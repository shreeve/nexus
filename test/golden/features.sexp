(grammar
  (lang `"features"`)
  (conflicts `0`)
  (rule
    (name `name`)
    (alt
      ((tok `IDENT`))))
  (rule
    (start `program`)
    (alt
      ((ref `body`))
      `(module ...1)`))
  (rule
    (start `expr`)
    (alt
      ((ref `expr`))
      `1`))
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
      ((ref `expr`))))
  (rule
    (name `expr`)
    (alt
      ((ref `call`)
        (lit `"="`)
        (ref `expr`))
      `(assign 1 3)`)
    (alt
      ((at_ref `infix`))))
  (rule
    (name `call`)
    (alt
      ((ref `call`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      `(call 1 ...3)`)
    (alt
      ((ref `atom`))))
  (rule
    (name `args`)
    (alt
      ((list_req
          `L`
          (plain `expr`)))
      `(...1)`)
    (alt () `()`))
  (rule
    (name `atom`)
    (alt
      ((ref `name`)))
    (alt
      ((tok `INTEGER`)))
    (alt
      ((tok `STRING_DQ`)))
    (alt
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
