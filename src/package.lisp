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

   #:uci-engine
   #:uci-engine-position
   #:uci-engine-option-values
   #:uci-engine-debug
   #:uci-engine-name
   #:uci-engine-author
   #:uci-engine-options
   #:uci-new-game
   #:uci-set-option
   #:uci-position-updated
   #:uci-go
   #:uci-stop
   #:uci-ponderhit
   #:uci-ready
   #:uci-quit
   #:uci-run
   #:uci-handle-line
   #:+uci-startpos-fen+
   #:uci-option
   #:make-uci-option
   #:uci-option-name
   #:uci-option-type
   #:uci-option-default
   #:uci-option-min
   #:uci-option-max
   #:uci-option-vars
   #:uci-go-parameters
   #:make-uci-go-parameters
   #:uci-go-searchmoves
   #:uci-go-ponder
   #:uci-go-wtime
   #:uci-go-btime
   #:uci-go-winc
   #:uci-go-binc
   #:uci-go-movestogo
   #:uci-go-depth
   #:uci-go-nodes
   #:uci-go-mate
   #:uci-go-movetime
   #:uci-go-infinite
   #:uci-parse-move
   #:uci-move-string
   ))
