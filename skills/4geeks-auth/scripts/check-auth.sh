#!/usr/bin/env bash
# Verifica la autenticación con 4Geeks: GET /v1/admissions/user/me
# Una sola acción. Nunca imprime el token ni el header.
# Salida: líneas RESULT=..., HTTP=..., NAME=... (solo el nombre en caso de éxito).
set -u

API="https://breathecode.herokuapp.com/v1/admissions/user/me"

# Detecta variable ausente o vacía, sin imprimir su valor.
if [ -z "${FOURGEEKS_STUDENT_TOKEN:-}" ]; then
  echo "RESULT=no_credential"
  exit 2
fi

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

# Sin -v. Los errores de curl se descartan para no mostrar detalles de la petición.
http_code="$(curl -sS --max-time 20 -o "$body" -w '%{http_code}' \
  -H "Authorization: Token ${FOURGEEKS_STUDENT_TOKEN}" \
  -H "Accept: application/json" \
  "$API" 2>/dev/null)" || http_code="000"

case "$http_code" in
  200)
    name="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
u = d["user"] if isinstance(d.get("user"), dict) else d
print(" ".join(x for x in (u.get("first_name"), u.get("last_name")) if x))
' "$body" 2>/dev/null)"
    echo "RESULT=active"
    echo "HTTP=200"
    echo "NAME=${name}"
    ;;
  401|403)
    echo "RESULT=invalid_token"
    echo "HTTP=${http_code}"
    exit 1
    ;;
  000)
    echo "RESULT=network_error"
    echo "HTTP=000"
    exit 3
    ;;
  502)
    echo "RESULT=unexpected_error"
    echo "HTTP=502"
    # El cuerpo nunca se imprime; solo se busca el texto del proxy de egreso.
    if grep -q "is not allowed for host" "$body" 2>/dev/null; then
      echo "DETAIL=host_no_permitido"
    fi
    exit 4
    ;;
  *)
    echo "RESULT=unexpected_error"
    echo "HTTP=${http_code}"
    exit 4
    ;;
esac
