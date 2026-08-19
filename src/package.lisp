(defpackage :monsoon
  (:use :cl :iterate)
  (:shadow :position)
  (:import-from :serapeum #:defconst #:tokens)
  (:import-from :alexandria #:with-gensyms)

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
   #:generate-legal-moves

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
   #:uci-go-param-searchmoves
   #:uci-go-param-ponder
   #:uci-go-param-wtime
   #:uci-go-param-btime
   #:uci-go-param-winc
   #:uci-go-param-binc
   #:uci-go-param-movestogo
   #:uci-go-param-depth
   #:uci-go-param-nodes
   #:uci-go-param-mate
   #:uci-go-param-movetime
   #:uci-go-param-infinite
   #:uci-parse-move
   #:uci-move-string
   ))
