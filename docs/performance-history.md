# Performance history

Measured `perft` throughput across Monsoon's git history, commit by commit.

**Headline:** from the first benchmarkable commit (`657a4b5`, May 2026) to HEAD (`a82c23d`), startpos perft throughput rose **9.8×** (0.80M → 7.89M nodes/s at depth 4) while allocation fell **48×** (1288 → 27 bytes/node). Six bookmarked changes account for essentially all of it; the largest single one — `3e05e40`, make/unmake in place — contributed +70% speed and a 91% allocation cut on its own.

## Method

- **Environment:** SBCL via Roswell/quicklisp, one machine, sequential runs.
- **Per commit:** clean checkout → fresh Lisp image → system compiled from source with the FASL cache cleared → correctness gate (startpos perft 1–4 = `20/400/8902/197281`; Kiwipete depth 1 = `48`) → warm-up run → **5 timed `perft 4` runs** (197,281 nodes), full GC before each → report the **minimum** time. Allocation is bytes consed per run (deterministic; reported as bytes/node). GC time comes from `sb-ext:*gc-run-time*`.
- **Why depth 4:** it is the deepest depth that stays fast in the copy-based era (early commits), while still exercising the full move-generation pipeline. Throughput at different depths is not comparable, so the sweep uses one depth throughout.
- **Confirmations:** each significant mover was re-measured as a **paired parent/child A/B** (commit and its parent, back-to-back, depth 5 where affordable) to cancel machine drift. Those paired numbers are the authoritative ones quoted in the bookmarks.
- Deltas within **±5%** are machine noise. The sweep measures committed snapshots only; the working tree was clean before and after.

## Timeline

Throughput is min-of-5 nodes/sec at depth 4; `vs prev` compares to the previous *benchmarkable* commit.

### Baseline and early type hints

| Commit | Date | Change | Class | nodes/s | vs prev | B/node |
|---|---|---|---|---|---|---|
| `657a4b5`† | 2026-05-09 | Add perft tests and legality check (baseline) | baseline | 801,952 | — | 1288 |
| `a65dcb3`† | 2026-05-09 | Add some inline and type hints | declarations | 1,078,038 | +34.4% | 1276 |
| `3fc1974` | 2026-05-09 | Add even MORE type hints | declarations | 1,483,316 | +37.6% | 844 |
| `1f1d121` | 2026-05-09 | Remove `move-has-flag?` | refactor | 1,603,910 | +8.2% | 844 |
| `2aa7404` | 2026-05-10 | Add package export list | API | 1,630,422 | +1.6% | 844 |
| `97c56a1` | 2026-05-10 | Add more inline hints | declarations | 1,578,248 | −3.2% | 844 |
| `b4c70fd` | 2026-05-10 | Add missing comma in `with-moves` | fix | 1,644,008 | +4.2% | 844 |
| `5a692d0` | 2026-05-10 | Fix `occupied-squares` misspelling and tweak docs | docs/fix | 1,644,008 | 0% | 844 |

### UCI interlude (broken as committed)

| Commits | Date | Change | Status |
|---|---|---|---|
| `bb976e3` … `baa2298` (10 commits) | 2026-05-13 | UCI protocol support and refinements | **build-broken**: `it:return` does not exist in `iterate`; fixed in `68c0bc8` |

### Interim era

