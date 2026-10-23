(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `number` `string` `comment` `newline` `kw_fn` `kw_let` `kw_use` `kw_return` `assign` `plus` `minus` `star` `lparen` `rparen` `lbrace` `rbrace` `comma` `dot` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'"' [^"\\n]* '"'` _ `string`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `"fn"` _ `kw_fn`)
  (lex_rule `"let"` _ `kw_let`)
  (lex_rule `"use"` _ `kw_use`)
  (lex_rule `"return"` _ `kw_return`)
  (lex_rule `'='` _ `assign`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'{'` _ `lbrace`)
  (lex_rule `'}'` _ `rbrace`)
  (lex_rule `','` _ `comma`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `[a-z_] [a-z_0-9]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (display
    (name_pair `IDENT` `"a name"`)
    (name_pair `NEWLINE` `"end of line"`))
  (errors
    (name_pair `expr` `"an expression"`))
  (messages
    (message
      `after`
      _
      `"expected ',' between arguments, got {got}"`
      (msg_sym `IDENT` _)
      (msg_sym `"("` _)
      (msg_sym `expr` _)
      (msg_sym `IDENT` _)))
  (trivia `COMMENT`)
  (repair
    (repair_line `holes` `IDENT`)
    (repair_line `terminator` `NEWLINE`))
  (highlight
    (hl_line `language` `"Tally"`)
    (hl_line `scope-name` `source.tally`)
    (hl_line `extensions` `tally`)
    (hl_line `line-comment` `"#"`)
    (hl_line `indent` `'{' [ \\t]* line-end`)
    (hl_line `dedent` `line-start [ \\t]* '}'`)
    (hl_line `keyword` `"fn" [ \\t]+ function:([a-z_] [a-z_0-9]*)`)
    (hl_line `keyword` `"fn" "let" "use"`)
    (hl_line `keyword.control` `"return"`)
    (hl_line `operator` `"=" "+" "-" "*"`)
    (hl_line `punctuation` `"(" ")" "{" "}" "," "."`)
    (hl_line `constant.numeric` `NUMBER`)
    (hl_line `string` `STRING`)
    (hl_line `comment` `COMMENT`)
    (hl_line `invalid` `ERR`))
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
      ((ref `line`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`)
        (ref `line`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `line`)
    (alt
      _
      ((ref `stmt`))
      _
      _)
    (alt
      _
      ()
      (null)
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((tok `KW_USE`)
        (tok `IDENT`))
      (node
        `use`
        (pos `2`))
      _)
    (alt
      _
      ((tok `KW_LET`)
        (tok `IDENT`)
        (lit `"="`)
        (ref `expr`))
      (node
        `let`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((tok `KW_FN`)
        (tok `IDENT`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `IDENT`))))
        (lit `")"`)
        (ref `block`))
      (node
        `fn`
        (pos `2`)
        (node
          `params`
          (spread `4`))
        (pos `6`))
      _)
    (alt
      _
      ((tok `KW_RETURN`)
        (ref `expr`))
      (node
        `return`
        (pos `2`))
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `block`)
    (alt
      _
      ((lit `"{"`)
        (ref `body`)
        (lit `"}"`))
      (node
        `block`
        (spread `2`))
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((at_ref `infix`))
      _
      _))
  (rule
    (name `atom`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `name`
        (pos `1`))
      _)
    (alt
      _
      ((tok `NUMBER`))
      (node
        `num`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STRING`))
      (node
        `str`
        (pos `1`))
      _)
    (alt
      _
      ((ref `atom`)
        (lit `"."`)
        (tok `IDENT`))
      (node
        `member`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `atom`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _))
  (infix
    `atom`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`))))
