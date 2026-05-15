(grammar
  (lang `"basic"`)
  (conflicts `0`)
  (rule
    (name `name`)
    (alt
      _
      ((tok `IDENT`))))
  (rule
    (start `program`)
    (alt
      _
      ((ref `body`))
      `(module ...1)`))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      `1`))
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
      ((ref `expr`))))
  (rule
    (name `expr`)
    (alt
      _
      ((at_ref `infix`))))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"-"`)
        (ref `unary`))
      `(neg 2)`)
    (alt
      _
      ((ref `atom`))))
  (rule
    (name `atom`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((tok `INTEGER`)))
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      `2`))
  (infix
    `unary`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`))
    (level
      (infix_op `"**"` `right`))))
