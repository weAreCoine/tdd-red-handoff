# Benchmark protocol — two-role vs pipeline, single task (weather-card)

> Campaign material, not kit product. Measures **time per phase** and **tokens/cost per
> phase** for the same feature run under both profiles. One task, one run per profile —
> the goal is a cost/throughput comparison, not a quality benchmark.
>
> Model names are deliberately absent from this file (coupling #8 — `verify-kit`'s
> `model-roster` check scans every `.md` in the repo). Concrete names and prices live in
> `bench_report.py`, which the check does not scan. Whenever this protocol says "the
> role's model", resolve it in the **test repo's** `.ai/PROJECT_ARCHITECTURE.md § Model
> Roster`.

## Setup (already done — recorded for reproducibility)

| Worktree | Branch | Profile | Base |
|---|---|---|---|
| `~/Projects/AgentsWorkflowTests-bench-two` | `bench/two-role` | two-role (switch committed as `88b9164`) | `4b92f6c` |
| `~/Projects/AgentsWorkflowTests-bench-pipe` | `bench/pipeline` | pipeline (unchanged) | `4b92f6c` |

Sibling worktrees, **not** nested: Claude Code climbs parent directories for `CLAUDE.md`,
so a nested worktree would also inherit the main repo's pipeline shell.

Environment per worktree: `.env` copied, `composer install`, `npm ci`, `npm run build`
(Vite manifest is required by the Inertia root view in tests), sqlite migrated,
`wayfinder:generate` run. Baseline: **80/80 tests green in ~1.4s** in both.

## Measurement rules

1. **Each phase starts with a frozen driver prompt** pasted verbatim, beginning with a
   `[BENCH <ID>]` marker. The parser segments the transcripts on these markers; never
   improvise the marker or reword the prompt.
2. **Model per session**: before pasting the first prompt of a session, set the model to
   the session's role per the roster (`/model`, then verify). The Implementer runs in its
   own external CLI per `AGENTS.md`; its session is measured from that CLI's rollout log.
3. **Active time** (Claude transcripts): work runs from each prompt you type to the
   last *work event* of its turn — assistant output, tool results, file edits landing.
   The wait before your next prompt is idle. Work-closed gaps count whatever their
   length (long thinking stretches included); harness bookkeeping entries — attachments
   batched with a prompt, away summaries, hook logs, a new session's preamble — close
   nothing (they used to leak the whole inter-session wait into the previous phase).
   The external CLI's rollout can't reliably separate your approval waits from tool
   waits, so there a ≤120s-gap threshold applies instead (`--gap`); approval waits
   inflate its active time.
4. **Rework loops are part of the measurement**: a `REJECTED(n)` gate or review findings
   send the work back to the owning role exactly as the chapter prescribes. When
   re-entering a phase, reuse its marker verbatim (a second `[BENCH P2]` before the fix
   session, a second `[BENCH A4]`/`[BENCH P5]` for the re-review): the parser sums
   same-ID windows. **Model escalation is the exception**: record the verdict and stop —
   the run does not climb the ladder.
5. **No mid-run fixes**: if the environment breaks mid-phase, note it, fix it outside the
   session, and mark the phase as contaminated in the results.
6. Work in the worktree's own directory only — transcripts land in a per-worktree project
   dir under `~/.claude/projects/`, which is what keeps the two runs separable.

## Comparable phase buckets

| Bucket | two-role (marker) | pipeline (marker) |
|---|---|---|
| Design | Analyze (`A1`) | Phase 1 Design (`P1`) |
| Tests | Tests (`A2`) | Phase 2 Transcription (`P2`) |
| Plan/Gate | Plan (`A3`) | Phase 3 Gate + plan (`P3`) |
| Implementation | Implementer, external CLI | Phase 4, external CLI |
| Review | Review (`A4`) | Phase 5 Review (`P5`) |

## The frozen feature request (identical in both profiles)

Included verbatim inside `A1` and `P1` below. Deliberately isomorphic to
`exchange-rate-card` (both worktrees carry that precedent, so neither profile gets an
advantage): the differences measured are process overhead, not design luck.

## Driver prompts — two-role worktree