| Commit | Date | Change | Class | nodes/s | vs prev | B/node |
|---|---|---|---|---|---|---|
| `68c0bc8` | 2026-05-13 | Fix non-external name error in `uci.lisp` | fix | 1,643,995 | 0% | 844 |
| `c038685` | 2026-05-13 | Add a function to generate legal-moves | feature | 1,644,008 | 0% | 844 |
| `de9295e` | 2026-05-14 | Add docstrings and brief comments | docs | 1,630,408 | −0.8% | 844 |
| `3fdccf4` | 2026-05-14 | Fix indentation in comment updates | docs | 1,603,910 | −1.6% | 844 |
| `9c0a62e` | 2026-06-02 | Remove `by-piece` bitboards in `Position` | representation | 1,745,850 | +8.8% | 677 |
| `2ffaf6b` | 2026-06-03 | Change `move` and some other types to be plain integers | experiment | — | — | — (runtime-broken) |
| `7ed02cb` | 2026-08-18 | Revert "Change `move` … to plain integers" | revert | 1,761,438 | +0.9% | 677 |
| `b9d37a8` | 2026-08-18 | Revert `uci-parse-go` table refactor | revert | 1,793,464 | +1.8% | 677 |
| `ad7c3c7` | 2026-08-18 | Clean up stale declaim and `piece-at` indentation | cleanup | 1,715,487 | −4.3% | 677 |
| `5da8cf4` | 2026-08-18 | Use `:iterate` and import serapeum/alexandria symbols | deps | 1,730,535 | +0.9% | 677 |
| `26b12ed` | 2026-08-18 | Rename helpers for clarity and simplify board mutation | refactor | 1,826,676 | +5.6% | 677 |
| `150c380` | 2026-08-18 | Add docstrings to undocumented `moves.lisp` forms | docs | 1,843,748 | +0.9% | 677 |
| `062f05d` | 2026-08-18 | Fix FEN en-passant parsing by making `sq` an inline function | fix | 1,809,918 | −1.8% | 677 |
| `e1176b5` | 2026-08-18 | Replace qlot with Roswell + quicklisp | build | 1,745,850 | −3.5% | 677 |

### Optimization campaign

| Commit | Date | Change | Class | nodes/s | vs prev | B/node |
|---|---|---|---|---|---|---|
| `633938c` | 2026-08-18 | Eliminate double do-move in legal move generation and perft | algorithmic | 2,376,880 | +36.1% | 409 |
| `1b94a4c` | 2026-08-18 | Build move lists destructively with nconc/nconcing | allocation | 2,435,598 | +2.5% | 375 |
| `9e93bbf` | 2026-08-18 | Constant-fold castling destination squares | declarations | 2,466,012 | +1.2% | 375 |
| `040c9f7` | 2026-08-18 | Compile hot source files at speed 3 | policy | 2,497,228 | +1.3% | 375 |
| `dafeb42` | 2026-08-18 | Add attack, pin, and between-square building blocks | building blocks | 2,466,012 | −1.2% | 375 |
| `df99710` | 2026-08-18 | Classify move legality without per-move king-in-check | algorithmic | 2,989,106 | +21.2% | 349 |
| `ac6bae0` | 2026-08-18 | Declare `lsb`/`msb` return type as `(integer -1 63)` | declarations | 2,944,536 | −1.5% | 349 |
| `98fe0ac` | 2026-08-18 | Declare perft depth and return type; typed accumulation | declarations | 3,082,516 | +4.7% | 349 |
| `afd67cc` | 2026-08-18 | Replace pawn push-fn funcall with inlined shift-board macro | inline | 3,082,516 | 0% | 349 |
| `a199a3b` | 2026-08-18 | Keep `attacked-by` bitboards typed as `(unsigned-byte 64)` | declarations | 3,035,092 | −1.6% | 348 |
| `7ac6ff2` | 2026-08-18 | Type `pinned-pieces` blockers as square | declarations | 3,181,952 | +4.8% | 345 |
| `444ed1c` | 2026-08-18 | Declare castling-king-path argument types | declarations | 3,182,003 | 0% | 345 |
| `42612fe` | 2026-08-18 | Pack move into a 20-bit fixnum | representation | 3,181,952 | 0% | 295 |
| `3e05e40` | 2026-08-18 | Make and unmake moves in place (`do-move!`/`undo-move!`) | algorithmic | 8,220,042 | +158.3% | 27 |

### Modern commits

| Commit | Date | Change | Class | nodes/s | vs prev | B/node |
|---|---|---|---|---|---|---|
| `583a09a` | 2026-08-18 | Fix docstrings misplaced after declare | docs | 7,891,240 | −4.0% | 27 |
| `068da75` | 2026-08-18 | Drop unused serapeum `nest` import | deps | 8,220,042 | +4.2% | 27 |
| `a4753c9` | 2026-08-18 | Add colored-piece-code decomposition accessors | API | 8,220,042 | 0% | 27 |
| `c150490` | 2026-08-18 | Consolidate castling squares into one named set | refactor | 7,891,240 | −4.0% | 27 |
| `e62154d` | 2026-08-18 | Add `attacked-by-kingless` helper | feature | 7,587,730 | −3.8% | 27 |
| `a557aab` | 2026-11-21 | Refactor `fen.lisp` names and `iterate` usage | refactor | 7,587,730 | 0% | 27 |
| `c390c91` | 2026-11-21 | Create a `do-bitboard` macro to iterate over bitboards | refactor | 7,306,704 | −3.7% | 27 |
| `f5d7d71` | 2026-11-21 | Remove dependency on alexandria | deps | — | — | — (build-broken) |
| `a82c23d` | 2026-11-21 | Remove dependency on `iterate` | deps | 7,891,240 | +8.0% | 27 |

