# AGENTS.md — Monsoon Chess Library

## Project overview

Monsoon is a Common Lisp chess library providing bitboard-based board representation, pseudo-legal and legal move generation, FEN parsing, and a full UCI engine protocol scaffold. The codebase targets SBCL 2.4.x and its dependency (`serapeum`) is resolved via quicklisp through Roswell.

The library's guiding principle is **clarity and abstraction first, performance second**. When a choice must be made between the two, lean toward the more readable and well-abstracted solution. Performance is not ignored — `declaim inline`, precomputed attack tables, and typed array accesses appear throughout — but it must be justified by clarity of intent, not raw micro-optimisation instinct.

---

## Repository layout

```
monsoon.asd          — ASDF system definition (main + test systems)
src/
  package.lisp       — single package :monsoon with all exports
  types.lisp         — squares, bitboards, pieces, colors, castling rights and
                       geometry, per-side parameters, packed move type
  position.lisp      — position struct, board mutation, make/unmake, position macros
  utils.lisp         — bitboard helpers (lsb, msb) and the do-bitboard macro
  attacks.lisp       — attack tables, ray math, attacked squares, checks, pins
  movegen.lisp       — move generation, legality classification, perft
  fen.lisp           — FEN string parsing → position
  uci.lisp           — UCI protocol engine base class and I/O loop
tests/
  main.lisp          — rove test suite
docs/
  api.md                 — public API reference
  developer-guide.md     — architecture overview
  performance-history.md — measured perft history across the git timeline
```

---

## Running tests

With the project linked into a quicklisp/Roswell source location (see `README.org`), run:

```lisp
(asdf:test-system :monsoon)
```

or in one go from a shell: `ros run -e '(asdf:test-system :monsoon)'`.

This loads `monsoon/tests` (which depends on `monsoon` and `rove`) and calls `(rove:run c)` via the `:perform` clause. All tests live in `tests/main.lisp`. There is no separate test runner script; the ASDF hook is the only supported entry point.

---

## Architecture

### Types (`types.lisp`)

All fundamental types are defined here as `deftype` aliases over CL integer types, keeping the rest of the codebase type-annotated without any struct overhead:

- `square` — `(unsigned-byte 6)`, a board index 0–63, laid out as `rank * 8 + file`.
- `bitboard` — `(unsigned-byte 64)`, one bit per square.
- `castling-rights` — `(unsigned-byte 4)`, one bit each for WK/WQ/BK/BQ.
- `color` — `(member :white :black)`.
- `piece` — `(member :pawn :knight :bishop :rook :queen :king)`.

The `sq` function converts symbolic square names (e.g. `:e4`) to their integer index. It is declared `inline`, so constant calls like `(sq :e4)` fold to a single integer at compile time; it also accepts runtime values.

Color and piece indices are produced by `color-index` and `piece-index`. The combined `colored-piece-index` maps a `(piece, color)` pair to `[0, 11]` and is the key into the `pos-boards` array. These functions are declared `inline`.

Constants use `defconst` (imported from `serapeum`) rather than `defconstant` to avoid SBCL's redefinition errors during iterative development.

### Side parameters (`types.lisp`)

Everything that depends on which color is moving lives in one `side-parameters`
struct per color, indexed by `color-index` through the inline `side-params`
function:

- **Pawn geometry** — `push-shift` (toward the opponent), `pawn-back-shift`
  (behind an advanced pawn: EP square and EP victim), `cap-e-shift`,
  `cap-w-shift`, `start-rank`, `promo-rank`.
- **Castling geometry** — king and rook origin/destination squares, the rights
  bit for each wing, and the empty/safe square masks for each wing.

The fields are explicit rather than derived: `pawn-back-shift` is separate from
`push-shift`, so callers never negate a shift or infer a direction from color.
The table is a `defparameter` initialized at load time, not a `defconst`,
because its initializer calls `sq`.

`checkers` uses the "king-shift trick": enemy pawns attack a king from exactly
the squares the defender's own pawns would capture, so it shifts the king by the
defender's `cap-e`/`cap-w` shifts instead of generating the attacker's pawn
attacks.

### Position (`position.lisp`)

The `position` struct is the central data type. It carries three redundant-but-consistent views of the board:

- `pos-boards` — 12-element array, indexed by `colored-piece-index`.
- `pos-by-color` — 2-element array, aggregate occupancy per color.
- `pos-occupied-squares` — union of the two color boards.

