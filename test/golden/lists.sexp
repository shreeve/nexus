(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `star` `plus` `comma` `slash` `query` `equals` `minus` `semi` `eof` `err`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `','` _ `comma`)
  (lex_rule `'/'` _ `slash`)
  (lex_rule `'?'` _ `query`)
  (lex_rule `'='` _ `equals`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `';'` _ `semi`)
  (lex_rule
    `'\\n'`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule `[a-z]+` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"lists"`)
  (rule
    (start `top`)
    (alt
      _
      ((quantified
          (ref `form`)
          (zero_plus)))
      (node
        `top`
        (spread `1`))
      _))
  (rule
    (name `form`)
    (alt
      _
      ((lit `"*"`)
        (quantified
          (tok `IDENT`)
          (zero_plus))
        (lit `";"`))
      (node
        `star`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"+"`)
        (quantified
          (tok `IDENT`)
          (one_plus))
        (lit `";"`))
      (node
        `plus`
        (pos `2`))
      _)
    (alt
      _
      ((lit `","`)
        (list_req
          `L`
          (plain `IDENT`))
        (lit `";"`))
      (node
        `list`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"/"`)
        (list_req
          `L`
          (sep_items `IDENT` `"/"`))
        (lit `";"`))
      (node
        `sep`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"?"`)
        (list_req
          `L`
          (opt_items_nosep `IDENT`))
        (lit `";"`))
      (node
        `opt`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"="`)
        (quantified
          (group
            _
            ((tok `IDENT`))
            ((skip
                (lit `"-"`))))
          (zero_plus))
        (lit `";"`))
      (node
        `nils`
        (pos `2`))
      _)))
