#!/usr/bin/env bash
# Solo lectura. Nunca imprime el token ni el header Authorization. Sin curl -v.
# Corre en el Gateway: el secreto llega como variable con marcador opaco.
set -u

BASE="https://breathecode.herokuapp.com"

# Detecta variable ausente o vacía, sin imprimir su valor.
if [ -z "${FOURGEEKS_STUDENT_TOKEN:-}" ]; then
  echo "RESULT=no_credential"
  exit 2
fi

# Todas las respuestas van a archivos temporales que se borran al salir.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Traduce un código HTTP no exitoso a RESULT= y sale.
fail() {
  case "$1" in
    401|403) echo "RESULT=invalid_token"; echo "HTTP=$1"; exit 1 ;;
    000)     echo "RESULT=network_error"; echo "HTTP=000"; exit 3 ;;
    502)
      # $2 = archivo con el cuerpo de la respuesta (opcional); nunca se imprime.
      if [ -n "${2:-}" ] && grep -q "is not allowed for host" "$2" 2>/dev/null; then
        echo "RESULT=unexpected_error"; echo "HTTP=502"; echo "DETAIL=host_no_permitido"; exit 4
      fi
      echo "RESULT=unexpected_error"; echo "HTTP=502"; exit 4 ;;
    *)       echo "RESULT=unexpected_error"; echo "HTTP=$1"; exit 4 ;;
  esac
}

# Respuesta 200 que no es JSON válido (p. ej. una página HTML de error): unexpected_error.
invalid_json() {
  echo "RESULT=unexpected_error"; echo "HTTP=$1"; echo "DETAIL=respuesta_no_es_json"; exit 4
}

# GET de una sola página -> archivo. Errores de curl descartados (sin detalles de la petición).
http_get() {
  curl -sS --max-time 30 -o "$2" -w '%{http_code}' \
    -H "Authorization: Token ${FOURGEEKS_STUDENT_TOKEN}" \
    -H "Accept: application/json" \
    "$BASE$1" 2>/dev/null || true
}

# fetch_all <ruta[?query]> <salida.jsonl>: pagina con limit/offset hasta traer todo.
fetch_all() {
  local path="$1" out="$2" offset=0 limit=100 sep="?" code info more n guard=0
  case "$path" in *\?*) sep="&" ;; esac
  : > "$out"
  while :; do
    code="$(http_get "${path}${sep}limit=${limit}&offset=${offset}" "$tmp_dir/page.json")"
    [ "$code" = "200" ] || fail "$code" "$tmp_dir/page.json"
    info="$(python3 - "$tmp_dir/page.json" "$out" 2>/dev/null <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if isinstance(d, dict):
    items = d.get("results") or []
    more = 1 if d.get("next") else 0
else:
    items, more = d, 0
with open(sys.argv[2], "a") as f:
    for it in items:
        f.write(json.dumps(it) + "\n")
print(len(items), more)
PY
)" || invalid_json "$code"
    n="${info% *}"; more="${info#* }"
    [ "$more" = "1" ] && [ "$n" -gt 0 ] || break
    offset=$((offset + limit)); guard=$((guard + 1))
    [ "$guard" -lt 200 ] || break
  done
}

# Estado traducido: revision_status manda (APPROVED/REJECTED); si no, task_status.
PYSTATE='
def estado(t):
    rev = t.get("revision_status"); st = t.get("task_status")
    if rev == "APPROVED": return "aprobado"
    if rev == "REJECTED": return "rechazado"
    if st == "DONE": return "entregado"
    if st == "PENDING": return "pendiente"
    return str(st or "desconocido").lower()
def limpio(s): return " ".join(str(s or "(sin título)").split())
'