**All board mutations go through `place-piece!` and `remove-piece!`**, which keep all three views in sync. Never touch individual array slots directly outside these two functions. Both are declared `inline`.

`do-move` is the public way to apply a move: it copies the position first, so its input is never mutated. For hot paths (perft, search), `do-move!` applies a move destructively and returns the values `undo-move!` needs to restore it, and the `with-move-applied` macro wraps apply/body/undo so a single position object can be reused instead of copied per move.

`with-position` is a convenience macro that binds `side`, `occupied`, `friendly`, and `enemy` from a position in one go. Use it at the top of move-generation functions rather than repeatedly accessing slots.

### Move generation (`attacks.lisp`, `movegen.lisp`)

The packed `move` representation lives in `types.lisp`, alongside the
`side-parameters` table that holds all per-color movement and castling geometry;
attack tables, ray math, and attack queries live in `attacks.lisp`; the
generators and legality layer in `movegen.lisp`. Move generation is split into
pseudo-legal generation followed by legal filtering:

1. `generate-moves` — appends results from all per-piece generators.
2. `move-legal-p` — classifies each candidate against a precomputed `legality-context` (enemy attacks with the king removed, pinned pieces, and an evasion mask when in check) using O(1) bit tests, without making the move.
3. `generate-legal-moves` — filters the pseudo-legal list with `move-legal-p`.

**Precomputed tables** (`+king-attacks+`, `+knight-attacks+`, `+rays+`) are built at load time using the `build-attack-table` and `build-ray-table` macros. These macros are load-time tools, not runtime abstractions; do not call them from non-toplevel code.

Sliding piece attacks use the classical positive/negative ray technique. `ray-attacks+` uses `lsb` (lowest set bit) to find the first blocker along a positive ray; `ray-attacks-` uses `msb`. The attack-mask forms (`rook-attack-mask`, `bishop-attack-mask`, `queen-attack-mask`) take `(square occupied)` as explicit arguments — there is no anaphoric binding. They stay macros rather than functions because a function boundary forces an extra 64-bit representation conversion per slider call (measured; see `docs/performance-history.md`), and the arguments are spliced directly, so pass variables.

Pawn generation uses bitboard shift arithmetic entirely (no per-pawn loop). Promotions are emitted by splitting target bitboards against the promotion-rank mask before calling `emit-pawn-promos`.

The `do-bitboard` macro (defined in `utils.lisp`) pops bits from a bitboard one at a time using `lsb` and a bit-clear trick. It is the standard idiom for iterating over a piece's squares throughout the codebase.

`perft` is a development utility used for correctness and basic performance measurement. It is not part of the public API and need not be exposed or extended.

### FEN parsing (`fen.lisp`)

`position-from-fen` is the primary entry point for constructing a position. The `with-fen-fields` macro destructures the six FEN fields from a string via `tokens`. FEN parsing is intentionally simple and does not validate the resulting position; it trusts well-formed input.

The `parse-ep-square` function interns the square string as a keyword and passes it through `sq`.

### UCI scaffold (`uci.lisp`)

`uci-engine` is a CLOS base class. Engine implementors subclass it and override the generic functions listed below. Only `uci-go` **must** be overridden; the rest have no-op defaults.

| Generic | Responsibility |
|---|---|
| `uci-engine-name` | Return engine name string |
| `uci-engine-author` | Return author string |
| `uci-engine-options` | Return list of `uci-option` structs |
| `uci-new-game` | Reset game-specific state |
| `uci-set-option` | Handle `setoption`; default stores in hash table |
| `uci-position-updated` | Hook called after position is updated |
| `uci-go` | Run search; return `(values bestmove ponder-or-nil)` |
| `uci-stop` | Signal search to stop (for threaded engines) |
| `uci-ponderhit` | Switch pondering search to timed |
| `uci-ready` | Deferred init before `readyok` |
| `uci-quit` | Tear down and release resources |

`uci-run` is the blocking I/O loop; pass a subclassed engine to it with optional `:input` / `:output` streams. `uci-handle-line` dispatches a single tokenised line and is exposed for testing command handling without starting a full loop.

`uci-go` is currently called **synchronously**. Threaded engines must launch their search in `uci-go` and set a stop flag in `uci-stop`; `uci-stop` is called after `uci-go` has returned in the synchronous model, so threaded engines need their own coordination.

