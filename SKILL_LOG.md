# SKILL_LOG — My 4Geeks Assistant (OpenClaw)

**Student:** María Camino
**OpenClaw:** 2026.10.9 · Node 26.13.0 · Model: Claude Sonnet (Anthropic API key)
**4Geeks API base URL:** `https://breathecode.herokuapp.com`

---

## 0. Setup and security

### Installation
- OpenClaw installed with the official installer (`curl -fsSL https://openclaw.ai/install.sh | bash`).
- The installer updated Node from **26.8.1 (vulnerable to CVE-2026-111497, Brotli)** to **26.13.0 (patched)**.
- Gateway installed as a LaunchAgent service, bound only to **loopback (127.0.0.1:18789)**. Verified with `openclaw gateway status`.

### Hardening applied
| Change | Command | Why |
|---|---|---|
| Disable Chrome cookie import | `openclaw config set browser.allowSystemProfileImport false` | The 4Geeks token is a cookie (`4g_tok`); the agent must not be able to read it on its own |
| Disable legacy browser-relay auth | `openclaw config set browser.extensionRelay.allowLegacyAuth false` | Weaker legacy method, not in use |
| Disable 36 unavailable skills | `openclaw doctor` → Yes | Less attack surface and less noise for the model |
| Memory search without OpenAI | `memory.search.provider = none` | No OpenAI key; keyword-based search |
| Delete 2 failed xAI credentials | `openclaw models auth logout xai:...` | Unused credentials get deleted |
| Rotate the gateway token and move it to the store | `openssl rand -hex 32 \| openclaw secrets store set GATEWAY_AUTH_TOKEN --kind secret --value-file -` + `openclaw secrets configure` | It was in plain text in `openclaw.json` |

### Storing the 4Geeks token
- Copied from the `4g_tok` cookie (DevTools → Application → Cookies → learn.4geeks.com).
- Stored **without showing it on screen or in the shell history**:
  ```bash
  pbpaste | openclaw secrets store set FOURGEEKS_STUDENT_TOKEN --kind secret --allow-host breathecode.herokuapp.com --value-file -
  pbcopy < /dev/null
  ```
- Result of `openclaw secrets store list`:
  ```
  FOURGEEKS_STUDENT_TOKEN [secret] (write-only); allowed hosts: breathecode.herokuapp.com
  GATEWAY_AUTH_TOKEN [secret] (write-only); allowed hosts: none
  ```
- **Protections:** write-only (not even the CLI can read it back) + `--allow-host` (it can only be used against the 4Geeks API, which mitigates exfiltration via prompt injection).

### Audit
- `openclaw secrets audit`: from `plaintext=4` → **`plaintext=1`**, `unresolved=0`.
- **Known risk:** the Anthropic API key remains in plain text in the shared auth-profile store (`~/.openclaw/state/openclaw.sqlite`). OpenClaw 2026.10.9 cannot migrate it yet. Mitigation: key dedicated to this project, monthly spending cap, file outside any repo, gateway on loopback.

---

## 1. Discovery conversation

**Initial prompt:**
> Quiero darte la capacidad de conectarte a mi cuenta de 4Geeks usando mi token de estudiante, sin que yo tenga que escribir código. ¿Qué necesitamos hacer?
>
> Contexto: mi token ya está guardado en el secret store de OpenClaw como `FOURGEEKS_STUDENT_TOKEN` (kind secret, allowed host `breathecode.herokuapp.com`). La API es `https://breathecode.herokuapp.com` y se autentica con el header `Authorization: Token <token>`. Regla: nunca me muestres, repitas ni escribas el token en un archivo o mensaje. Quiero construir skills pequeñas, cada una con una sola acción de la API.

**What OpenClaw did and diagnosed:**
- It confirmed the secret exists in the store (kind secret, allowed host correct) **without seeing its value**.
- It made a test call → **HTTP 401 "No credentials provided"**.
- Cause: protected secrets are only injected into commands when `secrets.egressProxy.enabled` is active, and that setting was not configured.
- How the egress proxy works: commands receive an **opaque placeholder** in `$FOURGEEKS_STUDENT_TOKEN`; the Gateway swaps it for the real token **only** in HTTPS requests to `breathecode.herokuapp.com`. The token never goes through the model, the chat, or any file.

