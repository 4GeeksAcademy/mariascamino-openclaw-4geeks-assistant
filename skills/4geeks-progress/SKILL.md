---
name: 4geeks-progress
description: "Resumen del progreso de Maria en 4Geeks: cohortes activos, % completado, desglose por estado y % de proyectos aprobados, con filtro opcional por nombre de cohorte. Úsala cuando pregunte '¿cuánto llevo del curso?', '¿cómo voy?' o '¿cómo voy en <cohorte>?'. Solo lectura: GET /v1/admissions/user/me (cohortes) y GET /v1/assignment/user/me/task (todas las tareas)."
---

# 4Geeks: resumen de progreso

## Pasos

1. Ejecuta el script con la herramienta de shell en el **Gateway** (`host: "gateway"`). Solo ahí se inyecta el secreto protegido. Puede tardar unos segundos porque pagina la API.

   ```
   bash ${baseDir}/scripts/check-progress.sh
   ```

   **Filtro opcional por cohorte:** si Maria nombra un cohorte ("¿cómo voy en Docker?", "progreso de Tailwind"), pasa una parte de su nombre o slug como argumento, entre comillas y sin caracteres especiales:

   ```
   bash ${baseDir}/scripts/check-progress.sh "docker"
   ```

   La búsqueda no distingue mayúsculas y coincide con el nombre o el slug del cohorte, en cualquier estado educativo (ACTIVE, GRADUATED, POSTPONED). Con filtro, el % completado, el desglose y los proyectos aprobados se calculan solo con las tareas de los cohortes coincidentes. Sin filtro se usan todas las tareas y los cohortes ACTIVE.

2. Presenta: cohortes (`COHORTES_ACTIVOS`, o `COHORTES_COINCIDENTES` si hubo filtro, y las filas `COHORTE` con más tareas), el % completado (`COMPLETADO`), el desglose por estado (`DESGLOSE`) y el % de proyectos aprobados (`PROYECTOS_APROBADOS`). Si hay muchas filas de cohorte, muestra las 5 con más tareas y ofrece el resto. **Listo cuando:** mostraste cohorte(s), % completado, desglose y % de proyectos aprobados.

## Fórmulas

- % completado = (entregado + aprobado) / total de tareas.
- % de proyectos aprobados = proyectos aprobados / total de proyectos.
- Estados: ver la tabla de traducción en la skill `4geeks-projects` (aprobado, rechazado, entregado, pendiente). Un rechazado **no** cuenta como completado.

## Campos del JSON usados

- Tareas: `task_status`, `revision_status`, `task_type`, `cohort.id`. Paginación: `limit=100` y `offset` hasta que `next` sea nulo.
- Cohortes: `cohorts[].educational_status` (ACTIVE), `cohorts[].cohort.id`, `cohorts[].cohort.name`, `cohorts[].cohort.slug`.

## Nota sobre el endpoint de cohortes

`GET /v1/admissions/academy/cohort/me` responde **403** ("Missing academy_id") con un token de estudiante. El script obtiene los cohortes de `GET /v1/admissions/user/me` (campo `cohorts`), que es la misma información.

## Resultados posibles

| RESULT | Qué decirle a Maria |
|---|---|
| `ok` | Presenta los datos como se indica arriba. |
| `no_match` | "Ningún cohorte coincide con ese filtro." Muestra la lista `COHORTES_ACTIVOS_DISPONIBLES` y pregunta cuál quiere. |
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
