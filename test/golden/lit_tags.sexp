(grammar
  (conflicts `0`)
  (rule
    (start `program`)
    (alt
      ((ref `body`))
      `(module ...1)`))
  (rule
    (name `body`)
    (alt
      ((ref `stmt`))
      `(1)`)
    (alt
      ((ref `body`)
        (tok `NEWLINE`)
        (ref `stmt`))
      `(...1 3)`)
    (alt
      ((ref `body`)
        (tok `NEWLINE`))
      `1`))
  (rule
    (name `stmt`)
    (alt
      ((tok `IDENT`)
        (lit `"="`)
        (tok `INTEGER`))
      `(set fixed 1 _ 3)`)
    (alt
      ((tok `IDENT`)
        (lit `"->"`)
        (tok `INTEGER`))
      `(set move 1 _ 3)`)
    (alt
      ((tok `IDENT`)
        (lit `"+="`)
        (tok `INTEGER`))
      `(set += 1 _ 3)`)))