## Bookmarked changes

1. **`a65dcb3` — Add some inline and type hints.** +38.5% (paired, depth 4; 0.80M → 1.10M n/s). The hot path was still doing generic arithmetic on bitboards; inline and type declarations let SBCL keep bitboards unboxed. This matches the declaration audit, where removing such declarations reintroduces `GENERIC-*` calls and bignum boxing (e.g. `emit-moves` grows from 70 to 114 instructions without them).
2. **`3fc1974` — Add even MORE type hints.** +38.0% (paired; 1.04M → 1.44M n/s; allocation 1276 → 844 B/node, −34%). Type information propagated into the inline expansions of move packing, attack masks, and bit helpers, eliminating checks and generic operations throughout move generation.
3. **`633938c` — Eliminate double do-move in legal move generation and perft.** +42.8% (paired, depth 5; 2.23M → 3.19M n/s; 672 → 405 B/node, −40%). Perft previously applied each candidate move twice — once to test legality, once to recurse. Removing the duplicate nearly halves position copying per node.
4. **`9c0a62e` — Remove `by-piece` bitboards in `Position`.** Small speed effect (1.05× paired) but a clear allocation win: 839 → 672 B/node (−20%). The position object is smaller and fewer redundant arrays are maintained on every mutation.
5. **`df99710` — Classify move legality without per-move king-in-check.** +29.8% (paired, depth 5; 3.42M → 4.44M n/s; 372 → 347 B/node). Legality is decided from precomputed attack maps (checkers, pins, evasion mask) instead of making the move and testing the king, removing the remaining make/unmake cost from the filter.
6. **`3e05e40` — Make and unmake moves in place.** +70.5% (paired, depth 5; 4.95M → 8.45M n/s; 293 → 26 B/node, −91%; the timed run completes with **zero GC time**). The largest single change: each node mutates and restores one position instead of allocating a copy.

**Honorable mentions** (allocation or representation wins with little/no depth-4 speed effect):

- **`42612fe` — Pack move into a 20-bit fixnum.** 345 → 295 B/node (−14.5%), timing unchanged at depth 4; the gain is in allocation, not raw perft speed.
- **`1b94a4c` — Build move lists destructively with nconc/nconcing.** 409 → 375 B/node.
- **`98fe0ac` — Declare perft depth and return type; typed accumulation.** +4.7% (borderline, but consistent).

## Late-era regression check (powered A/B)

The depth-4 sweep cannot resolve small deltas in the modern era: a run takes ~25 ms, so 1 ms of timer jitter equals ~4%. The late commits were therefore re-measured with longer runs — five interleaved fresh-image arms, each doing **depth 5 × 10 runs (min)** and **one depth 6 run** (119,060,324 nodes). Allocation was identical across every arm (26.5 bytes/node at depth 6), so all differences below are codegen.

| Commit | Context | Depth-6 time | vs `a4753c9` |
|---|---|---|---|
| `a4753c9` | August peak (last pre-refactor commit) | 14.248 s / 14.357 s | — |
| `c150490` | Castling constants consolidated; `with-castling-params` now expands in `do-move!`/`undo-move!` | 14.588 s | +2.0% |
| `e62154d` | `attacked-by-kingless` helper added to the per-node legality context | 14.842 s | +4.2% |
| `c390c91` | Last iterate-using state | 14.798 / 14.919 / 15.067 s | +4.5% |
| `a82c23d` | Iterate removed (`do-bitboard` + `loop` instead of `iter`) | 15.384 s / 15.475 s | +8.0% |

Control: `e62154d` and `c390c91` have identical perft code (the commits between them touch only `fen.lisp` and add an unused macro) and measure identically (14.842 s vs 14.798–15.067 s), confirming the harness resolves sub-2% differences.

Findings:

