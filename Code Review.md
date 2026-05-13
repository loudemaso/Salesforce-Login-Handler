# Instructions for Deep Code Review

**Main Instruction:** Review this code and make improvements based on the guidance below. STRICTLY keep current functionality in place. If there are opportunities to substantially simplify or improve code that require certain functionality tradeoffs, raise these tradeoffs to me for a decision before making changes that change the behavior of the app.

**Behavior lock:** If a change could alter *observable behavior* (API responses, UI states, persistence semantics, timing/ordering, permissions/visibility), call it out explicitly and do not implement without approval.

## Review Principles

- **Protect invariants first.** Prioritize issues that can break core correctness guarantees (data integrity, authorization/visibility rules, idempotency, ordering, consistency) or create irreversible outcomes.
- **Bound all loops and async workflows.** For polling/retries/background work, ensure there is always an exit condition (timeouts/max attempts), terminal states (success/failed/cancelled), and cancellation where appropriate.
- **Prefer recoverable failure over “perfect” handling.** When a rare edge case would require complex custom logic, favor a simple, observable failure path with a user/operator recovery mechanism (retry/reset/refresh) rather than “tying up every loose end.”
- **Make retries safe.** If the code retries anything, ensure it is safe to retry (idempotent operations, deduplication, idempotency keys, guards against double-writes).
- **Keep resource usage bounded.** Avoid unbounded API calls, exponential fan-out, memory growth, unbounded queues, or runaway logging. Add backoff + jitter and rate limiting when relevant.
- **Optimize for clarity over cleverness.** Use standard, boring patterns (state machines over boolean soup, explicit enums, small pure helpers) and remove band-aid layers when the foundational logic can be fixed cleanly.
- **Assume change has blast radius.** Before structural refactors, trace call sites and related flows; identify what behavior could change and what must be manually tested.
- **Instrument the unknowns.** Prefer adding lightweight observability (logs/metrics/error reporting with context) over speculative code paths. Fail “loudly” (not silently) for non-recoverable conditions.
- **Security is a first-class review axis.** Look for ways inputs can bypass permissions, cause injection, leak data, or trigger unintended side effects.
    - Prompts: *What’s the worst thing an untrusted caller could do?* *Are we relying on client-side enforcement anywhere?* *Any path to read/write data outside the viewer’s scope?*
- **Be explicit about tradeoffs.** If improving reliability/performance/readability conflicts with current behavior, surface the decision clearly before changing behavior.
- **Comments explain constraints, not narration.** Prefer self-documenting structure and names. Comments should capture *why*, invariants, and non-obvious constraints; remove comments that merely restate what the code does.
- **Strengthen tests when it matters.** For non-trivial fixes/refactors, add or adjust automated tests when feasible; use manual testing as the final safety net.

## Expected Review Output

When you complete a review, include:

- **Summary:** what changed and why (1–5 bullets)
- **Behavior impact:** explicitly state “no observable behavior change expected” *or* list the expected behavior changes and why
- **Risks & assumptions:** brief risk register (severity/likelihood) + assumptions the change relies on
- **Manual test checklist:** specific features/flows to manually validate
- **Rollback note (if relevant):** simplest way to revert if something goes wrong