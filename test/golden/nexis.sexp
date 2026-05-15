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
      ((ref `forms`))
      `(program ...1)`))
  (rule
    (start `form`)
    (alt
      ((ref `form`))
      `1`))
  (rule
    (name `forms`)
    (alt
      ((ref `forms`)
        (ref `form`))
      `(...1 2)`)
    (alt
      ((ref `form`))
      `(1)`)
    (alt () `()`))
  (rule
    (name `form`)
    (alt
      ((ref `atom`)))
    (alt
      ((ref `list_form`)))
    (alt
      ((ref `vector_form`)))
    (alt
      ((ref `map_form`)))
    (alt
      ((ref `set_form`)))
    (alt
      ((ref `quote_form`)))
    (alt
      ((ref `syntax_quote_form`)))
    (alt
      ((ref `unquote_form`)))
    (alt
      ((ref `unquote_splicing_form`)))
    (alt
      ((ref `deref_form`)))
    (alt
      ((ref `anon_fn_form`)))
    (alt
      ((ref `discard_form`)))
    (alt
      ((ref `meta_form`))))
  (rule
    (name `atom`)
    (alt
      ((tok `INTEGER`))
      `(int 1)`)
    (alt
      ((tok `REAL`))
      `(real 1)`)
    (alt
      ((tok `STRING`))
      `(string 1)`)
    (alt
      ((tok `CHAR`))
      `(char 1)`)
    (alt
      ((tok `KEYWORD`))
      `(keyword 1)`)
    (alt
      ((tok `IDENT`))
      `(symbol 1)`))
  (rule
    (name `list_form`)
    (alt
      ((lit `"("`)
        (ref `forms`)
        (lit `")"`))
      `(list ...2)`))
  (rule
    (name `vector_form`)
    (alt
      ((lit `"["`)
        (ref `forms`)
        (lit `"]"`))
      `(vector ...2)`))
  (rule
    (name `map_form`)
    (alt
      ((lit `"{"`)
        (ref `forms`)
        (lit `"}"`))
      `(map ...2)`))
  (rule
    (name `set_form`)
    (alt
      ((lit `"#{"`)
        (ref `forms`)
        (lit `"}"`))
      `(set ...2)`))
  (rule
    (name `quote_form`)
    (alt
      ((lit `"'"`)
        (ref `form`))
      `(quote 2)`))
  (rule
    (name `syntax_quote_form`)
    (alt
      ((lit `"\`"`)
        (ref `form`))
      `(syntax-quote 2)`))
  (rule
    (name `unquote_form`)
    (alt
      ((lit `"~"`)
        (ref `form`))
      `(unquote 2)`))
  (rule
    (name `unquote_splicing_form`)
    (alt
      ((lit `"~@"`)
        (ref `form`))
      `(unquote-splicing 2)`))
  (rule
    (name `deref_form`)
    (alt
      ((lit `"@"`)
        (ref `form`))
      `(deref 2)`))
  (rule
    (name `anon_fn_form`)
    (alt
      ((lit `"#("`)
        (ref `forms`)
        (lit `")"`))
      `(anon-fn ...2)`))
  (rule
    (name `discard_form`)
    (alt
      ((lit `"#_"`)
        (ref `form`))
      `(discard 2)`))
  (rule
    (name `meta_form`)
    (alt
      ((lit `"^"`)
        (ref `form`)
        (ref `form`))
      `(with-meta-raw 3 2)`)))