- **The iterate removal cost ~3.4% at depth 6** (~2% at depth 5) — real but small, and invisible at depth 4. Root cause identified below: the push + `nreverse` list building.
- **A further ~2% had already been lost after the August peak** at `c150490` (root cause below). `e62154d` was re-measured with a component benchmark and is neutral within noise; its earlier ~1.8% attribution came from single-visit depth-6 runs.
- HEAD is therefore ~8% slower than the August peak (`a4753c9`) at depth 6 (15.38–15.48 s vs 14.25–14.36 s), despite identical allocation. The identified causes account for roughly 5–6 percentage points; the rest is within cross-visit measurement uncertainty. Recovering it is an open optimization opportunity, not a correctness issue.
- The corresponding rows in the depth-4 timeline above (for example `a82c23d` showing +8% against its predecessor) sit inside depth-4 quantization and should not be read as real gains or losses.

## Root-cause investigation

The confirmed regressions were traced to specific changes with `sb-sprof` profiles and component microbenchmarks (all worker-only; no source edits).

### `a82c23d` — iterate removal (~3.4% at depth 6)

- **Profile evidence:** `SB-IMPL::LIST-NREVERSE` accounts for **3.1% of total runtime** after the rewrite and is absent before it. Everything else in the rewrite is neutral or better (`EMIT-MOVES` self time 3.6% → 2.9%, `NCONC` 2.2% → 1.8%).
- **Static instruction counts mislead:** the rewritten code is *smaller* (`emit-moves` 85 → 69 instructions, `generate-pawn-moves` 1078 → 836, `generate-legal-moves` 100 → 59, `perft` 194 → 178) yet slower, because the cost is an extra traversal at runtime, not code size.
- **Component benchmark:** with the reversal removed, `generate-pawn-moves` (1,000,000 calls) drops from 0.222 s to 0.180 s (**−19%**); depth-6 perft recovers ~2–3% (13.79–14.25 s patched vs 14.25–14.68 s baseline in the same image).
- **Cause:** the rewrite replaced iterate's tail-consing `collect` with `push` + `nreverse` in `emit-moves`, `emit-pawn-moves`, and `emit-pawn-promos`. The reversal walks each freshly built list a second time.
- **Fix:** drop the `nreverse` (move order is unspecified and perft/tests are order-insensitive), or use tail-consing collectors to preserve order.

### `c150490` — castling consolidation (~2% at depth 6)

- **Cause:** `with-castling-params` was moved into `do-move!` and `undo-move!`, where its `let` bindings run **unconditionally for every move**. Only four bindings are used (rook from/to), and each is an `(if (eq side :white) …)` selection; the old code had those selections inside the castle branch, so non-castling moves paid nothing.
- **Component benchmark:** apply + undo (2,000,000 operations) drops from 0.101 s to 0.095 s (**−6%**) when the selections are moved back inside the branches — consistent with ~2–3% of perft.
- **Fix:** compute the rook-square constants inside the castle branches (or expand them lazily via a `macrolet`). Landed in Phase 2 with the `side-parameters` table — see the Phase 2 measurement below.

### `e62154d` — `attacked-by-kingless` (not a regression)

- The `make-legality-context` microbenchmark (300,000 calls) is unchanged: 0.132 s before, 0.129 s after. The earlier ~1.8% attribution from single-visit depth-6 runs was noise. No action needed.

## Phase 2: side-parameters table (working tree, uncommitted)

The `c150490` castling fix was landed structurally rather than as a local patch. All per-color knowledge now lives in a two-entry `side-parameters` table indexed by `color-index`; `do-move!`/`undo-move!` read the castling squares only when the move actually castles, and the pawn generators read their shifts from the same table. `with-castling-params`, `with-pawn-params`, `castling-safe-squares`, and the entire `castling.lisp` module are gone.

Measured against the Phase 1 state in one SBCL image (pre-Phase-2 snapshot loaded as `monsoon-base`, arms alternated, full GC before each run, depth 6 = 119,060,324 nodes):

| Arm | apply+undo, 2M ops | depth-6 |
|---|---|---|
| Phase 1 state | 0.097–0.099 s | 15.202 s / 17.256 s |
| Phase 2 | 0.079 s | 13.963 s / 14.226 s |

