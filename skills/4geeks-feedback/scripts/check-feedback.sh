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


# Uso: check-feedback.sh [título | parte del título | id numérico]
# Sin argumento: feedback de todos los proyectos rechazados.
query="${1:-}"

fetch_all "/v1/assignment/user/me/task?task_type=PROJECT" "$tmp_dir/projects.jsonl"

python3 - "$tmp_dir/projects.jsonl" "$tmp_dir/ids" "$query" <<'PY'
import json, sys, unicodedata
def estado(t):
    rev = t.get("revision_status"); st = t.get("task_status")
    if rev == "APPROVED": return "aprobado"
    if rev == "REJECTED": return "rechazado (requiere correcciones)"
    if st == "DONE": return "entregado"
    if st == "PENDING": return "pendiente"
    return str(st or "desconocido").lower()
def limpio(s): return " ".join(str(s or "(sin título)").split())
def norm(s):
    s = unicodedata.normalize("NFKD", " ".join(str(s or "").split()))
    return "".join(c for c in s if not unicodedata.combining(c)).casefold()
items = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
q = norm(sys.argv[3])
if not q:
    sel = [t for t in items if t.get("revision_status") == "REJECTED"]
elif q.isdigit():
    sel = [t for t in items if str(t.get("id")) == q]
else:
    sel = [t for t in items if q in norm(t.get("title"))]
    exactos = [t for t in sel if norm(t.get("title")) == q]
    if exactos:
        sel = exactos
if q and not sel:
    print("RESULT=no_match"); print("HTTP=200"); print("BUSQUEDA=" + limpio(sys.argv[3]))
    print("PROYECTOS_RECHAZADOS_DISPONIBLES:")
    for t in items:
        if t.get("revision_status") == "REJECTED":
            print("  - %s" % limpio(t.get("title")))
    sys.exit(5)
if q and len(sel) > 1:
    print("RESULT=ambiguous"); print("HTTP=200"); print("BUSQUEDA=" + limpio(sys.argv[3])); print("COINCIDENCIAS=%d" % len(sel))
    for t in sel[:15]:
        co = t.get("cohort") if isinstance(t.get("cohort"), dict) else {}
        print("OPCION | id=%s | %s | %s | cohorte=%s" % (t.get("id"), limpio(t.get("title")), estado(t), limpio(co.get("name"))))
    sys.exit(6)
with open(sys.argv[2], "w") as f:
    for t in sel:
        f.write("%s\n" % t.get("id"))
PY
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

n=0
for id in $(cat "$tmp_dir/ids"); do
  case "$id" in ''|*[!0-9]*) continue ;; esac
  code="$(http_get "/v1/assignment/task/$id" "$tmp_dir/task-$id.json")"
  [ "$code" = "200" ] || fail "$code" "$tmp_dir/task-$id.json"
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp_dir/task-$id.json" 2>/dev/null || invalid_json "$code"
  n=$((n + 1))
done

python3 - "$tmp_dir" <<'PY'
import json, sys, glob
from datetime import datetime, timezone, timedelta
try:
    from zoneinfo import ZoneInfo
    LIMA = ZoneInfo("America/Lima")
except Exception:
    LIMA = timezone(timedelta(hours=-5))
def estado(t):
    rev = t.get("revision_status"); st = t.get("task_status")
    if rev == "APPROVED": return "aprobado"
    if rev == "REJECTED": return "rechazado (requiere correcciones)"
    if st == "DONE": return "entregado"
    if st == "PENDING": return "pendiente"
    return str(st or "desconocido").lower()
def limpio(s): return " ".join(str(s or "(sin título)").split())
def fecha(s):
    if not s: return "-"
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(LIMA).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return str(s)
ids = [l.strip() for l in open(sys.argv[1] + "/ids") if l.strip()]
print("RESULT=ok")
print("HTTP=200")
print("PROYECTOS=%d" % len(ids))
if not ids:
    print("SIN_PROYECTOS_RECHAZADOS=1")
for i in ids:
    try:
        t = json.load(open("%s/task-%s.json" % (sys.argv[1], i)))
    except Exception:
        continue
    co = t.get("cohort") if isinstance(t.get("cohort"), dict) else {}
    print("---")
    print("PROYECTO | %s" % limpio(t.get("title")))
    print("ID | %s" % t.get("id"))
    print("ESTADO | %s" % estado(t))
    print("COHORTE | %s" % limpio(co.get("name")))
    print("ENTREGADO | %s (Lima)" % fecha(t.get("delivered_at")))
    print("REVISADO | %s (Lima)" % fecha(t.get("reviewed_at")))
    texto = str(t.get("description") or "").replace("\r\n", "\n").strip()
    revisado = t.get("revision_status") in ("APPROVED", "REJECTED")
    if texto and revisado:
        print("FEEDBACK_INICIO")
        print(texto[:3000] + ("…" if len(texto) > 3000 else ""))
        print("FEEDBACK_FIN")
    elif texto:
        print("NOTA_SIN_REVISAR_INICIO")
        print(texto[:3000] + ("…" if len(texto) > 3000 else ""))
        print("NOTA_SIN_REVISAR_FIN")
    else:
        print("FEEDBACK=sin_feedback")
PY
