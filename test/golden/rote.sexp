(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `global` `number` `comment` `newline` `kw_do` `kw_set` `caret` `colon` `eq` `plus` `eof` `err`)
  (lex_rule `';' [^\\n]*` _ `comment`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `"do"` _ `kw_do`)
  (lex_rule `"set"` _ `kw_set`)
  (lex_rule `'^'` _ `caret`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `'='` _ `eq`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'$' [a-z]+` _ `global`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `[a-z]+` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (schema
    (kind_decl
      (kinds `routine`)
      (roles
        (role rest `lines` _ _))
      _
      _)
    (kind_decl
      (kinds `label`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `do`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role
          _
          `routine`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `set`)
      (roles
        (role
          _
          `target`
          (type `global`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `global`)
      (roles
        (role
          _
          `name`
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
      _))
  (lsp
    (lsp_line `scope` `routine` `unordered`)
    (lsp_line `define` `label.name` `function`)
    (lsp_line `use` `IDENT`)
    (lsp_line `import` `do.routine` `file` `"{}.rote"`)
    (lsp_line `qualify` `do.label` `in:routine`)
    (lsp_line `nominal` `GLOBAL` `ns:globals`))
  (trivia `COMMENT`)
  (highlight
    (hl_line `language` `"Rote"`)
    (hl_line `scope-name` `source.rote`)
    (hl_line `extensions` `rote`)
    (hl_line `line-comment` `";"`)
    (hl_line `keyword` `"do" "set"`)
    (hl_line `operator` `"=" "+" "^"`)
    (hl_line `punctuation` `":"`)
    (hl_line `variable.special` `GLOBAL`)
    (hl_line `constant.numeric` `NUMBER`)
    (hl_line `comment` `COMMENT`)
    (hl_line `invalid` `ERR`))
  (rule
    (start `routine`)
    (alt
      _
      ((ref `lines`))
      (node
        `routine`
        (spread `1`))
      _))
  (rule
    (name `lines`)
    (alt
      _
      ((ref `line`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `lines`)
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
      ((tok `IDENT`)
        (lit `":"`))
      (node
        `label`
        (pos `1`))
      _)
    (alt
      _
      ((tok `KW_DO`)
        (tok `IDENT`))
      (node
        `do`
        (pos `2`)
        (null))
      _)
    (alt
      _
      ((tok `KW_DO`)
        (tok `IDENT`)
        (lit `"^"`)
        (tok `IDENT`))
      (node
        `do`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((tok `KW_DO`)
        (lit `"^"`)
        (tok `IDENT`))
      (node
        `do`
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `KW_SET`)
        (ref `global`)
        (lit `"="`)
        (ref `expr`))
      (node
        `set`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ()
      (null)
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
      ((ref `global`))
      _
      _)
    (alt
      _
      ((tok `NUMBER`))
      (node
        `num`
        (pos `1`))
      _))
  (rule
    (name `global`)
    (alt
      _
      ((tok `GLOBAL`))
      (node
        `global`
        (pos `1`))
      _)))
