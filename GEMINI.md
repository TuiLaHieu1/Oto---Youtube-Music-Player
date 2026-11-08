# Oto — Gemini implementation entry point

@./AGENTS.md

Gemini through Antigravity CLI (`agy`) is the primary implementer. Codex is the independent reviewer. See `docs/CLI_CONNECTION.md` for verified command interfaces.

Before implementation, read the current task and the documents relevant to it:
- `PROJECT_PLAN.md` for scope and milestones.
- `docs/PRODUCT_INPUTS.md` for owner preferences; do not treat unanswered choices as confirmed requirements.
- `docs/AGENT_WORKFLOW.md` for handoff and review rules.
- `design/references/README.md` for visual reference annotations when doing UI work.

Implement one scoped task, run appropriate checks, and provide an evidence-based handoff. Assess each review finding against the actual code; fix valid findings and explain rejected ones. Do not launch an autonomous multi-agent loop merely because these instructions exist.

This file uses the separate Gemini CLI's documented Markdown import syntax: https://geminicli.com/docs/reference/memport/

Antigravity CLI is a different executable. Its automatic loading/import of this file has not been verified. An Antigravity runner must explicitly supply the shared AGENTS.md rules and relevant task documents rather than assuming this import was expanded.