**What OpenClaw proposed:**
1. Enable the secrets egress proxy (Gateway config change + restart). **Asked for my approval.**
2. Verify with a read-only call, showing only the HTTP code and non-sensitive fields.
3. Build small skills (folder + `SKILL.md` + short `curl` script, with no `-v`, no echoing the header, no token in files), one API action each.
4. Leave write actions (such as delivering a task) for later, with my confirmation.

**What it asked me for:** approval to enable the egress proxy, and a name for the agent.

**My adjustments to its proposal:**
- Use the documented endpoint for authentication (`/v1/admissions/user/me`) instead of `/v1/auth/user/me`.
- Align the skills with the 4 core skills of the project (authenticate, projects, pending, progress) instead of a generic `4geeks-assignments` skill that would mix projects and pending work.
- Approval **step by step**, not a blanket "carry on without asking", so I can test and document each skill.

## 2. Core skills

### Skill 1 — Authenticate (`4geeks-auth`)
- **Prompt:** "Creemos la Skill 1: Autenticar. Quiero poder preguntarte cosas como '¿mi conexión con 4Geeks funciona?' o '¿mi token sigue válido?' y que verifiques la sesión con `GET /v1/admissions/user/me`." + requirements: one action only, show only the name on 200, renewal instructions on 401/403 without asking me to paste the token, never print the token or the header, no `curl -v`. I asked to **review the `SKILL.md` and the script before saving**.
- **What it does:** checks that `FOURGEEKS_STUDENT_TOKEN` is accepted by the API. The script (`scripts/check-auth.sh`) returns `RESULT=` (`active`, `invalid_token`, `no_credential`, `network_error`, `unexpected_error`) and the `SKILL.md` says how to explain each case. It runs on the Gateway (`host: "gateway"`), where the egress proxy injects the secret.
- **Endpoint:** `GET /v1/admissions/user/me`
- **Review changes (code review of the agent's proposal):**
  1. Confirmed that the header uses the variable `${FOURGEEKS_STUDENT_TOKEN}` (the name, never the value).
  2. Empty-variable check: `[ -z "${FOURGEEKS_STUDENT_TOKEN:-}" ]`.
  3. Renewal flow swapped for the tested method (`pbpaste | wc -c` → `pbpaste | … --value-file -` → `pbcopy < /dev/null` → `openclaw secrets reload`).
  4. The 401 test was run on a copy outside `skills/`, deleted afterwards.
- **Test:**

  | Case | Output |
  |---|---|
  | Real token | `RESULT=active`, `HTTP=200`, `NAME=Maria Camino` |
  | Fake token (temporary copy) | `RESULT=invalid_token`, `HTTP=401` |

- **Not tested:** `no_credential`, `network_error`, `unexpected_error`, and the renewal flow (it would modify the real secret).

### Shared design pattern (skills 2–6)
All skills reuse the reviewed `4geeks-auth` pattern:
- Script in `skills/<name>/scripts/check-*.sh` that prints structured lines (`RESULT=`, `HTTP=`, …); the `SKILL.md` explains how to present each result.
- Runs on the Gateway (`host: "gateway"`), where the egress proxy swaps the placeholder `$FOURGEEKS_STUDENT_TOKEN` for the real token **only** towards `breathecode.herokuapp.com`.
- `curl` without `-v`; response in a temporary file deleted with `trap`; read-only (no POST/PUT/PATCH/DELETE).
- Uniform error handling: `401/403 → invalid_token`, `000 → network_error`, `502 + "is not allowed for host" → DETAIL=host_no_permitido` (secret misconfiguration), other `502`/`5xx`/`404`/`429 → unexpected_error`, HTML instead of JSON → `DETAIL=respuesta_no_es_json`.
- Pagination with `limit=100` / `offset` until `next` is null.
- Before writing each skill, the agent made a read-only call to confirm the **real JSON fields**.

**Prompt for skills 2, 3 and 4** (session "Continuar skills 4Geeks"):
> Construye las Skills 2, 3 y 4 en este orden, sin esperarme entre una y otra, cada una en su propia carpeta en skills/, con el mismo patrón de seguridad de 4geeks-auth […]. Antes de escribir cada una haz una llamada de solo lectura para confirmar los campos reales del JSON, y pagina con limit/offset hasta traer todo. [+ endpoint, states to show and sample phrases for each skill]. Al final un solo reporte con, por skill: carpeta, endpoint, campos del JSON usados y la salida real de la prueba (títulos y conteos sí; token y email no). No hagas commit.

_Note: skills 2–4 had been created in an earlier session (Nov 2, reviewed one by one: projects approved, 502 handling added to all four). With this prompt the agent re-checked them against the real API and re-ran them._

### Skill 2 — Get my projects (`4geeks-projects`)
- **What it does:** lists my assigned projects with their status, translated: **pending** / **submitted** / **graded** (graded = approved, or rejected and needing corrections).
- **Endpoint:** `GET /v1/assignment/user/me/task?task_type=PROJECT`
- **JSON fields:** `title`, `task_status`, `revision_status`, `task_type`; envelope `count`, `next`, `results`.
- **Status logic (finding):** `revision_status=APPROVED` → approved; `revision_status=REJECTED` → rejected; `task_status=DONE` with review pending → submitted; `task_status=PENDING` → pending.
- **Test:** `RESULT=ok HTTP=200 TOTAL=69` → rejected=3, pending=14, submitted=0, approved=52.
  Rejected: Building a website collaborative · Simple Counter · EduTrack Data Audit — Related Tables.

### Skill 3 — Get pending work (`4geeks-pending`)
- **What it does:** shows what I still have to do: pending tasks **plus** rejected ones that need corrections, grouped by type (projects first) with the total.
- **Endpoints:** `GET /v1/assignment/user/me/task?task_status=PENDING` and `GET /v1/assignment/user/me/task?revision_status=REJECTED` (same endpoint, two filters, merged without duplicates by `id`).
- **JSON fields:** `id`, `title`, `task_type`, `task_status`, `revision_status`.
- **API finding:** `task_status=PENDING,REJECTED` does **not** filter by several values (it returns only the PENDING ones), and `REJECTED` is a `revision_status`, not a `task_status` (those tasks stay as `DONE`). That's why two queries are needed.
- **Test:** `RESULT=ok HTTP=200 TOTAL=216` (213 pending + 3 rejected) → projects 17, exercises 162, lessons 36, quizzes 1.

### Skill 4 — Progress summary (`4geeks-progress`)
- **What it does:** how far along I am: active cohorts, % completed, breakdown by status, and % of approved projects shown separately. It can filter by cohort ("¿cómo voy en Docker?").
- **Endpoints:** `GET /v1/admissions/user/me` (field `cohorts`) + `GET /v1/assignment/user/me/task` (all tasks).
- **Change from the original plan:** `GET /v1/admissions/academy/cohort/me` returns **403 "Missing academy_id"** with a student token; the agent got the cohorts from `user/me`, which carries the same data.
- **JSON fields:** `cohorts[].educational_status`, `cohorts[].cohort.{id,name,slug}`; tasks: `task_status`, `revision_status`, `task_type`, `cohort.id`.
- **Formula decision:** completed = submitted + approved; **rejected does not count** as completed (it isn't finished yet).
- **Test:** `RESULT=ok HTTP=200` → 327 tasks · **33.9 % completed** (111/327) · pending=213 submitted=55 approved=56 rejected=3 · **approved projects 75.4 %** (52/69).

---

## 3. Extended skills

**Prompt for skills 5 and 6:**
> Ahora las 2 skills extendidas, mismo patrón de seguridad y mismo flujo (confirma campos reales con una llamada de solo lectura, crea, prueba, sin esperarme entre una y otra). SKILL 5 4geeks-events: próximos eventos de mi academia […] SKILL 6 4geeks-feedback: feedback de un proyecto, sobre todo de los rechazados […] Pruébala con los 3 proyectos rechazados. Al final un solo reporte […]. Sin commit y sin tocar otros archivos.

**Why these two:** events answer "is there anything coming up I should attend?" without opening the platform; feedback answers the most useful question after "what's pending": **why** a project was rejected and what to fix.

### Skill 5 — Upcoming events (`4geeks-events`)
- **What it does:** upcoming events for my academy (max. 10, soonest first), with date and time in America/Lima, online/in person, type and an `esta_semana=si/no` flag. If my academy has none, it says so and separately lists events from other academies.
- **Endpoints:** `GET /v1/admissions/user/me` (academy id) + `GET /v1/events/all?upcoming=true&academy=<id>`.
- **API finding:** `profile_academy` does not exist in the student's response; the academy comes from `cohorts[].cohort.academy` (id 7, 4Geeks Latam).
- **JSON fields:** `id`, `title`, `starting_at`, `ending_at` (UTC → Lima), `online_event`, `venue`, `event_type.name`, `status`, `academy.name`.
- **Test:**
  ```
  RESULT=ok HTTP=200
  ACADEMIA=7 (4Geeks Latam)
  TOTAL_PROXIMOS=0 MOSTRADOS=0
  SIN_EVENTOS_DE_TU_ACADEMIA=1 OTRAS_ACADEMIAS_TOTAL=4
  OTRO_EVENTO | mar 2026-11-17 13:30-14:30 (Lima) | online | Coding with AI | esta_semana=no | academia=4Geeks.com | El Agente Caza-Ofertas… (DÍA 1)
  … (3 more)
  ```
  Error tests: fake token → `invalid_token` (401); empty secret → `no_credential`.

### Skill 6 — Feedback on a project (`4geeks-feedback`)
- **What it does:** given a project title (or part of it), shows its status and the reviewer's comment. If it matches several, it lists the options; with no argument, it brings the rejected ones.
- **Endpoints:** `GET /v1/assignment/user/me/task?task_type=PROJECT` (look up the `id`) → `GET /v1/assignment/task/{id}` (detail). A tightly related set: look up + read a single task.
- **API finding:** there is no `feedback` field; the reviewer's comment lives in `description`, and it's only treated as feedback if the task has already been reviewed.
- **JSON fields:** list: `id`, `title`, `task_status`, `revision_status`, `cohort.name`; detail: `title`, `task_status`, `revision_status`, `description`, `reviewed_at`, `delivered_at`, `cohort.name`.
- **Test with the 3 rejected projects:**

  | Project | Feedback (summary) |
  |---|---|
  | Simple Counter (802086) | Use components to map the seconds separately with a formula, not by incrementing a variable |
  | Building a website collaborative (781806) | First and second heading are missing |
  | EduTrack Data Audit — Related Tables (1011874) | Rename `erd-diagram (1).png` to `diagram.png` and update the link |

  Other cases: "Command Line Challenge" → `ambiguous` (3 options); "zzz nada" → `no_match`; fake token → 401; empty secret → `no_credential`.

---

## 4. Final security check (before publishing this repo)
- No skill contains the token: the scripts use only the **variable name** `${FOURGEEKS_STUDENT_TOKEN}`, and at runtime they receive an opaque placeholder.
- `allowed hosts: breathecode.herokuapp.com` validated: a request to another host was rejected by the proxy (502 `is not allowed for host`).
- The token and my email did not appear in any output.
- Automated scan of the 6 skill folders in `skills/` before pushing:
  - `Authorization` lines: all 6 use `Token ${FOURGEEKS_STUDENT_TOKEN}` (variable name only).
  - Strings of ≥32 opaque characters: none (only the constant name `PROYECTOS_RECHAZADOS_DISPONIBLES`).
  - Emails: none. `curl -v` / `set -x` / `echo` of the variable: none. `POST/PUT/PATCH/DELETE` methods: none.
  - Only host used: `https://breathecode.herokuapp.com`. `bash -n` with no syntax errors in all 6 scripts.
- `.gitignore` in this repo excludes `.env*`, `*.sqlite*`, `*.db`, `*.log`, `openclaw.json`, `memory/`.

## 5. Repository contents
```
SKILL_LOG.md          ← main deliverable
skills/
  4geeks-auth/        SKILL.md + scripts/check-auth.sh
  4geeks-projects/    SKILL.md + scripts/check-projects.sh
  4geeks-pending/     SKILL.md + scripts/check-pending.sh
  4geeks-progress/    SKILL.md + scripts/check-progress.sh
  4geeks-events/      SKILL.md + scripts/check-events.sh
  4geeks-feedback/    SKILL.md + scripts/check-feedback.sh
```
The skills live in `~/.openclaw/workspace/skills/` on my machine; this is a copy for review. To use them, the secret `FOURGEEKS_STUDENT_TOKEN` (kind secret, allowed host `breathecode.herokuapp.com`) and `secrets.egressProxy.enabled=true` are required.
