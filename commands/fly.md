---
description: Open phase 1 of an autopilot flight — the design interview; as its last act it launches the driver in the background and goes dormant until the report or a stop.
---

# /fly `<feature>`

Fly one feature unattended under the **autopilot** profile: this command runs **phase 1** — the
design interview, the only phase where a human answers questions — then launches the driver
(`${CLAUDE_PLUGIN_ROOT}/bin/autopilot-driver.sh`) in the background and stays open, dormant,
until the flight ends. One flight = one feature = one draft PR. The full contract is the
chapter: `.ai/process/autopilot.md`.

> **Model check first.** Phase 1 runs on the **Designer's row** of
> `.ai/PROJECT_ARCHITECTURE.md § Model Roster`. Mismatch with no substitution recorded → say so
> and stop. Mismatch with a recorded substitution → proceed, declare it, and record it in the
> design record. Never assume a substitution and never edit a roster cell to make the check
> pass.

## Phase A — Preconditions (all fail fast, nothing written yet)

1. **Argument**: a feature name in kebab-case. Missing → STOP and ask.
2. **Profile**: `.ai/kit.json` says `"profile": "autopilot"`. Anything else → STOP and point to
   `/switch-profile autopilot` (never switch on your own — switching is its command's job).
3. **Fresh name** (extended inertness): `.ai/plans/` carries no `{feature}.adr.md`,
   `{feature}.testplan.md`, or `{feature}.md` from an earlier era. A hit → STOP: the flight
   never adopts or overwrites artifacts; ask for another name.
4. **Roster complete**: the roster has rows the autopilot production roles resolve to
   (TestPlan Designer / Handoff Planner — flagship production tier; Test Writer —
   cost-efficient; Implementer — mid) besides Designer and Verifier. A missing row → STOP and
   point to `/update-models-roster`.
5. **Git**: the base branch exists (`develop` where the convention applies) — missing → STOP,
   its creation is a human act. Working tree clean.
6. **Tooling**: the two headless harness CLIs and `gh` are on PATH. Missing → STOP and say
   which.
7. **Gitignore**: `.gitignore` covers `.ai/autopilot/` — add the line if missing (flight state
   is operational, never committed).

## Phase B — The machine binding (`models.env`)

The roster records display names; the driver needs CLI model identifiers. Read
`.ai/autopilot/models.env` if it exists and show it; otherwise (or if the roster changed since)
collect from the operator — **never from your own memory** — the identifiers for the four
slots and any recorded substitution ladder, then write:

```sh
# .ai/autopilot/models.env — machine binding of the Model Roster (operational, gitignored)
AP_MODEL_REVIEW='<review-tier CLI id>'
AP_MODEL_FLAGSHIP='<flagship-production CLI id>'
AP_MODEL_COSTEFF='<cost-efficient-production CLI id>'
AP_MODEL_MID='<mid-production CLI id>'
AP_LADDER_FLAGSHIP='<space-separated fallback ids, per the roster ladder>'   # optional
```

Each binding must agree with the roster row it implements — the roster stays the human record.

## Phase C — The interview (phase 1 of the chapter)

Work the Designer's phase-1 contract with the operator: understand the requirement fully,
inspect the code, fix affected units and exact signatures, map edge cases and blast radius,
resolve **every** open decision here — later phases inherit only what the artifacts say, and
nobody attends them. Then, in order:

1. Update the base branch and cut `feature/{feature}` from it.
2. Tracker: move (or create, with the operator) the feature's issue to *in progress*; keep its
   reference.
3. Write the design record `.ai/plans/{feature}.adr.md` — goal, scope and non-goals, affected
   layers and signatures, edge-case map, tracker reference, model bindings (substitutions and
   ladder included, if any).
4. Write the flight config and commit:
   ```sh
   mkdir -p .ai/autopilot/{feature}
   printf "AP_BASE_BRANCH='%s'\nAP_ISSUE_REF='%s'\n" "<base>" "<issue-ref>" > .ai/autopilot/{feature}/flight.env
   git add .ai/plans/{feature}.adr.md && git commit -m "feat: {feature} — design record (<issue-ref>)"
   ```

## Phase D — Launch and go dormant

Run the driver **in the background** (it must keep flying while this session sits idle):

```sh
"${CLAUDE_PLUGIN_ROOT}/bin/autopilot-driver.sh" -f {feature} .
```

Tell the operator the flight is airborne and what the two endings look like. Then stay dormant —
no further edits, no second-guessing the phases — until the driver exits:

- **DONE** → relay `.ai/autopilot/{feature}/report.md`: the draft PR link, the bounce counters,
  any proposed issues from the Final Reviewer's notes. Promotion from draft, merge, and issue
  closure are the operator's.
- **STOPPED** → present the exact blocking point and the last verdict from the report; the
  operator amends and relaunches (`autopilot-driver.sh -f {feature} -s <phase>`) or aborts.
  A stopped flight pushed nothing.
