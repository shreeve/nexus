(grammar
  (conflicts `0`)
  (rule
    (start `program`)
    (alt
      _
      ((ref `body`))
      `(module ...1)`))
  (rule
    (name `body`)
    (alt
      _
      ((ref `stmt`))
      `(1)`)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`)
        (ref `stmt`))
      `(...1 3)`)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`))
      `1`))
  (rule
    (name `stmt`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"="`)
        (tok `INTEGER`))
      `(set fixed 1 _ 3)`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"->"`)
        (tok `INTEGER`))
      `(set move 1 _ 3)`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"+="`)
        (tok `INTEGER`))
      `(set += 1 _ 3)`)))