# Uso: check-progress.sh [filtro]   (filtro opcional: parte del nombre o slug del cohorte)
# Cohortes: /v1/admissions/academy/cohort/me devuelve 403 para estudiantes
# (exige academy_id), así que se leen de /v1/admissions/user/me (campo cohorts).
code="$(http_get "/v1/admissions/user/me" "$tmp_dir/me.json")"
[ "$code" = "200" ] || fail "$code" "$tmp_dir/me.json"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp_dir/me.json" 2>/dev/null || invalid_json "$code"
fetch_all "/v1/assignment/user/me/task" "$tmp_dir/tasks.jsonl"

python3 - "$tmp_dir/me.json" "$tmp_dir/tasks.jsonl" "${1:-}" <<PY
import json, sys, collections
$PYSTATE
me = json.load(open(sys.argv[1]))
tasks = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
filtro = " ".join(sys.argv[3].split()).lower()

cohortes = {}
for c in me.get("cohorts") or []:
    co = c.get("cohort")
    if isinstance(co, dict):
        cohortes[co.get("id")] = {
            "nombre": co.get("name") or co.get("slug") or "(sin nombre)",
            "slug": co.get("slug") or "",
            "estado": c.get("educational_status"),
        }

def pct(a, b): return "%.1f%%" % (100.0 * a / b) if b else "n/a"

if filtro:
    # Con filtro: coincide por nombre o slug, en cualquier estado educativo.
    alcance = {k: v for k, v in cohortes.items() if filtro in v["nombre"].lower() or filtro in v["slug"].lower()}
    if not alcance:
        print("RESULT=no_match")
        print("HTTP=200")
        print("FILTRO=" + filtro)
        print("COHORTES_ACTIVOS_DISPONIBLES:")
        for v in cohortes.values():
            if v["estado"] == "ACTIVE":
                print("  - " + limpio(v["nombre"]))
        sys.exit(5)
else:
    alcance = {k: v for k, v in cohortes.items() if v["estado"] == "ACTIVE"}

if filtro:
    tasks = [t for t in tasks if isinstance(t.get("cohort"), dict) and t["cohort"].get("id") in alcance]

total = len(tasks)
cuenta = collections.Counter(estado(t) for t in tasks)
orden = ["pendiente", "entregado", "aprobado", "rechazado"]
completadas = cuenta.get("entregado", 0) + cuenta.get("aprobado", 0)
proyectos = [t for t in tasks if t.get("task_type") == "PROJECT"]
proy_aprob = sum(1 for t in proyectos if estado(t) == "aprobado")

print("RESULT=ok")
print("HTTP=200")
if filtro:
    print("FILTRO=" + filtro)
    print("COHORTES_COINCIDENTES=%d" % len(alcance))
else:
    print("COHORTES_ACTIVOS=%d" % len(alcance))
print("TAREAS_TOTAL=%d" % total)
print("COMPLETADO=%s (%d de %d; entregado+aprobado)" % (pct(completadas, total), completadas, total))
print("DESGLOSE " + " ".join("%s=%d" % (e, cuenta.get(e, 0)) for e in orden + sorted(set(cuenta) - set(orden))))
print("PROYECTOS_APROBADOS=%s (%d de %d)" % (pct(proy_aprob, len(proyectos)), proy_aprob, len(proyectos)))

por_cohorte = collections.defaultdict(list)
for t in tasks:
    co = t.get("cohort")
    if isinstance(co, dict) and co.get("id") in alcance:
        por_cohorte[co["id"]].append(t)
for cid, ts in sorted(por_cohorte.items(), key=lambda kv: -len(kv[1])):
    hechas = sum(1 for t in ts if estado(t) in ("entregado", "aprobado"))
    print("COHORTE | %s | %s | %d de %d | %s" % (limpio(alcance[cid]["nombre"]), alcance[cid]["estado"], hechas, len(ts), pct(hechas, len(ts))))
sin = [v["nombre"] for cid, v in alcance.items() if cid not in por_cohorte]
if sin:
    print("COHORTES_SIN_TAREAS=%d" % len(sin))
PY