**Session 1 — design side (the Architect role's model).** Three prompts, one session:

```
[BENCH A1] You are the design side for the feature below. Run the Analyze phase now and
stop when it is complete — do not start the Tests phase until I say so.

Feature request — weather-card

The Dashboard gains a card showing the current temperature in Milan and the trend over
the last 7 days (daily mean temperature: absolute delta in °C and direction), sourced
from the Open-Meteo forecast API (no API key, no new dependency). The card is decorative
relative to the rest of the page: any upstream problem — timeout, HTTP error, malformed
payload, fewer than two data points — must degrade to an explicit "unavailable" state
while the Dashboard renders normally. Cache upstream reads so the API is not hit on
every page load: a successful read can be reused for 1 hour; a failure must not be
retried for 5 minutes.
```

```
[BENCH A2] Proceed with the Tests phase. Stop when it is complete.
```

```
[BENCH A3] Proceed with the Plan phase. Stop when the plan is issued.
```

**Implementation — external CLI** (per `AGENTS.md`), started after `A3`:

```
Implement the plan in .ai/plans/weather-card.md following AGENTS.md.
```

**Session 2 — review (the Architect role's model, fresh session):**

```
[BENCH A4] The Implementer has finished weather-card. Run the Review phase on the
implementation.
```

## Driver prompts — pipeline worktree

**Session 1 — Designer (the Designer role's model):**

```
[BENCH P1] You are the Designer. Run Phase 1 (Design) for the feature below and stop
when the testplan is READY.

Feature request — weather-card

The Dashboard gains a card showing the current temperature in Milan and the trend over
the last 7 days (daily mean temperature: absolute delta in °C and direction), sourced
from the Open-Meteo forecast API (no API key, no new dependency). The card is decorative
relative to the rest of the page: any upstream problem — timeout, HTTP error, malformed
payload, fewer than two data points — must degrade to an explicit "unavailable" state
while the Dashboard renders normally. Cache upstream reads so the API is not hit on
every page load: a successful read can be reused for 1 hour; a failure must not be
retried for 5 minutes.
```

**Session 2 — Test-Writer (the Test-Writer role's model, fresh session):**

```
[BENCH P2] You are the Test-Writer. Run Phase 2 (Test transcription) for weather-card.
Stop when the testplan is RED.
```

**Session 3 — Verifier (the Verifier role's model, fresh session):**

```
[BENCH P3] You are the Verifier. Run Phase 3 (Gate) for weather-card. Stop after the
gate verdict — and, if APPROVED, after issuing the plan.
```

**Implementation — external CLI** (per `AGENTS.md`), started only after `Gate: APPROVED`:

```
Implement the plan in .ai/plans/weather-card.md following AGENTS.md.
```

**Session 4 — Verifier (the Verifier role's model, fresh session):**

```
[BENCH P5] You are the Verifier. Run Phase 5 (Review) for weather-card.
```

## Producing the report

After each worktree's run completes:

```bash
python3 docs/design/bench/bench_report.py \
  --label two-role \
  --claude-dir ~/.claude/projects/-Users-luca-Projects-AgentsWorkflowTests-bench-two \
  --codex-cwd /Users/luca/Projects/AgentsWorkflowTests-bench-two

python3 docs/design/bench/bench_report.py \
  --label pipeline \
  --claude-dir ~/.claude/projects/-Users-luca-Projects-AgentsWorkflowTests-bench-pipe \
  --codex-cwd /Users/luca/Projects/AgentsWorkflowTests-bench-pipe
```

The report prints, per phase: active time, tokens (input / output / cache read / cache
write) split by model, and estimated cost in USD. **Compare on the cost column**, not on
raw tokens — the pipeline staffs roles on different price tiers by design, so token
counts are not comparable 1:1 across profiles. The implementation phase reports tokens
always; its cost only if you pass `--codex-price-in/--codex-price-out` (USD per 1M).

## Cross-check with ccusage

`bench_report.py` is the only instrument that knows the phase markers and the active-time
rule; `ccusage` (installed, run via `bunx`) is session-grained but keeps an independent
accounting with its own pricing table. Use it two ways after each run:

1. **Validate the parser's totals.** Per worktree, the sum of the phase rows must match
   the session totals reported by:

   ```bash
   bunx ccusage claude session --json | # filter on projectPath:
   # -Users-luca-Projects-AgentsWorkflowTests-bench-two  (or …-bench-pipe)
   ```

   Tokens must match exactly (both dedupe by message id); the cost column may differ
   slightly where the parser's hardcoded prices and ccusage's live pricing table diverge
   (e.g. introductory pricing) — investigate anything beyond that.

2. **Price the implementation phase.** Instead of hunting for the external CLI's price
   list, read the per-session cost straight from `bunx ccusage codex session` (its rows
   match the rollouts `bench_report.py` finds; pair them by timestamp/size) and use that
   figure for the IMPL row.
