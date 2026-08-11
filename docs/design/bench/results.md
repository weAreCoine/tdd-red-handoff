# Benchmark results — two-role vs pipeline, weather-card (2026-08-11)

> One run per profile, single frozen task, measured per `protocol.md`. This is a
> cost/throughput observation, **not** statistical evidence (n=1 per profile, and the
> run happened to hit the no-rework path in both profiles). Model names are absent by
> design (coupling #8): roles resolve in the test repo's roster; the raw per-model
> figures live in the parser's output, reproducible with the commands in
> `protocol.md § Producing the report`.

## Run integrity

- All markers clean: one per phase, each phase in its own session as prescribed;
  no rework loops, no `REJECTED`, no escalation. The pipeline gate returned
  `APPROVED` on first pass and the plan was issued; the review set the plan `DONE`
  in both profiles. Both worktrees green.
- Excluded from measurement: one aborted false start before the pipeline Tests
  session (prompt sent with a leading @-mention, interrupted; ~$0.10, transcript
  quarantined) and an empty resurrected transcript (a single system entry, no usage).
- Both implementation runs produced a small secondary session on the external CLI's
  fallback tier (~$0.3–0.4 each); counted in the Impl bucket.

## two-role — phases

| Bucket | Marker | Role | Active | input | output | cache_r | cache_w | Cost USD |
|---|---|---|---|---:|---:|---:|---:|---:|
| Design | A1 | Architect | 4m05s | 89 | 16.5k | 830.9k | 100.0k | 3.66 |
| Tests | A2 | Architect | 6m25s | 19 | 31.3k | 1310.6k | 44.4k | 3.76 |
| Plan | A3 | Architect | 2m33s | 7 | 13.7k | 645.8k | 25.4k | 1.84 |
| Impl | — | Implementer (external CLI) | 8m50s | 3535.6k¹ | 15.0k | — | — | 3.11² |
| Review | A4 | Architect | 3m14s | 20 | 13.0k | 909.1k | 106.6k | 3.69 |
| **Total** | | | **25m07s** | | | | | **16.06** |

## pipeline — phases

| Bucket | Marker | Role | Active | input | output | cache_r | cache_w | Cost USD |
|---|---|---|---|---:|---:|---:|---:|---:|
| Design | P1 | Designer | 9m36s | 16 | 46.5k | 830.7k | 145.8k | 6.07 |
| Tests | P2 | Test-Writer | 7m39s | 70 | 35.6k | 4313.9k | 128.8k | 1.73 |
| | | └ advisor iterations (stronger tier)³ | | 150.8k | 8.7k | 0 | 0 | 0.97 |
| Gate + Plan | P3 | Verifier | 10m23s | 291.4k | 47.3k | 2144.4k | 157.6k | 5.28 |
| Impl | — | Implementer (external CLI) | 8m23s | 3381.4k¹ | 17.1k | — | — | 3.05² |
| Review | P5 | Verifier | 6m19s | 131.1k | 26.5k | 1990.7k | 113.8k | 3.45 |
| **Total** | | | **42m20s** | | | | | **20.55** |

¹ The external CLI's `input` includes its cached reads (no separate column in its log).
² Impl priced from the CLI's own accounting (`ccusage codex session`), per
  `protocol.md § Cross-check`, main + fallback session summed.
³ Harness-billed advisor calls on a stronger tier inside the Test-Writer's session —
  visible only in the per-iteration usage (see Method notes).

## Comparison by bucket — cost column

| Bucket | two-role | pipeline | Δ cost | two-role time | pipeline time |
|---|---:|---:|---:|---:|---:|
| Design | 3.66 | 6.07 | +66% | 4m05s | 9m36s |
| Tests | 3.76 | 2.70 | −28% | 6m25s | 7m39s |
| Plan/Gate | 1.84 | 5.28 | +187% | 2m33s | 10m23s |
| Impl | 3.11 | 3.05 | −2% | 8m50s | 8m23s |
| Review | 3.69 | 3.45 | −7% | 3m14s | 6m19s |
| **Total** | **16.06** | **20.55** | **+28%** | **25m07s** | **42m20s** |

Design-side active time (Impl excluded): 16m17s vs 33m57s (+108%).

## Readings

1. **On the no-rework path, the pipeline costs +28% and doubles design-side time.**
   The gate approved first pass, so the run paid the pipeline's coordination
   overhead (fresh sessions, cold caches, artifact re-reads) without exercising what
   the gate is for — catching a bad testplan before implementation. This is the
   pipeline's overhead floor, not its average value.
2. **Plan/Gate is where the overhead concentrates** (+187%): a fresh strong-tier
   session re-reads testplan + tests + repo to gate them (10m23s, $5.28), where the
   two-role Architect issues the plan from a warm session (2m33s, $1.84). Same-session
   cache reuse is the two-role profile's structural advantage.
3. **The Tests saving is real but smaller than it looks** (−28%): a third of the
   pipeline's Tests bucket is harness-billed advisor iterations on a stronger tier
   ($0.97 of $2.70). At the Test-Writer tier's sticker price (intro pricing ends
   2026-08-31) the bucket rises to ≈$3.57 and the saving nearly vanishes.
