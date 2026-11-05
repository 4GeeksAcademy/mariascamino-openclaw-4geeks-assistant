---
name: 4geeks-projects
description: "Lista los proyectos de Maria en 4Geeks con su estado (pendiente, entregado, aprobado, rechazado). Úsala cuando pregunte '¿cuáles son mis proyectos?' o '¿en qué estado están mis proyectos?'. Solo lectura; una sola acción: GET /v1/assignment/user/me/task?task_type=PROJECT."
---

# 4Geeks: mis proyectos y su estado

1. Ejecuta el script con la herramienta de shell en el **Gateway** (`host: "gateway"`). Solo ahí se inyecta el secreto protegido. Puede tardar unos segundos porque pagina la API.

   ```
   bash ${baseDir}/scripts/check-projects.sh
   ```

2. Presenta: el total, el resumen por estado (`RESUMEN`) y la lista de proyectos agrupada por estado (líneas `PROYECTO | estado | título`). Orden: rechazado, pendiente, entregado, aprobado. **Listo cuando:** mostraste título y estado de cada proyecto.

## Campos del JSON usados

`title`, `task_status`, `revision_status`, `task_type` (filtrado en la API con `task_type=PROJECT`). Paginación: `limit=100` y `offset` hasta que `next` sea nulo.

## Traducción de estados

La API usa dos campos: `task_status` (PENDING, DONE) y `revision_status` (PENDING, APPROVED, REJECTED).

| Estado mostrado | Regla |
|---|---|
| aprobado | `revision_status = APPROVED` |
| rechazado (requiere correcciones) | `revision_status = REJECTED` |
| entregado | `task_status = DONE` y la revisión aún está PENDING |
| pendiente | `task_status = PENDING` |


## Resultados posibles

| RESULT | Qué decirle a Maria |
|---|---|
| `ok` | Presenta los datos como se indica arriba. |
| `invalid_token` (HTTP 401 o 403) | "El token venció o es inválido." Remite a la skill `4geeks-auth` (sección "Renovar el token"). |
| `no_credential` | "Este comando no recibió el secreto (falta o está vacío)." Causas: no corrió en el Gateway, el proxy de egreso de secretos está apagado o el Gateway no se reinició. |
| `network_error` (HTTP 000) | "No pude llegar a 4Geeks." Causas: sin internet, proxy, DNS o timeout. No indica que el token sea inválido. |
| `unexpected_error` | Di el código `HTTP=` y su posible significado: 404 = el endpoint cambió; 429 = demasiadas peticiones, esperar; 5xx = problema del servidor de 4Geeks, reintentar más tarde. Si aparece `DETAIL=respuesta_no_es_json`, 4Geeks respondió algo que no es JSON (p. ej. una página de error o de mantenimiento): reintentar más tarde. |
| `unexpected_error` con `DETAIL=host_no_permitido` (HTTP 502) | "Es un problema de configuración del secreto, no de red." El proxy de egreso del Gateway se negó a enviar el token porque el host de la petición no está en los hosts permitidos de `FOURGEEKS_STUDENT_TOKEN` (debe incluir exactamente `breathecode.herokuapp.com`). Pide a Maria revisar los hosts permitidos del secreto; no es internet ni un token vencido. |
| `unexpected_error` con `HTTP=502` sin `DETAIL` | "4Geeks o el proxy no responden, reintenta más tarde." |

## Reglas de seguridad

- Nunca imprimas, repitas ni guardes el token ni el header `Authorization`.
- Nunca uses `curl -v`, `set -x` ni `echo` de la variable.
- Nunca pidas que Maria pegue el token en el chat.
- Solo lectura: no hagas POST/PUT/PATCH/DELETE.
- No muestres email ni otros datos personales; solo lo indicado arriba.
