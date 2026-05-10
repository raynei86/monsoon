# Public API reference

All public symbols are exported from the `:monsoon` package in
`src/package.lisp`. This section documents those exported symbols and how to
use them.

## Types and constants

- `square` — type for a board square as an integer `[0, 63]`.
- `bitboard` — 64-bit integer bitboard representation.
- `file` — integer `[0, 7]` for file.
- `rank` — integer `[0, 7]` for rank.

## Square helpers

- `sq` — macro mapping a keyword like `:e4` to its square index.
- `file-of` — returns the file index for a square.
- `rank-of` — returns the rank index for a square.

## Piece indexing

- `colored-piece-index` — returns an index `[0, 11]` for a piece/color pair.

## Position representation

- `position` — struct representing a chess position.
- `with-position` — macro binding common position state:
  `side`, `occupied`, `friendly`, `enemy`.
- `pos-boards` — bitboards for each colored piece (12 entries).
- `pos-by-color` — bitboards for each color (2 entries).
- `pos-by-piece` — bitboards for each piece kind (6 entries).
- `pos-occupied-sqaures` — exported misspelling of the occupied-squares bitboard.
  Note: the struct accessor is spelled `pos-occupied-squares` in the source.
- `pos-side-to-move` — `:white` or `:black`.
- `pos-castling` — castling rights bitmask.
- `pos-ep-square` — en passant square or `NIL`.
- `pos-hash` — hash key (placeholder; Zobrist not implemented).

## Position queries

- `occupied-p` — returns true if a square is occupied.
- `color-at` — returns the occupant color (assumes occupied).
- `piece-at` — returns the occupant piece type (assumes occupied).
- `occupant-at` — returns `(values piece color)` or `(values NIL NIL)`.
- `with-square` — macro binding `piece` and `color` at a square.
- `opponent` — returns the opposite color.

## Moves

- `move` — struct with `from`, `to`, `promotion`, `flags`.
- `with-move` — macro binding `from`, `to`, `promotion`, `flags`.
- `do-move` — returns a new position after applying a move.
- `generate-moves` — returns pseudo-legal moves for the side to move.
- `king-in-check-p` — tests if a color is in check.
- `legal-move-p` — true if a move does not leave the mover in check.

## FEN

- `position-from-fen` — constructs a `position` from a FEN string.

## Example usage

```lisp
(defparameter *start*
  (monsoon:position-from-fen
   "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))

(defparameter *moves* (monsoon:generate-moves *start*))

;; Pick the first legal move and apply it.
(defparameter *first-legal*
  (find-if (lambda (mv) (monsoon:legal-move-p *start* mv)) *moves*))

(defparameter *next* (monsoon:do-move *start* *first-legal*))

;; Inspect a square.
(monsoon:with-square (piece color) *next* (monsoon:sq :e4)
  (list piece color))
```
