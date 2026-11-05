---
name: 4geeks-auth
description: "Verifica si la conexión con 4Geeks funciona y si el token de estudiante sigue válido (GET /v1/admissions/user/me). Úsala cuando Maria pregunte '¿mi conexión con 4Geeks funciona?', '¿mi token sigue válido?', '¿mi sesión de 4Geeks está activa?'. Solo verifica autenticación; no lee proyectos ni tareas."
---

# 4Geeks: verificar autenticación

Una sola acción: comprobar que `FOURGEEKS_STUDENT_TOKEN` es aceptado por la API de 4Geeks.

## Pasos

1. Ejecuta el script con la herramienta de shell en el **Gateway** (`host: "gateway"`).
   Solo ahí se inyecta el secreto protegido.

   ```
   bash ${baseDir}/scripts/check-auth.sh
   ```

2. Lee la línea `RESULT=` de la salida y responde según la tabla.
   **Listo cuando:** respondiste con el mensaje que corresponde al resultado y nada más.

| RESULT | Qué decirle a Maria |
|---|---|
| `active` (HTTP 200) | "Tu sesión con 4Geeks está activa." Muestra solo el nombre (`NAME=`). No muestres email ni otros datos. |
| `invalid_token` (HTTP 401 o 403) | "El token venció o es inválido." Da las instrucciones de renovación de abajo. |
| `no_credential` | "Este comando no recibió el secreto (falta o está vacío)." Causas probables: no corrió en el Gateway, el proxy de egreso de secretos (`secrets.egressProxy.enabled`) está apagado, el Gateway no se reinició tras activarlo, o el secreto está vacío. |
| `network_error` (HTTP 000) | "No pude llegar a 4Geeks." Causas probables: sin internet, proxy o DNS. Esto no indica que el token sea inválido. |
| `unexpected_error` | Di el código `HTTP=` y su posible significado: 404 = el endpoint cambió; 429 = demasiadas peticiones, esperar; 5xx = el servidor de 4Geeks tiene un problema, reintentar más tarde; otro = reportar el código tal cual. |
| `unexpected_error` con `DETAIL=host_no_permitido` (HTTP 502) | "Es un problema de configuración del secreto, no de red." El proxy de egreso del Gateway se negó a enviar el token porque el host de la petición no está en los hosts permitidos de `FOURGEEKS_STUDENT_TOKEN` (debe incluir exactamente `breathecode.herokuapp.com`). Pide a Maria revisar los hosts permitidos del secreto; no es internet ni un token vencido. |
| `unexpected_error` con `HTTP=502` sin `DETAIL` | "4Geeks o el proxy no responden, reintenta más tarde." |

## Renovar el token (401/403)

1. En el navegador, entra a 4Geeks con tu sesión y copia de nuevo el valor de la cookie `4g_tok` (queda en el portapapeles).
2. En tu terminal, ejecuta estos cuatro comandos en orden:

   ```
   pbpaste | wc -c
   pbpaste | openclaw secrets store set FOURGEEKS_STUDENT_TOKEN --kind secret --allow-host breathecode.herokuapp.com --value-file -
   pbcopy < /dev/null
   openclaw secrets reload
   ```

   - `pbpaste | wc -c`: cuenta los caracteres del portapapeles sin mostrarlos. Debe dar unos 40; si da 0 o un número muy distinto, no copiaste el valor correcto.
   - `pbpaste | openclaw secrets store set ... --value-file -`: guarda el portapapeles como secreto protegido, permitido solo para `breathecode.herokuapp.com`. El valor viaja por stdin y nunca aparece en pantalla ni en el historial.
   - `pbcopy < /dev/null`: vacía el portapapeles para que el token no se quede copiado.
   - `openclaw secrets reload`: hace que el Gateway recargue el store.
3. Empieza una conversación o corrida nueva y repite la verificación. El Gateway toma los cambios del store solo en corridas nuevas.

## Reglas de seguridad

- Nunca pidas que Maria pegue el token en el chat.
- Nunca imprimas, repitas ni guardes el token ni el header `Authorization`.
- Nunca uses `curl -v`, `set -x` ni `echo` de la variable.
- No agregues otras llamadas a la API en esta skill.
