# Service Desk GPT Audit

## Summary
This audit reviews the current "Service-desk-gpt" configuration, focusing on structural consistency, runtime assets, and authoring hygiene. The findings below highlight friction points observed while reading the existing instructions, prompts, runtime assets, and artifacts, followed by concrete improvement suggestions.

## Key Findings & Recommendations

### 1. Align artifact file formats with stated plain-text requirements
- **Observation:** `runtime_layout.ini` advertises `.txt` artifacts that are "scrubbed to plain text," yet the `artifacts/` directory still ships `.md` templates containing Markdown bullets and separators (for example, hyphen lists and the ASCII bar in the escalation note). 【F:Projects/Custom GPTs/Service-desk-gpt/runtime_layout.ini†L12-L15】【F:Projects/Custom GPTs/Service-desk-gpt/artifacts/escalate.md†L1-L28】【F:Projects/Custom GPTs/Service-desk-gpt/artifacts/ticket_note.md†L1-L8】【F:Projects/Custom GPTs/Service-desk-gpt/artifacts/user_update.md†L1-L4】
- **Impact:** This mismatch risks downstream parsers or compliance checks rejecting generated notes, since the instructions explicitly forbid Markdown formatting for Autotask artifacts.
- **Suggested fix:** Rename the artifact files to `.txt`, remove Markdown list markers, and replace decorative separators with simple sentences so the templates are "plain" out of the box.

### 2. Remove Markdown wrappers from machine-consumed YAML assets
- **Observation:** Both `runtime/policies.yaml` and `runtime/patterns.yaml` include prose headers and fenced code blocks, which makes the files invalid YAML as-is. 【F:Projects/Custom GPTs/Service-desk-gpt/runtime/policies.yaml†L1-L19】【F:Projects/Custom GPTs/Service-desk-gpt/runtime/patterns.yaml†L1-L57】
- **Impact:** Any automation that expects clean YAML (including validation tooling or runtime loaders) will fail or require extra stripping logic.
- **Suggested fix:** Strip the Markdown scaffolding, keep only valid YAML, and move human-facing notes to adjacent README comments or inline YAML comments.

### 3. Clarify the "QuickFix-6" operating loop numbering
- **Observation:** The numbered list under "Operating Loop" interleaves multiple steps on single lines (`1.` then `2)` then `5)` etc.), making the intended sequence ambiguous. 【F:Projects/Custom GPTs/Service-desk-gpt/instructions.md†L32-L36】
- **Impact:** Editors and agents may misinterpret the flow, leading to inconsistent runbooks.
- **Suggested fix:** Rewrite the section as a true ordered list (1–6) or table that spells out each stage on its own line with duration/goal.

### 4. Harden PowerShell guidance against partial implementations
- **Observation:** The PowerShell section mandates `Scope / Fast path / Rollback / Automation hook`, but the pattern entries only include scope, steps, and automation hook—no rollback guidance. 【F:Projects/Custom GPTs/Service-desk-gpt/instructions.md†L68-L73】【F:Projects/Custom GPTs/Service-desk-gpt/runtime/patterns.yaml†L6-L55】
- **Impact:** Without rollback hints, engineers risk implementing one-way changes or omitting required reversibility docs.
- **Suggested fix:** Add a `rollback:` field (even if it references manual steps) for each pattern, and mirror that expectation in any future PowerShell snippets.

### 5. Tighten checklist formatting to reinforce plain-text outputs
- **Observation:** The checklists mirror Markdown conventions (filename echo + fenced blocks) rather than presenting copy-ready bullet points. 【F:Projects/Custom GPTs/Service-desk-gpt/checklists/evidence.md†L1-L10】【F:Projects/Custom GPTs/Service-desk-gpt/checklists/isolation.md†L1-L10】
- **Impact:** Agents copying directly from the checklist risk pasting code fences into user-visible replies, undermining the "thin" reply objective.
- **Suggested fix:** Drop the fences and lead with concise imperative lines (`Repro steps:` etc.) so the checklist can be pasted without cleanup.

### 6. Expand test templates with decision aids
- **Observation:** The tests prompt provides a skeleton but no guidance on selecting appropriate diagnostics or mapping outcomes back to the state machine. 【F:Projects/Custom GPTs/Service-desk-gpt/prompts/tests.md†L1-L13】
- **Impact:** Less experienced agents may struggle to craft tests that meaningfully advance the triage.
- **Suggested fix:** Add a short "How to choose" paragraph (e.g., "Prefer isolation by layer; pick one identity test, one client test"), plus a reminder to record evidence for the ticket note.

### 7. Reinforce intake/triage hand-offs with state cues
- **Observation:** The example behaviors document and triage prompt are helpful, but neither calls out the state transitions or stop conditions embedded in `state_machine.json`. 【F:Projects/Custom GPTs/Service-desk-gpt/'How the GPT should behave (examples).md'†L1-L37】【F:Projects/Custom GPTs/Service-desk-gpt/runtime/state_machine.json†L1-L64】
- **Impact:** Human maintainers must read multiple files to understand when to escalate or re-enter intake, increasing onboarding time.
- **Suggested fix:** Add a table or quick-reference appendix summarizing each state, entry trigger, and exit condition so documentation mirrors the machine workflow.

## Next Steps
1. Decide which files must remain machine-readable and refactor them first (artifacts, YAML assets).
2. Update documentation (instructions, examples, checklists) to match the cleaned formats and clarify workflows.
3. After restructuring, validate with linting or runtime dry-runs to ensure the GPT still loads the assets without manual cleanup.
