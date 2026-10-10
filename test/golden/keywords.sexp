(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `number` `dollar` `lparen` `rparen` `comma` `newline` `eof` `err`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `'$'` _ `dollar`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `','` _ `comma`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]* '?'?` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"keywords"`)
  (keywords
    (kw_group `cmd` `caseless` `base` `100` `S[ET]` `W[RITE]` `H[ANG]` `HALT` `Q[UIT]` `ZW[RITE]` `ZT=ZWRITE` `TRO[LLBACK]` `TRE[START]`)
    (kw_group `fn` `caseless` `base` `200` `L[ENGTH]` `E[XTRACT]` `P[IECE]` `ZD[ATE]` `ZDATEH`)
    (kw_group `word` `begin:BEGIN_KW` `end` `"nil?":NIL_P`))
  (as
    `IDENT`
    _
    (as_entry perm `cmd` _)
    (as_entry perm `fn` _)
    (as_entry perm `word` _))
  (rule
    (start `prog`)
    (alt
      _
      ((quantified
          (ref `line`)
          (one_plus)))
      (node
        `prog`
        (spread `1`))
      _))
  (rule
    (name `line`)
    (alt
      _
      ((ref `cmd`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `cmd`)
    (alt
      _
      ((tok `SET`)
        (tok `IDENT`)
        (ref `expr`))
      (node
        `set`
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `WRITE`)
        (list_req
          `L`
          (plain `expr`)))
      (node
        `write`
        (pos `1`)
        (spread `2`))
      _)
    (alt
      _
      ((tok `HANG`)
        (ref `expr`))
      (node
        `hang`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((tok `HALT`))
      (node
        `halt`
        (pos `1`))
      _)
    (alt
      _
      ((tok `CMD`)
        (group
          opt
          ((list_req
              `L`
              (plain `expr`)))))
      (node
        `cmd`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `NUMBER`))
      _
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `LENGTH`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `length`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `FN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `call`
        (pos `2`)
        (spread `4`))
      _)
    (alt
      _
      ((tok `BEGIN_KW`)
        (ref `expr`)
        (tok `END`))
      (node
        `block`
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `NIL_P`)
        (ref `expr`))
      (node
        `nil?`
        (pos `1`)
        (pos `2`))
      _)))
