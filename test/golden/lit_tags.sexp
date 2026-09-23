(grammar
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
      ((tok `IDENT`)
        (lit `"="`)
        (tok `INTEGER`))
      (node
        `set`
        (tag `fixed`)
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (lit `"->"`)
        (tok `INTEGER`))
      (node
        `set`
        (tag `move`)
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (lit `"+="`)
        (tok `INTEGER`))
      (node
        `set`
        (tag `+=`)
        (pos `1`)
        (null)
        (pos `3`))
      _)))
