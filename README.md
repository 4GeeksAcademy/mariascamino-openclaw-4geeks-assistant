# My 4Geeks Assistant: OpenClaw + 4Geeks API

4Geeks Academy project: teaching OpenClaw (agent **MariBot**) to answer questions about my progress in the course using the Student API (BreatheCode).

- 📄 **Deliverable:** [`SKILL_LOG.md`](./SKILL_LOG.md): setup, discovery conversation, and for each skill the prompt, description, endpoint and test result.
- 🧩 **Skills:** [`skills/`](./skills): 4 core (`auth`, `projects`, `pending`, `progress`) + 2 extended (`events`, `feedback`).
- 🔐 **Token:** stored in the OpenClaw secret store (write-only, allowed host `breathecode.herokuapp.com`) and injected by the Gateway's egress proxy. It does not appear in any file in this repo.
