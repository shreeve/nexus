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
      (node
        `module`
        (spread `1`))))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)))
  (rule
    (name `body`)
    (alt
      _
      ((ref `stmt`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`)
        (ref `stmt`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`))
      (pos `1`)))
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
      (node
        `assign`
        (pos `1`)
        (pos `3`)))
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
      (node
        `call`
        (pos `1`)
        (spread `3`)))
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
      (list
        (spread `1`)))
    (alt
      _
      ()
      (list)))
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
      (pos `2`)))
  (infix
    `call`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`))))
