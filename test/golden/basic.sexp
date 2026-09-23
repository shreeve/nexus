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
      ((at_ref `infix`))))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"-"`)
        (ref `unary`))
      (node
        `neg`
        (pos `2`)))
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
      (pos `2`)))
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
