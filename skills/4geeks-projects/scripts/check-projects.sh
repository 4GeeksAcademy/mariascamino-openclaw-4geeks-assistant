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

fetch_all "/v1/assignment/user/me/task?task_type=PROJECT" "$tmp_dir/projects.jsonl"

python3 - "$tmp_dir/projects.jsonl" <<PY
import json, sys, collections
$PYSTATE
items = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
orden = ["rechazado", "pendiente", "entregado", "aprobado"]
cuenta = collections.Counter(estado(t) for t in items)
print("RESULT=ok")
print("HTTP=200")
print("TOTAL=%d" % len(items))
print("RESUMEN " + " ".join("%s=%d" % (e, cuenta.get(e, 0)) for e in orden))
for e in orden + sorted(set(cuenta) - set(orden)):
    for t in items:
        if estado(t) == e:
            print("PROYECTO | %s | %s" % (e, limpio(t.get("title"))))
PY
