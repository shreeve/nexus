(grammar
  (lang `"messages"`)
  (section `lexer`)
  (tokens `tokens` `ident` `number` `kw_print` `eq` `semi` `lt` `gt` `plus` `lparen` `rparen` `eof` `err`)
  (lex_rule
    `'\\n'`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule `'='` _ `eq`)
  (lex_rule `';'` _ `semi`)
  (lex_rule `'<'` _ `lt`)
  (lex_rule `'>'` _ `gt`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `"print"` _ `kw_print`)
  (lex_rule `[a-z]+` _ `ident`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (display
    (name_pair `IDENT` `"a name"`)
    (name_pair `NUMBER` `"a number"`)
    (name_pair `KW_PRINT` `"'print'"`))
  (errors
    (name_pair `stmt` `"a statement"`)
    (name_pair `expr` `"an expression"`))
  (repair
    (repair_line `holes` `IDENT`)
    (repair_line `terminator` `";"`))
  (messages
    (message
      `after`
      _
      `"expected ';' after the value, got {got}"`
      (msg_sym `IDENT` _)
      (msg_sym `"="` _)
      (msg_sym `expr` _)
      (msg_choice
        (msg_sym `IDENT` _)
        (msg_sym `KW_PRINT` _)))
    (message
      `after`
      _
      `"expected ';' after the value, got {got}"`
      (msg_sym `KW_PRINT` _)
      (msg_sym `expr` _)
      (msg_choice
        (msg_sym `IDENT` _)
        (msg_sym `KW_PRINT` _)))
    (message
      `at`
      _
      `"comparison operators cannot be chained"`
      (msg_sym `IDENT` _)
      (msg_sym `"="` _)
      (msg_sym `IDENT` _)
      (msg_sym `"<"` _)
      (msg_sym `IDENT` _)
      (msg_choice
        (msg_sym `"<"` _)
        (msg_sym `">"` _)))
    (message
      `at`
      _
      `"comparison operators cannot be chained"`
      (msg_sym `IDENT` _)
      (msg_sym `"="` _)
      (msg_sym `IDENT` _)
      (msg_sym `">"` _)
      (msg_sym `IDENT` _)
      (msg_choice
        (msg_sym `"<"` _)
        (msg_sym `">"` _)))
    (message
      `after`
      _
      `"\`?\` is not an operator; write a comparison"`
      (msg_sym `stmt` _)
      (msg_sym `ERR` `"?"`))
    (message
      `after`
      _
      `"unexpected {got} after a statement"`
      (msg_sym `stmt` _)
      (msg_sym `ERR` _))
    (message
      `at`
      `expr`
      `"\`(\` is never closed: expected {expected}"`
      (msg_sym `"("` _)
      (msg_sym `IDENT` _)
      (msg_sym `EOF` _)))
  (rule
    (start `program`)
    (alt
      _
      ((quantified
          (ref `stmt`)
          (one_plus)))
      (node
        `program`
        (spread `1`))
      _))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `set`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `KW_PRINT`)
        (ref `expr`)
        (lit `";"`))
      (node
        `print`
        (pos `2`))
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `sum`))
      _
      _)
    (alt
      _
      ((ref `sum`)
        (lit `"<"`)
        (ref `sum`))
      (node
        `lt`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `sum`)
        (lit `">"`)
        (ref `sum`))
      (node
        `gt`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `sum`)
    (alt
      _
      ((ref `term`))
      _
      _)
    (alt
      _
      ((ref `sum`)
        (lit `"+"`)
        (ref `term`))
      (node
        `add`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `term`)
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
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _)))
