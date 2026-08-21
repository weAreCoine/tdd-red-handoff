# Plan: {feature-name}

<!-- =============================================================
     HANDOFF PLAN — the SOLE interface between the design side
     (CLAUDE.md) and the implementer (AGENTS.md). Written by whoever
     the active profile's chapter assigns (the Verifier at the gate
     under pipeline; the Handoff Planner under autopilot; the
     Architect under two-role). The implementer
     does ONLY what this file says. Ambiguity here becomes a guess
     there, so be surgical.

     Under the gated profiles (pipeline, autopilot), signatures and
     intent come from the feature's testplan
     (.ai/plans/{feature-name}.testplan.md) — copy them verbatim,
     don't re-derive them.

     CONVENTIONS:
       <!-- FILL: ... -->   instruction to the agent filling this plan.
                            Obey, then DELETE. None may survive in the
                            finished plan.
       {placeholder}        replace with the concrete value.

     Before handing off, verify:
       grep -nE 'FILL:|\{[a-z-]+\}' .ai/plans/{feature-name}.md   # must be empty
     ============================================================= -->

> **Status:** {RED | DONE}
>
> `RED` tests written and failing — under a gated profile, gated per its chapter — ready for
> implementation · `DONE` implemented and review-passed (set by the review phase, with its
> date). Issue the plan as `RED`; only the review phase closes it.
>
> **Design side:** tests and this plan are done — under the gated profiles, from the gated
> testplan.
> **Implementer:** make the listed tests pass, nothing more.
>
> **Tier substitution:** {none | {role} ran below its roster tier — see `PROJECT_ARCHITECTURE.md § Model Roster`}
>
> `none` is the normal case. A **record, not a reference**: it stays as written after the
> substitution is lifted — what matters later is the tier this artifact was produced on.

## 1. Goal

<!-- FILL: one paragraph. WHAT this feature does and WHY, in domain terms. No implementation detail
     here — that's §4. The implementer reads this to understand intent, not to copy it. -->

{one-paragraph statement of the feature and its purpose}

## 2. Affected Layers & Units

<!-- FILL: enumerate every unit the change touches, tagged with its layer (Model / View /
     Controller-orchestration / Service / Client). This is the layering contract made concrete for
     this feature — it tells the implementer where each file lives and stops layer-guessing.
     If a layer is NOT touched, omit its row. If a NEW layer materializes (e.g. first Service),
     say so explicitly — that's an architectural event. -->

| Layer                      | Unit | New / Modified |
|----------------------------|------|----------------|
| Model                      | {path} | {new\|modified} |
| Controller (orchestration) | {path} | {new\|modified} |
| Service                    | {path or "— not touched"} | — |
| Client (transport)         | {path} | {new\|modified} |

## 3. Tests (the spec — already written and RED)

<!-- FILL: list each test file and the behaviors it pins. The implementer runs these and makes them
     green. State the focused-test command (from PROJECT_ARCHITECTURE § Toolchain) so they can run
     exactly this slice. Confirm RED was verified — if any test passed before implementation, it's
     wrong and must not ship in this plan.
     The "Source testplan" and "Gate" rows belong to the gated profiles (pipeline, autopilot).
     The Gate line certifies the approval that authorizes implementation: under pipeline the
     Verifier writes it at issue time (a pipeline plan without an APPROVED gate must not exist);
     under autopilot the Handoff Planner issues the plan WITHOUT the Gate line and only the
     Plan Reviewer stamps it. Under two-role, OMIT both rows — there is no testplan and no
     gate. -->

- **Source testplan:** `.ai/plans/{feature-name}.testplan.md`
- **Test files:**
  - `{path}.test.{ext}` — covers: {happy path, failure paths, boundaries, async/abort states it pins}
- **Run this slice:** `{focused test command with pattern}`
- **RED verified:** {yes — all listed tests fail as written}
- **Gate:** APPROVED — {date}, all gate checks passed (CLAUDE.md, gate phase)

## 4. Implementation Spec

<!-- FILL: the surgical part. For each unit in §2, give the implementer everything needed to write it
     WITHOUT inventing a pattern:
       - exact file path
       - full signature(s) with types (inputs, return, generics, error type)
       - which existing sibling file to mirror for structure/naming/imports (reference it by path)
       - the data/control flow in prose if non-obvious (e.g. stream → mapping → state transition)
     Be explicit about types — a vague signature is where the implementer guesses. -->

### `{path}`

```{lang}
{exact signature(s) the implementer must produce — types included}
```

- **Mirror:** `{sibling path}` for {structure / naming / import style}.
- **Flow:** {prose description of non-obvious control/data flow, if any}.

## 5. Constraints (DO / DO NOT)

<!-- FILL: the guardrails. AGENTS.md already forbids touching tests, adding deps, refactoring, and
     creating unlisted files — DON'T repeat those. List only the constraints SPECIFIC to this feature:
       - "use the adapter pattern from X, not a new one"
       - "DO NOT add a Service yet — orchestration calls the Client directly here"
       - "no new top-level dirs"
       - boundary/validation rules unique to this change
     Each constraint should prevent a specific plausible mistake. -->

- **DO:** {feature-specific positive constraint}.
- **DO NOT:** {feature-specific prohibition — the tempting-but-wrong move}.

## 6. Definition of Done

<!-- FILL: the exit checklist. Mostly fixed (mirrors the review phase in CLAUDE.md / AGENTS.md Steps 3–4) but
     restate it so the implementer has one place to check against. Adjust only if this feature has
     an extra gate. -->

- [ ] All tests in §3 green (full suite, not just the slice).
- [ ] `typecheck` clean (zero errors).
- [ ] `lint` + `format:check` clean.
- [ ] Layering respected (§2 placement; dependency direction not skipped/inverted).
- [ ] No code beyond what the tests require (YAGNI).
- [ ] No secrets in frontend; boundary validation at the edge.
