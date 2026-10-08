(grammar
  (section `lexer`)
  (tokens `tokens` `integer` `real` `string` `regex` `char` `keyword` `ident` `lparen` `rparen` `lbracket` `rbracket` `lbrace` `rbrace` `hash_lbrace` `hash_lparen` `hash_discard` `quote_tok` `syntax_quote_tok` `unquote_splicing_tok` `unquote_tok` `deref_tok` `var_quote_tok` `caret` `eof` `err`)
  (section `parser`)
  (lang `"nexis"`)
  (rule
    (start `program`)
    (alt
      _
      ((ref `forms`))
      (node
        `program`
        (spread `1`))
      _))
  (rule
    (start `form`)
    (alt
      _
      ((ref `gap`)
        (ref `datum`)
        (ref `gap`))
      (pos `2`)
      _))
  (rule
    (name `forms`)
    (alt
      _
      ((ref `forms`)
        (ref `datum`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `forms`)
        (ref `discard`))
      (pos `1`)
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `gap`)
    (alt
      _
      ((ref `gap`)
        (ref `discard`))
      (null)
      _)
    (alt
      _
      ()
      (null)
      _))
  (rule
    (name `discard`)
    (alt
      _
      ((tok `HASH_DISCARD`)
        (ref `gap`)
        (ref `datum`))
      (null)
      _))
  (rule
    (name `datum`)
    (alt
      _
      ((tok `INTEGER`))
      (node
        `int`
        (pos `1`))
      _)
    (alt
      _
      ((tok `REAL`))
      (node
        `real`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STRING`))
      (node
        `string`
        (pos `1`))
      _)
    (alt
      _
      ((tok `REGEX`))
      (node
        `regex`
        (pos `1`))
      _)
    (alt
      _
      ((tok `CHAR`))
      (node
        `char`
        (pos `1`))
      _)
    (alt
      _
      ((tok `KEYWORD`))
      (node
        `keyword`
        (pos `1`))
      _)
    (alt
      _
      ((tok `IDENT`))
      (node
        `symbol`
        (pos `1`))
      _)
    (alt
      _
      ((tok `LPAREN`)
        (ref `forms`)
        (tok `RPAREN`))
      (node
        `list`
        (pos `1`)
        (spread `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `LBRACKET`)
        (ref `forms`)
        (tok `RBRACKET`))
      (node
        `vector`
        (pos `1`)
        (spread `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `LBRACE`)
        (ref `forms`)
        (tok `RBRACE`))
      (node
        `map`
        (pos `1`)
        (spread `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `HASH_LBRACE`)
        (ref `forms`)
        (tok `RBRACE`))
      (node
        `set`
        (pos `1`)
        (spread `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `HASH_LPAREN`)
        (ref `forms`)
        (tok `RPAREN`))
      (node
        `anon-fn`
        (pos `1`)
        (spread `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `QUOTE_TOK`)
        (ref `gap`)
        (ref `datum`))
      (node
        `quote`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `SYNTAX_QUOTE_TOK`)
        (ref `gap`)
        (ref `datum`))
      (node
        `syntax-quote`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `UNQUOTE_TOK`)
        (ref `gap`)
        (ref `datum`))
      (node
        `unquote`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `UNQUOTE_SPLICING_TOK`)
        (ref `gap`)
        (ref `datum`))
      (node
        `unquote-splicing`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `DEREF_TOK`)
        (ref `gap`)
        (ref `datum`))
      (node
        `deref`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `VAR_QUOTE_TOK`)
        (ref `gap`)
        (ref `datum`))
      (node
        `var-quote`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `CARET`)
        (ref `gap`)
        (ref `datum`)
        (ref `gap`)
        (ref `datum`))
      (node
        `with-meta-raw`
        (pos `1`)
        (pos `5`)
        (pos `3`))
      _)))
