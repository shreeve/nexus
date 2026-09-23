(grammar
  (section `lexer`)
  (tokens `tokens` `integer` `real` `string` `char` `keyword` `ident` `lparen` `rparen` `lbracket` `rbracket` `lbrace` `rbrace` `hash_lbrace` `hash_lparen` `hash_discard` `quote_tok` `syntax_quote_tok` `unquote_splicing_tok` `unquote_tok` `deref_tok` `caret` `eof` `err`)
  (lex_rule `[ \\t\\r\\n,]+` _ `skip`)
  (lex_rule `';' [^\\n]*` _ `skip`)
  (lex_rule `'"' ([^"\\\\\\n] | '\\\\' .)* '"'` _ `string`)
  (lex_rule `'\\\\' 'u{' [0-9a-fA-F]+ '}'` _ `char`)
  (lex_rule `'\\\\' [a-zA-Z][a-zA-Z]*` _ `char`)
  (lex_rule `'\\\\' .` _ `char`)
  (lex_rule `'-'? [0-9]+ '.' [0-9]+ ([eE] ('+'|'-')? [0-9]+)?` _ `real`)
  (lex_rule `'-'? [0-9]+ [eE] ('+'|'-')? [0-9]+` _ `real`)
  (lex_rule `'-'? '0x' [0-9a-fA-F]+` _ `integer`)
  (lex_rule `'-'? '0b' [01]+` _ `integer`)
  (lex_rule `'-'? [0-9]+` _ `integer`)
  (lex_rule `'~@'` _ `unquote_splicing_tok`)
  (lex_rule `'#{'` _ `hash_lbrace`)
  (lex_rule `'#('` _ `hash_lparen`)
  (lex_rule `'#_'` _ `hash_discard`)
  (lex_rule `"'"` _ `quote_tok`)
  (lex_rule `'\`'` _ `syntax_quote_tok`)
  (lex_rule `'~'` _ `unquote_tok`)
  (lex_rule `'@'` _ `deref_tok`)
  (lex_rule `'^'` _ `caret`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'['` _ `lbracket`)
  (lex_rule `']'` _ `rbracket`)
  (lex_rule `'{'` _ `lbrace`)
  (lex_rule `'}'` _ `rbrace`)
  (lex_rule `':' [a-zA-Z_*+!?<>=&$.%/-][a-zA-Z0-9_*+!?<>=&$.%'/-]*` _ `keyword`)
  (lex_rule `[a-zA-Z_*+!?<>=&$.%-][a-zA-Z0-9_*+!?<>=&$.%'/-]*` _ `ident`)
  (lex_rule `'/'` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"nexis"`)
  (op
    (op_map `"~@"` `"unquote_splicing_tok"`)
    (op_map `"#{"` `"hash_lbrace"`)
    (op_map `"#("` `"hash_lparen"`)
    (op_map `"#_"` `"hash_discard"`))
  (manifest
    (conflict `shift` `forms → ε` _ `108` `# a form list extends until its closing token, as Clojure's reader reads it`))
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
      ((ref `form`))
      (pos `1`)
      _))
  (rule
    (name `forms`)
    (alt
      _
      ((ref `forms`)
        (ref `form`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `form`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `form`)
    (alt
      _
      ((ref `atom`))
      _
      _)
    (alt
      _
      ((ref `list_form`))
      _
      _)
    (alt
      _
      ((ref `vector_form`))
      _
      _)
    (alt
      _
      ((ref `map_form`))
      _
      _)
    (alt
      _
      ((ref `set_form`))
      _
      _)
    (alt
      _
      ((ref `quote_form`))
      _
      _)
    (alt
      _
      ((ref `syntax_quote_form`))
      _
      _)
    (alt
      _
      ((ref `unquote_form`))
      _
      _)
    (alt
      _
      ((ref `unquote_splicing_form`))
      _
      _)
    (alt
      _
      ((ref `deref_form`))
      _
      _)
    (alt
      _
      ((ref `anon_fn_form`))
      _
      _)
    (alt
      _
      ((ref `discard_form`))
      _
      _)
    (alt
      _
      ((ref `meta_form`))
      _
      _))
  (rule
    (name `atom`)
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
      _))
  (rule
    (name `list_form`)
    (alt
      _
      ((lit `"("`)
        (ref `forms`)
        (lit `")"`))
      (node
        `list`
        (spread `2`))
      _))
  (rule
    (name `vector_form`)
    (alt
      _
      ((lit `"["`)
        (ref `forms`)
        (lit `"]"`))
      (node
        `vector`
        (spread `2`))
      _))
  (rule
    (name `map_form`)
    (alt
      _
      ((lit `"{"`)
        (ref `forms`)
        (lit `"}"`))
      (node
        `map`
        (spread `2`))
      _))
  (rule
    (name `set_form`)
    (alt
      _
      ((lit `"#{"`)
        (ref `forms`)
        (lit `"}"`))
      (node
        `set`
        (spread `2`))
      _))
  (rule
    (name `quote_form`)
    (alt
      _
      ((lit `"'"`)
        (ref `form`))
      (node
        `quote`
        (pos `2`))
      _))
  (rule
    (name `syntax_quote_form`)
    (alt
      _
      ((lit `"\`"`)
        (ref `form`))
      (node
        `syntax-quote`
        (pos `2`))
      _))
  (rule
    (name `unquote_form`)
    (alt
      _
      ((lit `"~"`)
        (ref `form`))
      (node
        `unquote`
        (pos `2`))
      _))
  (rule
    (name `unquote_splicing_form`)
    (alt
      _
      ((lit `"~@"`)
        (ref `form`))
      (node
        `unquote-splicing`
        (pos `2`))
      _))
  (rule
    (name `deref_form`)
    (alt
      _
      ((lit `"@"`)
        (ref `form`))
      (node
        `deref`
        (pos `2`))
      _))
  (rule
    (name `anon_fn_form`)
    (alt
      _
      ((lit `"#("`)
        (ref `forms`)
        (lit `")"`))
      (node
        `anon-fn`
        (spread `2`))
      _))
  (rule
    (name `discard_form`)
    (alt
      _
      ((lit `"#_"`)
        (ref `form`))
      (node
        `discard`
        (pos `2`))
      _))
  (rule
    (name `meta_form`)
    (alt
      _
      ((lit `"^"`)
        (ref `form`)
        (ref `form`))
      (node
        `with-meta-raw`
        (pos `3`)
        (pos `2`))
      _)))
