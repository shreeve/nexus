(grammar
  (lang `"nexis"`)
  (op
    (op_map `"~@"` `"unquote_splicing_tok"`)
    (op_map `"#{"` `"hash_lbrace"`)
    (op_map `"#("` `"hash_lparen"`)
    (op_map `"#_"` `"hash_discard"`))
  (conflicts `114`)
  (rule
    (start `program`)
    (alt
      _
      ((ref `forms`))
      `(program ...1)`))
  (rule
    (start `form`)
    (alt
      _
      ((ref `form`))
      `1`))
  (rule
    (name `forms`)
    (alt
      _
      ((ref `forms`)
        (ref `form`))
      `(...1 2)`)
    (alt
      _
      ((ref `form`))
      `(1)`)
    (alt _ () `()`))
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
      `(int 1)`)
    (alt
      _
      ((tok `REAL`))
      `(real 1)`)
    (alt
      _
      ((tok `STRING`))
      `(string 1)`)
    (alt
      _
      ((tok `CHAR`))
      `(char 1)`)
    (alt
      _
      ((tok `KEYWORD`))
      `(keyword 1)`)
    (alt
      _
      ((tok `IDENT`))
      `(symbol 1)`))
  (rule
    (name `list_form`)
    (alt
      _
      ((lit `"("`)
        (ref `forms`)
        (lit `")"`))
      `(list ...2)`))
  (rule
    (name `vector_form`)
    (alt
      _
      ((lit `"["`)
        (ref `forms`)
        (lit `"]"`))
      `(vector ...2)`))
  (rule
    (name `map_form`)
    (alt
      _
      ((lit `"{"`)
        (ref `forms`)
        (lit `"}"`))
      `(map ...2)`))
  (rule
    (name `set_form`)
    (alt
      _
      ((lit `"#{"`)
        (ref `forms`)
        (lit `"}"`))
      `(set ...2)`))
  (rule
    (name `quote_form`)
    (alt
      _
      ((lit `"'"`)
        (ref `form`))
      `(quote 2)`))
  (rule
    (name `syntax_quote_form`)
    (alt
      _
      ((lit `"\`"`)
        (ref `form`))
      `(syntax-quote 2)`))
  (rule
    (name `unquote_form`)
    (alt
      _
      ((lit `"~"`)
        (ref `form`))
      `(unquote 2)`))
  (rule
    (name `unquote_splicing_form`)
    (alt
      _
      ((lit `"~@"`)
        (ref `form`))
      `(unquote-splicing 2)`))
  (rule
    (name `deref_form`)
    (alt
      _
      ((lit `"@"`)
        (ref `form`))
      `(deref 2)`))
  (rule
    (name `anon_fn_form`)
    (alt
      _
      ((lit `"#("`)
        (ref `forms`)
        (lit `")"`))
      `(anon-fn ...2)`))
  (rule
    (name `discard_form`)
    (alt
      _
      ((lit `"#_"`)
        (ref `form`))
      `(discard 2)`))
  (rule
    (name `meta_form`)
    (alt
      _
      ((lit `"^"`)
        (ref `form`)
        (ref `form`))
      `(with-meta-raw 3 2)`)))
