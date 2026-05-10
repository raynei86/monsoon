(defpackage :monsoon
  (:use :cl)
  (:shadow :position)
  (:local-nicknames (:it :iterate))

  (:export
   #:square
   #:sq
   #:bitboard
   #:file
   #:rank
   #:file-of
   #:rank-of
   #:colored-piece-index

   #:position
   #:with-position
   #:pos-boards
   #:pos-by-color
   #:pos-by-piece
   #:pos-occupied-squares
   #:pos-side-to-move
   #:pos-castling
   #:pos-ep-square
   #:pos-hash

   #:occupied-p
   #:color-at
   #:piece-at
   #:occupant-at
   #:with-square
   #:opponent

   #:move
   #:with-move
   #:do-move
   #:generate-moves
   #:king-in-check-p
   #:legal-move-p

   #:position-from-fen
   ))