---

## Code style

**Idioms to follow:**

- Use `defconst` for any constant that should not cause redefinition errors.
- Use `(do-bitboard (sq bb) …)` to iterate over set bits in a bitboard. Never loop over integers 0–63 unless you genuinely need all 64.
- Use `with-position`, `with-move`, and `with-square` to destructure the common
  aggregates, and `side-params` to read per-color movement and castling
  parameters. Adding new destructuring macros in the same pattern is encouraged
  when it reduces slot-access repetition.
- `ecase` is preferred over `case` for exhaustive dispatch on types and keywords — it errors on unexpected values rather than silently falling through.
- Accessors generated by `defstruct` (e.g. `pos-side-to-move`, `move-from`) are the public interface. Do not access struct slots by index or use internal SBCL accessors.

**Idioms to avoid:**

- Do not `(loop for i from 0 to 63 …)` over the board when a bitboard iteration or attack-table lookup will do.
- Do not add magic numbers. All square indices should come from `(sq :name)`, all bit masks from named `+constants+`.
- Do not inline complex logic into `generate-attack-table` / `generate-ray-table` body forms at load time for the sake of performance. The tables are only built once; clarity in their construction matters more.
- Do not shadow or redefine `position` outside the test package (where `:shadow :cl:position` is already noted as a necessary evil for the `:use :monsoon` import).
- **Macro hygiene:** anaphora is allowed only for documented, caller-facing
  bindings (`from` in `generate-major-piece-moves`; `sq` in `do-bitboard` and
  `(union-attacks (sq bb) expr)`). Document every injected binding in the
  macro docstring, and declare it at the call site when the macro supports
  that. Bindings created internally by an expansion use gensyms (see
  `with-position`, `with-move-applied`).

**Macro taxonomy:** `with-…` establishes bindings or state and unwinds it
(`with-position`, `with-move`, `with-square`, `with-fen-fields`,
`with-move-applied`); `build-…` is load-time table construction
(`build-attack-table`, `build-ray-table`); `generate-…` is runtime move
generation (`generate-moves`, `generate-rook-moves`). Do not use `generate-`
for load-time or codegen helpers.

**Performance annotations:**

`(declaim (inline …))` is used for small, frequently-called functions (`lsb`, `msb`, `occupied-p`, `color-at`, `piece-at`, `occupant-at`, `place-piece!`, `remove-piece!`, `opponent`, and the index functions in `types.lisp`). Add `inline` declarations conservatively and only where profiling or clear reasoning justifies it. `(declare (type …))` annotations in hot functions are welcome and help SBCL generate better code, but they are not required on every function.

**Cross-file interface declarations:** hot-path functions called from another
source file must carry `ftype` declarations when they return bitboards (see
the interface block at the end of `attacks.lisp`). A compilation-unit boundary
loses the inferred return type at the FASL edge, and callers silently fall back
to generic, allocating arithmetic.

---

## Extending the library

**Adding a new piece or move type:** Define any new bitboard constants in `types.lisp`. Add generation logic in `movegen.lisp` following the pattern of the existing per-piece functions. Wire it into `generate-moves`. Add `+move-flag-*` constants in `types.lisp` if new flag bits are needed; the flags field is `(unsigned-byte 5)` so five bits are currently available. Per-color movement knowledge belongs in the `side-parameters` table; do not add a new `(if (eq side :white) …)` dispatch.

**Implementing a search engine:** Subclass `uci-engine`, override `uci-go` to run search and return a move, and optionally override the lifecycle hooks. `generate-legal-moves` is your starting point for enumerating moves. Do not modify the base class to add engine-specific state; keep it in the subclass.

**Adding Zobrist hashing:** The `pos-hash` slot exists in `position` and is initialised to 0. Hashing is not yet implemented. The natural place to add it is in `place-piece!` and `remove-piece!` (XOR in/out the relevant Zobrist key), with the key table defined in `types.lisp` or a new `src/hash.lisp` component added to the `.asd`.

---

## Dependencies

| Library | Role |
|---|---|
| `serapeum` | `defconst`, `tokens` |
| `rove` | Test framework (test system only) |

The package uses only `:cl`; `do-bitboard` and plain `loop` are the iteration idioms within `:monsoon`.
