(grammar
  (section `lexer`)
  (state
    `state`
    (assign `beg` `1`)
    (assign `depth` `0`))
  (after
    `after`
    (assign `beg` `0`))
  (tokens `tokens` `ident` `integer` `string_dq` `plus` `minus` `star` `assign` `comma` `colon` `lparen` `rparen` `arrow` `newline` `comment` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'"' ([^"\\\\$\\n] | '\\\\' . | '$')* '"'` _ `string_dq`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'='` _ `assign`)
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule
    `'('`
    _
    `lparen`
    (step_action `depth` `++`))
  (lex_rule
    `')'`
    _
    `rparen`
    (step_action `depth` `--`))
  (lex_rule
    `'\\n'`
    _
    `newline`
    (set_action `beg` `1`))
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"features"`)
  (rule
    (name `name`)
    (alt
      _
      ((tok `IDENT`))
      _
      _))
  (rule
    (start `program`)
    (alt
      _
      ((ref `body`))
      (node
        `module`
        (spread `1`))
      _))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)
      _))
  (rule
    (name `body`)
    (alt
      _
      ((ref `stmt`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`)
        (ref `stmt`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `call`)
        (lit `"="`)
        (ref `expr`))
      (node
        `assign`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((at_ref `infix`))
      _
      _))
  (rule
    (name `call`)
    (alt
      _
      ((ref `call`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `atom`))
      _
      _))
  (rule
    (name `args`)
    (alt
      _
      ((list_req
          `L`
          (plain `expr`)))
      (list
        (spread `1`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `atom`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `STRING_DQ`))
      _
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _))
  (infix
    `call`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`))))
