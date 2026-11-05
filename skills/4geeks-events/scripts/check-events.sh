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


# --- Academia del estudiante ---
# Uso: check-events.sh   (sin argumentos)
# El academy id sale de /v1/admissions/user/me: primero profile_academy (si existiera);
# si no, de cohorts[].cohort.academy (la academia de los cohortes, ACTIVE pesa más).
code="$(http_get "/v1/admissions/user/me" "$tmp_dir/me.json")"
[ "$code" = "200" ] || fail "$code" "$tmp_dir/me.json"
academy="$(python3 - "$tmp_dir/me.json" 2>/dev/null <<'PY'
import json, sys, collections
me = json.load(open(sys.argv[1]))
def acad(a):
    if isinstance(a, dict) and a.get("id") is not None:
        return a["id"], " ".join(str(a.get("name") or "").split())
    if isinstance(a, int):
        return a, ""
    return None
found = None
prof = me.get("profile") if isinstance(me.get("profile"), dict) else {}
for holder in (prof, me):
    pa = holder.get("profile_academy")
    for x in (pa if isinstance(pa, list) else [pa] if isinstance(pa, dict) else []):
        found = acad(x.get("academy")) if isinstance(x, dict) else None
        if found:
            break
    if found:
        break
if not found:
    cnt, names = collections.Counter(), {}
    for c in me.get("cohorts") or []:
        r = acad((c.get("cohort") or {}).get("academy"))
        if r:
            cnt[r[0]] += 2 if c.get("educational_status") == "ACTIVE" else 1
            names[r[0]] = r[1]
    if cnt:
        i = cnt.most_common(1)[0][0]
        found = (i, names[i])
if found:
    print(found[0], found[1])
PY
)" || invalid_json "$code"
academy_id="${academy%% *}"
academy_name="${academy#* }"
[ "$academy_name" = "$academy" ] && academy_name=""
case "$academy_id" in
  ''|*[!0-9]*) echo "RESULT=no_academy"; echo "HTTP=200"; exit 5 ;;
esac

# fetch_events <ruta?query> <salida.jsonl>: pagina con limit/offset; sin duplicados (por id).
# La API puede responder una lista simple o un objeto con results/next.
fetch_events() {
  local path="$1" out="$2" offset=0 limit=100 code info more new guard=0
  : > "$out"
  while :; do
    code="$(http_get "$path&limit=$limit&offset=$offset" "$tmp_dir/page.json")"
    [ "$code" = "200" ] || fail "$code" "$tmp_dir/page.json"
    info="$(python3 - "$tmp_dir/page.json" "$out" "$limit" 2>/dev/null <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); limit = int(sys.argv[3])
if isinstance(d, dict):
    items = d.get("results") or []
    more = 1 if d.get("next") else 0
else:
    items = d
    more = 1 if len(items) >= limit else 0
seen = set()
try:
    for l in open(sys.argv[2]):
        if l.strip():
            seen.add(json.loads(l).get("id"))
except Exception:
    pass
new = 0
with open(sys.argv[2], "a") as f:
    for it in items:
        if it.get("id") not in seen:
            seen.add(it.get("id")); new += 1
            f.write(json.dumps(it) + "\n")
print(new, more)
PY
)" || invalid_json "$code"
    new="${info% *}"; more="${info#* }"
    [ "$more" = "1" ] && [ "$new" -gt 0 ] || break
    offset=$((offset + limit)); guard=$((guard + 1))
    [ "$guard" -lt 50 ] || break
  done
}

fetch_events "/v1/events/all?upcoming=true&academy=$academy_id" "$tmp_dir/events.jsonl"

# Si la academia no tiene eventos próximos, se trae también la lista general (solo informativa).
if [ ! -s "$tmp_dir/events.jsonl" ]; then
  fetch_events "/v1/events/all?upcoming=true" "$tmp_dir/otros.jsonl"
else
  : > "$tmp_dir/otros.jsonl"
fi

python3 - "$tmp_dir/events.jsonl" "$tmp_dir/otros.jsonl" "$academy_id" "$academy_name" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
try:
    from zoneinfo import ZoneInfo
    LIMA = ZoneInfo("America/Lima")
except Exception:
    LIMA = timezone(timedelta(hours=-5))
DIAS = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
def limpio(s): return " ".join(str(s or "(sin título)").split())
def parse(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(LIMA)
    except Exception:
        return None
def cargar(p):
    return [json.loads(l) for l in open(p) if l.strip()]
ahora = datetime.now(LIMA)
sem = ahora.isocalendar()[:2]
def activos(items):
    out = []
    for e in items:
        if str(e.get("status") or "ACTIVE").upper() != "ACTIVE":
            continue
        d = parse(e.get("starting_at"))
        if d is not None and d < ahora - timedelta(hours=1):
            continue
        out.append((d, e))
    out.sort(key=lambda x: (x[0] is None, x[0] or ahora))
    return out
def linea(d, e, con_academia=False):
    fin = parse(e.get("ending_at"))
    if d:
        cuando = "%s %s %s" % (DIAS[d.weekday()], d.strftime("%Y-%m-%d"), d.strftime("%H:%M"))
        if fin:
            cuando += "-" + fin.strftime("%H:%M")
        cuando += " (Lima)"
        esta = "si" if d.isocalendar()[:2] == sem else "no"
    else:
        cuando, esta = str(e.get("starting_at")), "no"
    if e.get("online_event"):
        modo = "online"
    else:
        v = e.get("venue") if isinstance(e.get("venue"), dict) else {}
        lugar = limpio(v.get("title") or v.get("city") or "") if (v.get("title") or v.get("city")) else ""
        modo = "presencial" + (" (%s)" % lugar if lugar else "")
    et = e.get("event_type")
    tipo = limpio(et.get("name") if isinstance(et, dict) else et) if et else "-"
    extra = ""
    if con_academia and isinstance(e.get("academy"), dict):
        extra = " | academia=%s" % limpio(e["academy"].get("name"))
    return "EVENTO | %s | %s | %s | esta_semana=%s%s | %s" % (cuando, modo, tipo, esta, extra, limpio(e.get("title")))
propios = activos(cargar(sys.argv[1]))
otros = activos(cargar(sys.argv[2]))
print("RESULT=ok")
print("HTTP=200")
print("ACADEMIA=%s%s" % (sys.argv[3], (" (%s)" % sys.argv[4]) if sys.argv[4] else ""))
print("HOY=%s %s (Lima)" % (DIAS[ahora.weekday()], ahora.strftime("%Y-%m-%d %H:%M")))
print("TOTAL_PROXIMOS=%d" % len(propios))
print("MOSTRADOS=%d" % min(len(propios), 10))
for d, e in propios[:10]:
    print(linea(d, e))
if not propios:
    print("SIN_EVENTOS_DE_TU_ACADEMIA=1")
    print("OTRAS_ACADEMIAS_TOTAL=%d" % len(otros))
    for d, e in otros[:10]:
        print(linea(d, e, True).replace("EVENTO |", "OTRO_EVENTO |", 1))
PY
