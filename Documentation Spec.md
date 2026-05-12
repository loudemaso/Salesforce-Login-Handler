# AI Coding Design Spec

Topic: Artificial Intelligence (AI), Building
Created by AI: No

## Goal

Create design spec files that act as a true proxy for the code: during design/initial implementation they are the medium for refining and fully outlining the system before handing it to a coding agent, and during iteration they stay aligned with the code so there is always a human-readable, non-technical inspectable representation of the system.

## Design Spec Files

Only two spec file types exist; do not create other spec artifacts.

- **Feature Spec (per feature):** Runtime Pattern + UI Contract + System Components Involved.
- **System Components (global):** shared component index + stable contracts.

## Editing Rules

The following rules apply to all spec docs.

- Do not rename/reorder required section headers.
- Prefer bullets; be precise; detailed walkthroughs are allowed.
- Update spec first. **Do not change code** unless a human explicitly gives clear go-ahead to implement or modify code.
- Do not add “options”, discarded approaches, or speculative alternatives. Specs must be internally consistent and authoritative.

## System Consistency Rules

These rules exist to prevent spec drift and cross-feature inconsistencies.

- When proposing or making spec changes, consider the **whole system** (not just the local feature).
- Review aggressively for consistency before recommending a design: walk through **all relevant spec docs** and **all code paths in the repo** that could be involved with the proposed changes. Err on the side of excess caution.
- If you detect a conflict or inconsistency across specs, **pause and raise the concern to the human in AI chat**. Do not write conflict notes or alternative paths into any spec file.

System design priorities:

1. **Reliability** (durable state, clear invariants, safe failure handling)
2. **Simplicity** (streamlined architecture; fewer moving parts; avoid special-case patches)

## Feature Spec File Contract

These are multiple files: one Feature Spec per feature. Feature Specs contain feature-specific behavior only.

Rule of thumb: if two Feature Specs share meaningful runtime behavior, your feature boundaries are wrong.

- Merge the features, or create a new Feature Spec with a **descriptive functional name** that owns the shared Runtime Pattern as the single source of truth.
- Other Feature Specs must reference the shared feature; do not duplicate the shared behavior.

Each feature spec file must contain these sections as written.

### 1. Runtime Pattern

- One logical, chronological walkthrough whenever possible.
- Branch only for true concurrency; label branches and their join/sync points (shared state, stop signals).
- Include (inline; no extra subheaders): entrypoints, end-to-end behavior (including background workflows, integrations, persistence/data access effects, validation/policy enforcement, observability), invariants/guards, failure handling.

### 2. UI Contract

- Include: states/modes, primary surfaces, enabled/disabled rules, indicators/messages/counters, key copy, edge cases (including shared UI modules/state management and client-side service contracts when present).
- Do not include: runtime pattern logic, system component interface details, or implementation alternatives.

### 3. System Components Involved

- List the **System Components** this feature relies on (names must match the global doc).
- Definition: “System Components” are durable, reused building blocks (services/pipelines/modules/utilities/shared data models), not one-off feature glue code.
- Per-component note: **purpose only, 1–3 sentences max** (why this component is involved). No runtime/UI behavior.
- Do not include: runtime sequences, business rules, UI requirements, or interface details (those belong in Runtime Pattern, UI Contract, or the System Components file).

## System Components File Contract

This is a single global reference file for the entire system. It lists durable, reused System Components and their stable public surfaces so Feature Specs can reference them without duplicating runtime/UI behavior.

Per component, keep prose **purpose-focused (1–3 sentences max)**. Include only:

- Responsibility (purpose)
- Public interface (entrypoints)
- Dependencies
- If the System Component is a **data model / schema** (e.g., custom object / table), document its **fields** clearly: field name, field type, and allowed values/enums (e.g., picklist options).
- If the System Component is a **code module** (e.g., an Apex class / service / utility), document its **public surface area** clearly: the public methods/endpoints/events other modules call, their inputs/outputs, and any required usage constraints (keep prose 1–3 sentences; list signatures as bullets).

Do not include feature-specific behavior here (no step-by-step runtime sequences, UI behavior, or “how it works end-to-end”). If you find yourself writing “first…, then…, user…”, move that content to the relevant Feature Spec’s Runtime Pattern or UI Contract.