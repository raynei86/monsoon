# Developer guide

This guide covers the internal architecture, data representations, and algorithms used by Monsoon. It assumes familiarity with Common Lisp but not with chess engine internals.

## Codebase layout

```
monsoon.asd          — ASDF system definition (main + test systems)
src/
  package.lisp       — single package :monsoon with all exports
  types.lisp         — squares, bitboards, pieces, colors, castling rights
  position.lisp      — position struct, board mutation, position macros
  utils.lisp         — bitboard helpers (lsb, msb) and iterate clause
  moves.lisp         — packed move type, attack tables, move generation, do-move
  fen.lisp           — FEN string parsing → position
  uci.lisp           — UCI protocol engine base class and I/O loop
tests/
  main.lisp          — rove test suite
docs/
  api.md             — public API reference
  developer-guide.md — this file
```

## Type system

All fundamental types are defined as `deftype` aliases over CL integer types, keeping the codebase type-annotated without struct overhead.

| Type | Underlying type | Meaning |
|---|---|---|
| `square` | `(unsigned-byte 6)` | Board index 0–63, computed as `rank * 8 + file` |
| `bitboard` | `(unsigned-byte 64)` | One bit per square |
| `castling-rights` | `(unsigned-byte 4)` | One bit each for WK, WQ, BK, BQ |
| `color` | `(member :white :black)` | Side |
| `piece` | `(member :pawn … :king)` | Piece kind |
| `colored-piece-code` | `(unsigned-byte 4)` | Combined piece+color index |

- 12 colored-piece bitboards (`pos-boards`): one per piece kind and color.
- 2 color bitboards (`pos-by-color`): aggregate by color.
- An occupancy bitboard that is always kept in sync.
- Side to move, castling rights, en passant square, and clocks.

The `sq` function converts symbolic square names (`:e4`, `:h1`, etc.) to their integer index. It is declared `inline`, so constant calls inside `defconst` and other load-time forms fold to a single integer at compile time; it also accepts runtime values.

`colored-piece-index` maps a `(piece, color)` pair to an integer in `[0, 11]` by interleaving colors: white pawn → 0, black pawn → 1, white knight → 2, and so on up to black king → 11. This index is the key into every `pos-boards` array slot. `color-index` and `piece-index` compute the components separately when needed.

All constants use `defconst` (imported from `serapeum`) rather than `defconstant`. SBCL treats `defconstant` redefinition as an error during interactive development; `defconst` avoids this while still communicating the intent.

## Board representation

Monsoon uses a triple-redundant bitboard representation. A `position` struct holds three overlapping views of the same board state:

- **`pos-boards`** — 12-element array indexed by `colored-piece-index`, one bitboard per colored piece.
- **`pos-by-color`** — 2-element array, the aggregate occupancy for each color.
- **`pos-occupied-squares`** — the union of the two color boards.

The redundancy is intentional: different parts of move generation need different views, and keeping all of them in sync avoids repeated union operations in tight loops.

All mutations go through `place-piece!` and `remove-piece!`, which update all three views atomically. `do-move` copies the position via `copy-position` before mutating it, so the input position is never modified. For hot paths, `do-move!` applies a move destructively and returns the values `undo-move!` needs to restore it; the `with-move-applied` macro wraps apply/body/undo so a single position can be reused instead of copied per move.

## Move generation

Move generation is split into two stages: pseudo-legal generation followed by legal filtering.

### Pseudo-legal generation

`generate-moves` concatenates the output of six per-piece generators. Each generator uses `with-position` to bind `side`, `occupied`, `friendly`, and `enemy` from the position, then produces moves as a list of packed `move` integers.

**King and knight** moves are handled identically: a precomputed attack table (`+king-attacks+` and `+knight-attacks+`) is indexed by the piece's square, and the result is masked against friendly squares to exclude self-captures. The `generate-major-piece-moves` macro factors out this common pattern.

**Sliding pieces** use precomputed ray tables. `+rays+` is an array of eight ray tables (one per compass direction), each mapping a square to the set of all squares reachable along that ray ignoring blockers. At move-generation time, `ray-attacks+` and `ray-attacks-` cut a ray at the first occupied square using `lsb` (for positive directions) or `msb` (for negative directions). The rook, bishop, and queen attack masks are assembled by ORing the appropriate rays together.

The attack-mask forms (`rook-attack-mask`, `bishop-attack-mask`, `queen-attack-mask`) are macros rather than functions. This is because `generate-major-piece-moves` is itself a macro that introduces a `from` binding for the current piece's square, and the attack expressions need to reference that binding. Making the attack forms macros allows them to be written as if `from` were in scope, which it is at the point of macro expansion.

