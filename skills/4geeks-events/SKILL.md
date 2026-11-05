---
name: 4geeks-events
description: "Muestra los próximos eventos de la academia de Maria en 4Geeks (máximo 10, los más próximos primero) con fecha y hora en America/Lima y si son online o presenciales. Úsala cuando pregunte '¿qué eventos hay?' o '¿hay algún workshop esta semana?'. Solo lectura: GET /v1/admissions/user/me (para el id de la academia) y GET /v1/events/all?upcoming=true&academy=<id>."
---

# 4Geeks: próximos eventos de mi academia

1. Ejecuta el script con la herramienta de shell en el **Gateway** (`host: "gateway"`). Solo ahí se inyecta el secreto protegido.

   ```
   bash ${baseDir}/scripts/check-events.sh
   ```

2. Presenta: la academia (`ACADEMIA=`) y los eventos (líneas `EVENTO | fecha hora (Lima) | online/presencial | tipo | esta_semana | título`), en el orden recibido (el más próximo primero), máximo 10. **Listo cuando:** mostraste título, fecha y hora (Lima) y online/presencial de cada evento.
   - **"¿Hay algún workshop esta semana?"**: filtra las líneas con `esta_semana=si` y cuyo tipo o título digan "workshop"; si no hay ninguna, dilo y menciona el próximo evento de cualquier tipo.
   - Si aparece `SIN_EVENTOS_DE_TU_ACADEMIA=1`: dile que su academia no tiene eventos próximos publicados. Las líneas `OTRO_EVENTO` son de **otras academias** (eventos generales de 4Geeks); preséntalas aparte y aclara de qué academia son.

## Campos del JSON usados

- Academia: `/v1/admissions/user/me` → `profile.profile_academy` si existiera; hoy ese campo **no existe** para estudiantes, así que se usa `cohorts[].cohort.academy.id` y `.name` (los cohortes ACTIVE pesan más).
- Eventos: `id` (sin duplicados), `title`, `starting_at`, `ending_at` (UTC, se convierten a America/Lima), `online_event` (true = online, false = presencial), `venue.title`/`venue.city`, `event_type.name`, `status` (solo ACTIVE), `academy.name`.
- Paginación: `limit=100` y `offset`; la API responde una lista simple (o un objeto con `results`/`next`) y el script se detiene cuando no llegan eventos nuevos.

## Resultados posibles

| RESULT | Qué decirle a Maria |
|---|---|
| `ok` | Presenta los datos como se indica arriba. |
| `no_academy` | "No pude determinar tu academia desde tu perfil." Pide revisar el perfil en 4Geeks; no inventes un id. |
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
