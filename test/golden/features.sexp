(grammar
  (lang `"features"`)
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
      ((ref `call`)
        (lit `"="`)
        (ref `expr`))
      `(assign 1 3)`)
    (alt
      _
      ((at_ref `infix`))))
  (rule
    (name `call`)
    (alt
      _
      ((ref `call`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      `(call 1 ...3)`)
    (alt
      _
      ((ref `atom`))))
  (rule
    (name `args`)
    (alt
      _
      ((list_req
          `L`
          (plain `expr`)))
      `(...1)`)
    (alt _ () `()`))
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
      ((tok `STRING_DQ`)))
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      `2`))
  (infix
    `call`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`))))
