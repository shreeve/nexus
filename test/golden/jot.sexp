(grammar
  (lang `"jot"`)
  (section `lexer`)
  (tokens `tokens` `ident` `number` `comment` `newline` `kw_def` `kw_return` `kw_loop` `assign` `plus` `bang` `lparen` `rparen` `lbrace` `rbrace` `comma` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `"def"` _ `kw_def`)
  (lex_rule `"return"` _ `kw_return`)
  (lex_rule `'='` _ `assign`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'!'` _ `bang`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'{'` _ `lbrace`)
  (lex_rule `'}'` _ `rbrace`)
  (lex_rule `','` _ `comma`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `[a-z_]+` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (schema
    (kind_decl
      (kinds `file`)
      (roles
        (role rest `stmts` _ _))
      _
      _)
    (kind_decl
      (kinds `def`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `params`
          (type `params`)
          _)
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `params`)
      (roles
        (role
          rest
          `names`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `block`)
      (roles
        (role rest `stmts` _ _))
      _
      _)
    (kind_decl
      (kinds `assign`)
      (roles
        (role
          _
          `target`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `loop`)
      (roles
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `return`)
      (roles
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `name`)
      (roles
        (role
          _
          `id`
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
      (kinds `add`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `force`)
      (roles
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `call`)
      (roles
        (role _ `callee` _ _)
        (role rest `args` _ _))
      _
      _))
  (lsp
    (lsp_line `scope` `file`)
    (lsp_line `scope` `def` `block`)
    (lsp_line `define` `def.name` `function` `outer`)
    (lsp_line `define` `params.names` `variable`)
    (lsp_line `bind` `assign.target` `variable`)
    (lsp_line `use` `IDENT`)
    (lsp_line `builtin` `"print"`)
    (lsp_line `undefined` `warning`)
    (lsp_line `color` `def.name` `function` `declaration`)
    (lsp_line `color` `params.names` `variable.parameter` `declaration`)
    (lsp_line `color` `loop` `start` `keyword`)
    (lsp_line `color` `force` `end` `storage.modifier`)
    (lsp_line `words` `"loop"`))
  (trivia `COMMENT`)
  (repair
    (repair_line `holes` `IDENT`)
    (repair_line `terminator` `NEWLINE`))
  (highlight
    (hl_line `language` `"Jot"`)
    (hl_line `scope-name` `source.jot`)
    (hl_line `extensions` `jot`)
    (hl_line `line-comment` `"#"`)
    (hl_line `indent` `'{' [ \\t]* line-end`)
    (hl_line `dedent` `line-start [ \\t]* '}'`)
    (hl_line `keyword` `line-start [ \\t]* "loop" not before [a-z_]`)
    (hl_line `keyword` `"def"`)
    (hl_line `keyword.control` `"return"`)
    (hl_line `operator` `"=" "+" "!"`)
    (hl_line `punctuation` `"(" ")" "{" "}" ","`)
    (hl_line `constant.numeric` `NUMBER`)
    (hl_line `comment` `COMMENT`)
    (hl_line `invalid` `ERR`))
  (rule
    (start `file`)
    (alt
      _
      ((ref `body`))
      (node
        `file`
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
      ((tok `KW_DEF`)
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
        `def`
        (pos `2`)
        (node
          `params`
          (spread `4`))
        (pos `6`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (lit `"="`)
        (ref `expr`))
      (node
        `assign`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `KW_LOOP`)
        (ref `block`))
      (node
        `loop`
        (pos `2`))
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
      ((ref `expr`)
        (lit `"+"`)
        (ref `atom`))
      (node
        `add`
        (pos `1`)
        (pos `3`))
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
      ((ref `atom`)
        (lit `"!"`))
      (node
        `force`
        (pos `1`))
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
      _)))
