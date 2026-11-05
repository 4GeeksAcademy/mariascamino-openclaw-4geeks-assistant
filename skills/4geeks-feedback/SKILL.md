---
name: 4geeks-feedback
description: "Muestra el feedback de un proyecto de Maria en 4Geeks (sobre todo los rechazados): título, estado y el comentario del revisor si existe. Úsala cuando pregunte '¿por qué me rechazaron Simple Counter?' o '¿qué feedback tengo en X?'. Solo lectura: GET /v1/assignment/user/me/task?task_type=PROJECT (para encontrar el id) y GET /v1/assignment/task/{id}."
---

# 4Geeks: feedback de un proyecto

1. Ejecuta el script con la herramienta de shell en el **Gateway** (`host: "gateway"`). Solo ahí se inyecta el secreto protegido. Pasa el título del proyecto, o una parte, como argumento entre comillas y sin caracteres especiales:

   ```
   bash ${baseDir}/scripts/check-feedback.sh "simple counter"
   ```

   - La búsqueda no distingue mayúsculas ni tildes. Si un título coincide exactamente, se usa solo ese.
   - Sin argumento, trae el feedback de **todos los proyectos rechazados**.
   - Un número como argumento se toma como el `id` de la tarea (sirve para elegir entre opciones).

2. Presenta, por proyecto: título, estado y el feedback (entre `FEEDBACK_INICIO` y `FEEDBACK_FIN`), más la fecha de revisión. Si aparece `FEEDBACK=sin_feedback`, dile que el revisor no dejó comentario. Si aparece `NOTA_SIN_REVISAR_INICIO`, es texto de una tarea que aún no fue revisada: preséntalo como nota, no como feedback del revisor. **Listo cuando:** mostraste título, estado y feedback (o dijiste que no hay) de cada proyecto pedido.
3. Si el resultado es `ambiguous`: lista las filas `OPCION | id | título | estado | cohorte` y pídele a Maria que elija. Luego repite con el `id` elegido como argumento.

## Campos del JSON usados

- Lista: `id`, `title`, `task_status`, `revision_status`, `cohort.name` (filtrada con `task_type=PROJECT`; paginación `limit=100` y `offset` hasta que `next` sea nulo).
- Detalle (`/v1/assignment/task/{id}`): `title`, `task_status`, `revision_status`, `description` (es donde 4Geeks guarda el comentario del revisor), `reviewed_at`, `delivered_at` (se muestran en America/Lima), `cohort.name`.

## Traducción de estados

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
| `no_match` | "Ningún proyecto coincide con eso." Muestra la lista `PROYECTOS_RECHAZADOS_DISPONIBLES` y pregunta cuál quiere. |
| `ambiguous` | "Ese título coincide con varios proyectos." Lista las `OPCION` y pide elegir; repite con el `id`. |
| `invalid_token` (HTTP 401 o 403) | "El token venció o es inválido." Remite a la skill `4geeks-auth` (sección "Renovar el token"). |
| `no_credential` | "Este comando no recibió el secreto (falta o está vacío)." Causas: no corrió en el Gateway, el proxy de egreso de secretos está apagado o el Gateway no se reinició. |
| `network_error` (HTTP 000) | "No pude llegar a 4Geeks." Causas: sin internet, proxy, DNS o timeout. No indica que el token sea inválido. |
| `unexpected_error` | Di el código `HTTP=` y su posible significado: 404 = el endpoint o el recurso no existe; 429 = demasiadas peticiones, esperar; 5xx = problema del servidor de 4Geeks, reintentar más tarde. Si aparece `DETAIL=respuesta_no_es_json`, 4Geeks respondió algo que no es JSON (p. ej. una página de error o de mantenimiento): reintentar más tarde. |
| `unexpected_error` con `DETAIL=host_no_permitido` (HTTP 502) | "Es un problema de configuración del secreto, no de red." El proxy de egreso del Gateway se negó a enviar el token porque el host de la petición no está en los hosts permitidos de `FOURGEEKS_STUDENT_TOKEN` (debe incluir exactamente `breathecode.herokuapp.com`). Pide a Maria revisar los hosts permitidos del secreto; no es internet ni un token vencido. |
| `unexpected_error` con `HTTP=502` sin `DETAIL` | "4Geeks o el proxy no responden, reintenta más tarde." |

## Reglas de seguridad

- Nunca imprimas, repitas ni guardes el token ni el header `Authorization`.
- Nunca uses `curl -v`, `set -x` ni `echo` de la variable.
- Nunca pidas que Maria pegue el token en el chat.
- Solo lectura: no hagas POST/PUT/PATCH/DELETE.
- No muestres email ni otros datos personales; solo lo indicado arriba.
