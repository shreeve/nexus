(grammar
  (section `lexer`)
  (state
    `state`
    (assign `cut` `0`))
  (tokens `tokens` `name` `number` `string` `comment` `newline` `eq` `colon` `comma` `minus` `lparen` `rparen` `eof` `err`)
  (longtokens)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule
    `'"' [^"\\n]* '"'`
    (guards
      `@`
      (guard _ `cut` `==` `0`))
    `string`)
  (lex_rule
    `'"' [^"|\\n]*`
    (guards
      `@`
      (guard _ `cut` `==` `1`))
    `string`)
  (lex_rule `'='` _ `eq`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `','` _ `comma`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `[a-z]+` _ `name`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"long_tokens"`)
  (schema
    (kind_decl
      (kinds `program`)
      (roles
        (role rest `stmts` _ _))
      _
      _)
    (kind_decl
      (kinds `set`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      (sides `eq`)
      _)
    (kind_decl
      (kinds `call`)
      (roles
        (role
          _
          `callee`
          (type `leaf`)
          _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `note`)
      (roles)
      (sides `text`)
      _)
    (kind_decl
      (kinds `neg`)
      (roles
        (role
          _
          `value`
          (type `str`)
          _))
      _
      _)
    (kind_decl
      (kinds `str`)
      (roles
        (role
          _
          `value`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `num`)
      (roles
        (role
          _
          `value`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `ref`)
      (roles
        (role
          _
          `id`
          (type `leaf`)
          _))
      _
      _))
  (keywords
    (kw_group `kw` `let`))
  (as
    `NAME`
    _
    (as_entry _ `kw` _))
  (trivia `COMMENT`)
  (repair
    (repair_line `holes` `NAME`)
    (repair_line `terminator` `NEWLINE`))
  (rule
    (start `program`)
    (alt
      _
      ((ref `body`))
      (node
        `program`
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
      ((tok `LET`)
        (label
          `name`
          (tok `NAME`))
        (label
          `eq`
          (lit `"="`))
        (label
          `value`
          (ref `expr`)))
      (node `set`)
      _)
    (alt
      _
      ((label
          `name`
          (tok `NAME`))
        (label
          `eq`
          (lit `"="`))
        (label
          `value`
          (ref `expr`)))
      (node `set`)
      _)
    (alt
      _
      ((label
          `callee`
          (tok `NAME`))
        (lit `"("`)
        (group
          opt
          ((label
              `args`
              (list_req
                `L`
                (plain `expr`)))))
        (lit `")"`))
      (node `call`)
      _)
    (alt
      _
      ((lit `":"`)
        (label
          `text`
          (tok `STRING`)))
      (node `note`)
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((tok `STRING`))
      (node
        `str`
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
      ((tok `NAME`))
      (node
        `ref`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-"`)
        (tok `STRING`))
      (node
        `neg`
        (named
          `value`
          (node
            `str`
            (pos `2`))))
      _)))
