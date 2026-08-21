# Test Plan: {feature-name}

<!-- =============================================================
     TEST PLAN — the test-case inventory: the design side → transcription
     handoff, and the gate's reference. This is the SOLE spec interface
     between the design phase and the transcription and gate phases
     (CLAUDE.md — the active chapter names who writes it, who grants
     READY, and who gates it; the pipeline and autopilot profiles produce
     it). Under a profile that does not produce it (two-role) it goes
     inert — never rewritten or deleted.

     The transcription phase TRANSCRIBES this inventory into test code.
     Every decision not written here becomes a spec decision made by the
     wrong model — be exact. "Handles the error" is not a spec; "throws
     RateLimitError with retryAfter: 30" is.

     CONVENTIONS:
       <!-- FILL: ... -->   instruction to the role filling this plan.
                            Obey, then DELETE. None may survive once READY.
       {placeholder}        replace with the concrete value.

     Before setting Status: READY, verify:
       grep -nE 'FILL:|\{[a-z-]+\}' .ai/plans/{feature-name}.testplan.md   # must be empty
     ============================================================= -->

> **Status:** {DRAFT | READY | RED | APPROVED | REJECTED(n)}
>
> `DRAFT` design side still working · `READY` ready for transcription — self-declared by the
> Designer under pipeline, granted by the inventory gate under autopilot · `RED` tests written
> and failing, hand to the test gate · `APPROVED` gate passed, implementation plan authorized ·
> `REJECTED(n)` back to transcription with notes (n = rejection count; the cap's consequence is
> the active chapter's rule — pipeline escalates the gate to the Designer's model, autopilot
> stops the flight).

## 1. Goal

<!-- FILL: one paragraph. WHAT this feature does and WHY, in domain terms. The same intent
     statement will open the implementation plan (§1 there). No implementation detail. -->

{one-paragraph statement of the feature and its purpose}

## 2. Units & Signatures (design decisions — frozen)

<!-- FILL: every unit the tests will touch, tagged with its layer (Model / View /
     Controller-orchestration / Service / Client), with EXACT signatures — inputs, return
     type, generics, error types. The tests call these, so they are design decisions: the
     transcription and gate phases must not alter them. Whoever writes the implementation
     plan copies them verbatim (§4 there). -->

| Layer | Unit (path) | Signature(s) — exact, with types | New / Modified |
|---|---|---|---|
| {layer} | `{path}` | `{signature}` | {new\|modified} |

### 2.1 Behavioral decisions (frozen)

<!-- FILL: the design decisions that are neither signatures nor inventory rows — rounding and
     formatting policies, cache keys/TTLs, failure/degradation semantics, endpoint or protocol
     choices, explicit non-goals (YAGNI exclusions). One bullet each, with the WHY when it is
     not obvious. The inventory below ENCODES these decisions; the Verifier derives the
     implementation plan's constraints from here. Delete the section only if the feature
     genuinely has no such decisions (rare). -->

- {decision}

## 3. Test-Case Inventory (the spec)

<!-- FILL: one row per test, grouped by test file. This is the core artifact:
       - Test name: used VERBATIM by the transcription phase.
       - Arrange: concrete initial state, inputs, fixture values.
       - Act: the exact call being exercised.
       - Assert: the exact expected values — never "succeeds" or "throws"; state WHICH
         value, WHICH error type, WHICH fields.
       - Kind ∈ happy | failure | boundary | async | auth | state | side-effect.
     For table-driven variants: one row describing the table, then a sub-list of the
     variant tuples (input → expected). Apply CLAUDE.md § Test Philosophy when choosing
     rows — happy path + every failure path, boundaries, async states. -->

### `{path}.test.{ext}`

| # | Test name | Arrange | Act | Assert (exact) | Kind |
|---|---|---|---|---|---|
| 1 | {name} | {state/fixtures} | {call} | {exact expected values} | {kind} |

## 4. Mocks & Fixtures (allowed list)

<!-- FILL: exactly which boundaries may be mocked (e.g. "the HTTP transport inside the
     Client — mock fetch, nothing above it") and which fixtures/factories to use or create.
     Anything not listed here must NOT be mocked — the Verifier's gate checks this. A test
     that exercises mostly its own mocks tests nothing. -->

- **May mock:** {boundary + how}
- **Must not mock:** {everything else — name the tempting-but-wrong candidates}
- **Fixtures:** {existing factories to reuse, or new fixture files to create (list paths)}

## 5. Constraints for the transcription phase (DO / DO NOT)

<!-- FILL: add feature-specific constraints below the fixed ones. Delete none of the fixed
     ones — they are the role contract in checklist form. -->

- **DO:** mirror `{sibling test file}` for structure, naming, and imports.
- **DO:** run the focused slice with `{focused test command}` (from PROJECT_ARCHITECTURE § Toolchain).
- **DO NOT:** add, drop, merge, or reinterpret inventory rows — flag gaps in the Log instead.
- **DO NOT:** weaken an assert to make a test fail (or pass).
- **DO NOT:** touch application code, add dependencies, or create files beyond the test
  files and fixtures listed here.

## 6. Log (append-only)

<!-- Each phase APPENDS here; never rewrite earlier entries, and keep this the file's LAST
     section — the autopilot profile reads the Log from this heading to the end of the file,
     and refuses a testplan that has any section after it. Paste command output inside a
     fenced block: raw output carries ruler lines that Markdown reads as a heading. Under autopilot
     the reader is bounded and refuses what it does not model — a line starting with '<' (raw HTML;
     these comments are fine), a fence or comment left open, a second Log heading
     (§ Repairing a refused Log, in that chapter, is the repair for all of these). The
     Implementer's GREEN row here is narrative: under autopilot the proof of implementation is
     the driver's acceptance stamp in git, never a Log line.
     This is the feature's audit
     trail: the RED output the gate reads, the rejection notes the transcription answers.
     Role labels come from the ACTIVE chapter (pipeline: Designer / Test-Writer / Verifier;
     autopilot: its nine-phase role names — there, every phase logs here, verdicts included). -->

- {date} · **{role}** — Status: READY.
- {date} · **{role}** — Status: RED. {n} tests written, all failing. Flags:
  {none | ambiguities or suspected missing cases, one per line}. Output:

  ```
  {the focused run's output, verbatim — fenced, so its ruler lines stay text}
  ```

- {date} · **{role}** — Status: {APPROVED | REJECTED(n)}. {point-by-point notes if rejected}.

<!-- FILL: if a phase ran under a tier substitution (`PROJECT_ARCHITECTURE.md § Model Roster`),
     append it to that phase's own entry — "ran below roster tier" — plus, when the gate and the
     design phase ended up on the same model, one line saying so: that is the case where the
     verdict rests on less independence than usual, and the Log is where a post-mortem finds it. -->