4. **Design costs more under pipeline** (+66%): the Designer writes the full testplan
   artifact (the 40k testplan file is the interface to two other roles), where the
   Architect's Analyze output stays lean because its tests follow in the same session.
5. **Impl is the isomorphy check**: same task, same CLI, near-identical figures
   (−2% cost, −5% time). The frozen feature request measured process overhead, not
   design luck — as intended.

## Implementation comparison (tests + application code)

Both suites green: two-role **115/115** (386 assertions), pipeline **108/108** (365) —
baseline was 80/80. Both plans `DONE`, toolchain gates green in both worktrees.

**Convergence first.** Same layering (Client → Service → orchestration), same class and
file layout (client 95 vs 90 LOC, service 117 vs 121), same exception style, same cache
flow (success TTL + failure marker + single warning log), same direction `match()`,
same negative-zero formatting idiom, and Svelte card markup **identical to the CSS
class**. The shared precedent (`exchange-rate-card`) plus `PROJECT_ARCHITECTURE.md`
steered both profiles to the same design; the isomorphic task measured process, and the
processes converged.

**Divergences — process signatures, not defects:**

1. **Test initiative.** The Architect wrote 25 weather cases (9 client / 12 service /
   4 page), two beyond the minimum — including a cross-card independence test (rate-API
   outage must not take down the weather card) absent from the pipeline run. The
   Test-Writer transcribed the testplan's inventory **exactly**: 23 rows → 23 tests,
   nothing added. Under pipeline, coverage is decided entirely at Design time.
2. **The inventory's rigor caught an edge the Architect missed**: the pipeline service
   normalizes the *current* temperature's negative zero (freezing case, `−0.04` →
   `"0.0"`); the two-role service guards only the delta and would render `"-0.0"`.
   Minor, real, and exactly the kind of case a forced exhaustive inventory surfaces.
3. **Same sentence, two contracts.** On `null` daily means the two-role client is
   tolerant (skips them as days without data; the service windows the trend on what
   remains — three dedicated tests), the pipeline client is fail-fast (any `null` →
   exception → unavailable). Both are defensible readings of the frozen request's
   "malformed payload → unavailable"; neither run flagged the ambiguity for a human.
   Inverted strictness elsewhere: the two-role client type-checks means strictly
   (`is_int`/`is_float`, rejects numeric strings) where the pipeline accepts
   `is_numeric` strings. The wall guarantees the tests bind the implementation — not
   that two runs pick the same contract.
4. Cosmetics: return-key naming (`dailyMeans` vs `daily`), cache-key naming, constant
   naming. No functional weight.

**Net quality verdict:** indistinguishable on this task. One small edge each way
(independence test vs freezing edge), both suites green, no functional bug found in
either during this review beyond the `-0.0` rendering note above.

## Method notes

- Two parser defects were found and fixed **during** collection, before either run's
  figures were read for comparison; both fixes apply to both runs identically:
  (a) harness bookkeeping entries (attachments, away summaries, hook logs, session
  preambles) no longer close active-time gaps as work — this had inflated marker-file
  phases by up to 8m30s; (b) usage is now counted per iteration inside each message,
  which surfaces advisor calls billed to the session on another tier — invisible in
  the message-level usage fields.
- Cross-check vs `ccusage` (protocol § Cross-check): input, output and cache-read
  match **to the token** on every session in both runs; cache-write reads ~1–2%
  higher in the parser (per-iteration sums vs the message-level field), ≤$0.06 per
  session. Cost deltas beyond that: none.
- The Tests row is priced at the cost-efficient tier's introductory rate (through
  2026-08-31); recompute per Open question in `STATE`/roster notes after that date.
