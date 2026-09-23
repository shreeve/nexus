(grammar
  (lang `"nexis"`)
  (op
    (op_map `"~@"` `"unquote_splicing_tok"`)
    (op_map `"#{"` `"hash_lbrace"`)
    (op_map `"#("` `"hash_lparen"`)
    (op_map `"#_"` `"hash_discard"`))
  (conflicts `108`)
  (rule
    (start `program`)
    (alt
      _
      ((ref `forms`))
      (node
        `program`
        (spread `1`))))
  (rule
    (start `form`)
    (alt
      _
      ((ref `form`))
      (pos `1`)))
  (rule
    (name `forms`)
    (alt
      _
      ((ref `forms`)
        (ref `form`))
      (list
        (spread `1`)
        (pos `2`)))
    (alt
      _
      ((ref `form`))
      (list
        (pos `1`)))
    (alt
      _
      ()
      (list)))
  (rule
    (name `form`)
    (alt
      _
      ((ref `atom`)))
    (alt
      _
      ((ref `list_form`)))
    (alt
      _
      ((ref `vector_form`)))
    (alt
      _
      ((ref `map_form`)))
    (alt
      _
      ((ref `set_form`)))
    (alt
      _
      ((ref `quote_form`)))
    (alt
      _
      ((ref `syntax_quote_form`)))
    (alt
      _
      ((ref `unquote_form`)))
    (alt
      _
      ((ref `unquote_splicing_form`)))
    (alt
      _
      ((ref `deref_form`)))
    (alt
      _
      ((ref `anon_fn_form`)))
    (alt
      _
      ((ref `discard_form`)))
    (alt
      _
      ((ref `meta_form`))))
  (rule
    (name `atom`)
    (alt
      _
      ((tok `INTEGER`))
      (node
        `int`
        (pos `1`)))
    (alt
      _
      ((tok `REAL`))
      (node
        `real`
        (pos `1`)))
    (alt
      _
      ((tok `STRING`))
      (node
        `string`
        (pos `1`)))
    (alt
      _
      ((tok `CHAR`))
      (node
        `char`
        (pos `1`)))
    (alt
      _
      ((tok `KEYWORD`))
      (node
        `keyword`
        (pos `1`)))
    (alt
      _
      ((tok `IDENT`))
      (node
        `symbol`
        (pos `1`))))
  (rule
    (name `list_form`)
    (alt
      _
      ((lit `"("`)
        (ref `forms`)
        (lit `")"`))
      (node
        `list`
        (spread `2`))))
  (rule
    (name `vector_form`)
    (alt
      _
      ((lit `"["`)
        (ref `forms`)
        (lit `"]"`))
      (node
        `vector`
        (spread `2`))))
  (rule
    (name `map_form`)
    (alt
      _
      ((lit `"{"`)
        (ref `forms`)
        (lit `"}"`))
      (node
        `map`
        (spread `2`))))
  (rule
    (name `set_form`)
    (alt
      _
      ((lit `"#{"`)
        (ref `forms`)
        (lit `"}"`))
      (node
        `set`
        (spread `2`))))
  (rule
    (name `quote_form`)
    (alt
      _
      ((lit `"'"`)
        (ref `form`))
      (node
        `quote`
        (pos `2`))))
  (rule
    (name `syntax_quote_form`)
    (alt
      _
      ((lit `"\`"`)
        (ref `form`))
      (node
        `syntax-quote`
        (pos `2`))))
  (rule
    (name `unquote_form`)
    (alt
      _
      ((lit `"~"`)
        (ref `form`))
      (node
        `unquote`
        (pos `2`))))
  (rule
    (name `unquote_splicing_form`)
    (alt
      _
      ((lit `"~@"`)
        (ref `form`))
      (node
        `unquote-splicing`
        (pos `2`))))
  (rule
    (name `deref_form`)
    (alt
      _
      ((lit `"@"`)
        (ref `form`))
      (node
        `deref`
        (pos `2`))))
  (rule
    (name `anon_fn_form`)
    (alt
      _
      ((lit `"#("`)
        (ref `forms`)
        (lit `")"`))
      (node
        `anon-fn`
        (spread `2`))))
  (rule
    (name `discard_form`)
    (alt
      _
      ((lit `"#_"`)
        (ref `form`))
      (node
        `discard`
        (pos `2`))))
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
        (pos `2`)))))