- **apply+undo: −19%** (0.098 → 0.079 s, min of four 2M-operation runs). The whole-move `with-castling-params` expansion is gone, so quiet moves no longer pay eleven `(if (eq side :white) …)` selections.
- **depth 6: −8.2%** against the best Phase-1 run (15.202 → 13.963 s), far past the ≥2% target. The original ~2–3% estimate undercounted because the table also removes the remaining pawn-direction conditionals from the every-move path.
- **Allocation unchanged:** 26.454 vs 26.432 bytes/node at depth 5; the component figures (`generate-moves` 41.57 MB per 100k calls, `generate-pawn-moves` 25.58 MB, `generate-rook-moves` 3.18 MB, `make-legality-context` 12.78 MB) are identical to the pre-Phase-2 numbers.
- **Correctness:** 13/13 tests, startpos `20/400/8902/197281`, Kiwipete `48/2039/97862`, Kiwipete depth 4, and positions 4–6 of the extended battery.

## Phase 3: macro hygiene (working tree, uncommitted)

Two changes: `union-attacks` now declares its injected binding at the call site (`(union-attacks (sq bb) expr)`), and the anaphora/hygiene policy is documented. The planned macro→function conversion for the slider attack masks was implemented, measured, and **reverted**:

| form of `rook-attack-mask` | rook-gen allocation, 100k calls |
|---|---|
| macro, direct splice (kept) | 3.18 MB |
| inline function | 6.39 MB (+32 B per call) |
| plain function | 25.59 MB (8×) |
| macro, gensym-bound arguments | 6.39 MB |

The function and `let`-bound forms force SBCL to unbox/rebox the 64-bit `occupied` value around the ray calls; only the direct-splice macro keeps it in its original representation. Since the masks already take `square` and `occupied` explicitly — there is no anaphora to remove — keeping the macro is both the hygienic and the allocation-free form. The macro comment and the developer docs record this.

Verification: 13/13 tests, perft gates exact, depth-5 allocation unchanged at **26.432 bytes/node** (identical to Phase 2), and a paired depth-6 A/B against the Phase 2 state in one image:

| round | Phase 2 | Phase 3 |
|---|---|---|
| 1 (base first) | 13.959 s | 14.070 s |
| 2 (current first) | 14.546 s | 14.442 s |

The net effect is inside the ±1.8% noise floor (one round +0.8%, the other −0.7%), as expected for a hygiene-only change.

## Planned resolution: allocation-free move generation

Both regressions above point at the same structural cost: every node builds a fresh list of moves, and the list-building mechanics (consing, `nreverse`, `nconc`, and the `remove-if-not` copy in `generate-legal-moves`) sit directly on the perft/search critical path. Rather than optimizing the list construction itself (tail-consing, or simply dropping the reversal), the planned direction is to **stop allocating a per-node move list entirely**:

- Piece generators emit moves into a caller-supplied buffer — a `(simple-array move (N))` plus a fill pointer — instead of consing a list. `emit-moves`, `emit-pawn-moves`, `emit-pawn-promos`, and the `nconc` assembly in `generate-moves` disappear from the hot path.
- A `with-legal-moves`-style macro (or a `do-bitboard`-style driver) owns the buffer for the duration of one node and exposes the filled slice; perft and search iterate that region directly, and legality filtering compacts in place rather than allocating a second list.
- This removes the `nreverse` pass *and* the per-node consing/GC pressure the current design incurs, so it subsumes both local micro-fixes suggested for the iterate-removal regression.

Expected effect: recovery of the ~3.4% reversal cost plus the remaining per-node allocation, to be measured with the same depth-6 A/B protocol once implemented. The `c150490` castling fix is independent of this refactor and landed separately in Phase 2 (measured below).

## Cross-library reference: `queen.lisp`

