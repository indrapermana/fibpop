# Copy/Paste Prompt for Codex / GitHub Copilot

You are implementing **FIBPOP**, a bilingual offline/online hidden-identity card game. Start by reading `README.md`, `agent/AGENTS.md`, the English tabletop rules, rules clarification register, 72-card JSON catalog, Architecture, and Development Plan **in that order**.

Our locked stack is Flutter (+ selective Flame) for Android/iOS and future web; Hono + TypeScript Workers for HTTP; Cloudflare Durable Objects + hibernating WebSockets + SQLite for authoritative online matches; independent pure TypeScript game engine, with matching Dart offline engine and cross-engine golden fixtures. Neon is deferred.

**Work only on M0 for this first task**. Inspect existing workspace first and do not overwrite user code. Scaffold a monorepo compatible with the proposed architecture. Add validation for the source card catalog (24 unique designs, 72 total copies), base game state/type definitions and fixture-test infrastructure. Set up lint, formatting, typecheck, test commands and sensible GitHub Actions CI. Write minimal local dev instructions for both Flutter and backend. Implement only the locked 2.1.0 rules and record remaining balance questions without modifying them. Do not deploy or connect external accounts yet.

At the end, run the available tests and report exact commands/results, changed files, and next smallest task. If dependencies cannot be installed due to network or environment restrictions, state the blocker clearly and leave coherent files behind.