**Pawns** are handled entirely with bitboard shifts and masks, with no per-pawn iteration. Single pushes, double pushes, east captures, and west captures are each computed as a bitboard operation on all pawns at once. Target bitboards are then split against the promotion-rank mask to separate promotion moves from quiet moves before emitting packed `move` integers. En passant is handled by masking captures against a single-bit bitboard for the en passant square.

**Castling** checks the relevant rights bits and empty-path masks, then emits a king move tagged with `+move-flag-kingside+` or `+move-flag-queenside+`. The rook relocation is handled inside `do-move` when those flags are present, rather than in the generator itself.

### Legal filtering

Legality is classified without making each move. `make-legality-context` computes per-position invariants once: `king-danger` (enemy attacks with the moving king removed, which both detects check and validates king destinations), the set of own pieces pinned to the king and the line each is restricted to, and an evasion mask when in check (capture the checker or block its ray). `move-legal-p` then classifies each candidate with O(1) bit tests — castling must not be out of/through/into check, king moves must not land on an attacked square, pinned pieces must stay on their pin line, and in-check moves must reach the evasion mask. Everything else is legal. `generate-legal-moves` filters the pseudo-legal list with `move-legal-p`.

## FEN parsing

`position-from-fen` is the primary constructor for positions. The `with-fen-fields` macro destructures the six space-separated FEN fields from the input string using `tokens`. Each field is then parsed by a dedicated helper: `parse-placement!` walks the piece-placement string and calls `place-piece!` for each piece character it encounters; `parse-castling` accumulates the rights bits; `parse-ep-square` converts the algebraic square string to an index by interning it as a keyword and passing it through `sq`.

FEN parsing does not validate the resulting position. It trusts well-formed input.

## UCI engine scaffold

`uci-engine` is a CLOS base class that handles the full UCI wire protocol, leaving only the search logic to subclasses. The I/O loop (`uci-run`) reads lines from a stream, dispatches via `uci-handle-line`, and writes responses back. All line formatting and protocol state management is in the base class.

Engine behaviour is customised by overriding generic functions:

| Generic | Default behaviour | Must override? |
|---|---|---|
| `uci-engine-name` | Returns `"Monsoon"` | Recommended |
| `uci-engine-author` | Returns `"Unknown"` | Recommended |
| `uci-engine-options` | Returns `nil` | Only if the engine has options |
| `uci-new-game` | No-op | Only if game state needs resetting |
| `uci-set-option` | Stores value in hash table | Only to handle options specially |
| `uci-position-updated` | No-op | Only if incremental state must update |
| `uci-go` | Signals an error | **Yes** |
| `uci-stop` | No-op | Only for threaded engines |
| `uci-ponderhit` | No-op | Only for engines that ponder |
| `uci-ready` | No-op | Only for deferred initialisation |
| `uci-quit` | No-op | Only if resources need releasing |

`uci-go` is currently called synchronously by the I/O loop. This means `uci-stop` is invoked only after `uci-go` has already returned, so a single-threaded engine that blocks in `uci-go` will never see a stop signal mid-search. Engines that launch a background search thread should coordinate via a shared flag.

`uci-go` must return two values: the best move (a `move` struct, a UCI string, or `nil` for `0000`), and an optional ponder move or `nil`.

## Extending the library

**Adding a new move flag:** the `flags` slot of `move` is `(unsigned-byte 5)`, so five bits are available. Define a new `+move-flag-*` constant in `moves.lisp`, handle it in `do-move`, and emit it from the appropriate generator.

**Implementing a search engine:** subclass `uci-engine` and override `uci-go`. `generate-legal-moves` is the starting point for enumerating candidates. Keep all engine-specific state in the subclass slots.

**Adding Zobrist hashing:** the `pos-hash` slot exists in `position` and is initialised to 0 but is not yet maintained. The natural integration point is `place-piece!` and `remove-piece!`, which are called for every board mutation — XOR the relevant Zobrist key in or out there. The key table would live in `types.lisp` or a new `src/hash.lisp` component added to the `.asd`.

## Dependencies

| Library | Role |
|---|---|
| `iterate` | Extended iteration (`iter`, `for`, `in-bitboard` clause) |
| `serapeum` | `defconst`, `tokens`, `nest` |
| `alexandria` | `with-gensyms` in macro internals |
| `rove` | Test framework (test system only) |

The package `:use`s `:iterate`, so iterate forms within `:monsoon` are written bare (`iter`, `for`, `collect`, …).