[queen.lisp](https://github.com/mishoo/queen.lisp) (Mihai Bazon, MIT) is an 0x88 mailbox chess library with legal move generation, FEN/SAN/PGN handling, a simple evaluation, and a depth-limited search. It is the closest CL comparison point for Monsoon's core. Both libraries were loaded into the same SBCL image on this machine and measured with the same protocol as the depth-6 checks: fresh position/game per run, full GC before each, wall-clock time. Queen's `perft` also accumulates capture/check/castle/promotion statistics at the leaves, but those are cheap flag tests.

| Benchmark (startpos unless noted) | Monsoon @ `7d7a9b8` | queen.lisp | Monsoon |
|---|---|---|---|
| perft 5 (4,865,609 nodes) | 0.618 / 0.621 / 0.625 s → **0.621 s (7.83M n/s)** | 1.319 / 1.334 / 1.325 s → **1.326 s (3.67M n/s)** | **2.1×** |
| perft 6 (119,060,324 nodes) | 15.046 / 15.181 s → **15.11 s (7.88M n/s)** | 32.902 / 32.709 s → **32.81 s (3.63M n/s)** | **2.2×** |
| Kiwipete perft 4 (4,085,603 nodes) | 0.511 / 0.504 / 0.511 s → **0.509 s (8.03M n/s)** | **1.108 s (3.69M n/s)**† | **2.2×** |
| legal move generation only, 1M calls (startpos) | 1.478 / 1.480 / 1.501 s → **~1.49 µs/call** | 4.785 / 4.831 / 4.821 s → **~4.81 µs/call** | **3.2×** |

† Single timed run after a warm-up; queen's two depth-6 runs agreed within 0.6%, so the ratio is stable. Both libraries produce the exact counts on both suites (startpos through depth 6; Kiwipete `48 / 2039 / 97862 / 4085603`).

Reading the numbers:

- The perft gap is the expected structural difference: bitboards with precomputed attack tables, packed fixnum moves, and a per-node legality context (Monsoon) versus an 0x88 mailbox that resolves legality during generation (queen).
- The move-generation gap is larger than the perft gap (3.2× vs 2.2×): queen resolves legality per candidate move during generation, while Monsoon pays one legality-context construction per node plus O(1) bit tests per move.
- Monsoon's figures are HEAD (`7d7a9b8`), i.e. before the two validated fixes in "Root-cause investigation". Those would bring startpos depth 6 to roughly 13.8–14.3 s, widening the lead to ~2.3–2.4×. The planned lazy generator would change the generation-only figure further.
- For calibration, queen's README reports ~36–40 s for perft 6 on its author's laptop, against ~4 s for Crafty on the same machine (a ~9× gap). This machine is in the same class (queen: 32.8 s here), so the ~4× gap between Monsoon and a 2016-era C engine implied by that ratio is a useful sanity check on the remaining headroom.
- Scope differs: queen is 1,928 lines covering FEN/SAN/PGN, evaluation, and search, with four dependencies (`named-readtables`, `anaphora`, `alexandria`, `cl-ppcre-unicode`). Monsoon is 1,641 source lines (+208 test lines), depends only on `serapeum` (plus `rove` for tests), and covers board/FEN/move generation/UCI scaffolding but no evaluation or search. The comparison above is of the shared core: board representation, move generation, and perft.

Reproduction (queen's `perft` is not exported, hence `queen::perft`):

```lisp
(push #p"/path/to/queen.lisp/" asdf:*central-registry*)
(asdf:load-system :queen)
(let ((g (queen:make-game)))
  (queen:reset-game g)
  (queen::perft g 6))
```

For Monsoon, use the depth-6 protocol from the late-era checks, above.

## Notes on broken commits

- `657a4b5` and `a65dcb3` (marked †) are broken as committed: `+castling-rights-mask+` uses `(sq :e1)` before the `sq` macro is defined later in the same file, so a clean compile fails. They were benchmarked with the `sq` macro pre-defined (the author's own definition) in the image.
- `bb976e3` … `baa2298`: `it:return` does not exist in `iterate`; the window is unbuildable until `68c0bc8`.
- `2ffaf6b`: builds but fails at runtime (`:white` assigned to a `bit`-typed slot); reverted in `7ed02cb`.
- `f5d7d71`: the alexandria removal left `with-gensyms` calls behind; fixed in `a82c23d`.

## Reproduction

```lisp
;; per commit:
;;   check out the commit, start a fresh SBCL image, then:
(asdf:load-system :monsoon :force t)          ; clear stale FASLs first
(let ((pos (monsoon::position-from-fen
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")))
  (monsoon::perft pos 4)                      ; warm-up
  (loop repeat 5
        do (sb-ext:gc :full t)
           (let ((start (get-internal-real-time)))
             (monsoon::perft pos 4)
             (format t "~,3f s~%"
                     (/ (- (get-internal-real-time) start)
                        internal-time-units-per-second)))))
```

Absolute numbers depend on the machine; the ratios are the point. Commits that do not touch `src/` are absent from the timeline (they cannot change the benchmark), and merge commits are omitted because their parents cover the same code.
