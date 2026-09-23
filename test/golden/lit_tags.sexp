(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `integer` `assign` `plus_assign` `arrow` `newline` `eof` `err`)
  (lex_rule `'+='` _ `plus_assign`)
  (lex_rule `'='` _ `assign`)
  (lex_rule `'->'` _ `arrow`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
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
      ((tok `IDENT`)
        (lit `"="`)
        (tok `INTEGER`))
      (node
        `set`
        (tag `fixed`)
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (lit `"->"`)
        (tok `INTEGER`))
      (node
        `set`
        (tag `move`)
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (lit `"+="`)
        (tok `INTEGER`))
      (node
        `set`
        (tag `+=`)
        (pos `1`)
        (null)
        (pos `3`))
      _)))
