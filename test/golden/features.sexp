(grammar
  (lang `"features"`)
  (conflicts `0`)
  (rule
    (name `name`)
    (alt
      _
      ((tok `IDENT`))
      _
      _))
  (rule
    (start `program`)
    (alt
      _
      ((ref `body`))
      (node
        `module`
        (spread `1`))
      _))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)
      _))
  (rule
    (name `body`)
    (alt
      _
      ((ref `stmt`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`)
        (ref `stmt`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `body`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((ref `expr`))
      _
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((at_ref `infix`))
      _
      _))
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
        (spread `3`))
      _)
    (alt
      _
      ((ref `atom`))
      _
      _))
  (rule
    (name `args`)
    (alt
      _
      ((list_req
          `L`
          (plain `expr`)))
      (list
        (spread `1`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `atom`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `STRING_DQ`))
      _
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _))
  (infix
    `call`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`))))
