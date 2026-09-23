(grammar
  (section `lexer`)
  (tokens `tokens` `integer` `ident` `plus` `minus` `star` `slash` `power` `lparen` `rparen` `newline` `eof` `err`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'/'` _ `slash`)
  (lex_rule `"**"` _ `power`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"basic"`)
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
      ((at_ref `infix`))
      _
      _))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"-"`)
        (ref `unary`))
      (node
        `neg`
        (pos `2`))
      _)
    (alt
      _
      ((ref `atom`))
      _
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
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _))
  (infix
    `unary`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`))
    (level
      (infix_op `"**"` `right`))))
