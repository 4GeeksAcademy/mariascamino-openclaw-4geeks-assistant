---
name: 4geeks-pending
description: "Muestra lo que a Maria todavía le falta en 4Geeks: tareas pendientes más las rechazadas que debe corregir, agrupadas por tipo con los proyectos primero y el total. Úsala cuando pregunte '¿qué tengo pendiente?' o '¿qué me falta entregar?'. Solo lectura: GET /v1/assignment/user/me/task con task_status=PENDING y revision_status=REJECTED."
---

# 4Geeks: lo que me falta

1. Ejecuta el script con la herramienta de shell en el **Gateway** (`host: "gateway"`). Solo ahí se inyecta el secreto protegido. Puede tardar unos segundos porque pagina la API.

   ```
   bash ${baseDir}/scripts/check-pending.sh
   ```

2. Presenta: el total (`TOTAL`), cuántos son pendientes y cuántos rechazados (`RESUMEN`), y los grupos por tipo con los **proyectos primero**. Los rechazados aparecen primero dentro de cada tipo y hay que corregirlos. Para cada tipo da el conteo; lista los títulos de los proyectos siempre, y de los demás tipos los primeros 10, ofreciendo el resto si Maria lo pide. **Listo cuando:** mostraste el total y los grupos.

## Campos del JSON usados

`id` (para evitar duplicados), `title`, `task_type`, `task_status`, `revision_status`. Paginación: `limit=100` y `offset` hasta que `next` sea nulo.

## Nota sobre REJECTED

El filtro `task_status` **no acepta varios valores**: `task_status=PENDING,REJECTED` se ignora y devuelve solo los PENDING. Además, REJECTED no es un `task_status` sino un `revision_status` (esas tareas quedan con `task_status=DONE`). Por eso el script hace dos consultas al mismo endpoint (`task_status=PENDING` y `revision_status=REJECTED`) y las une sin duplicados.


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
