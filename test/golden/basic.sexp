(grammar
  (lang "basic")
  (conflicts 0)
  (rule
    (name name)
    (alt
      ((tok IDENT))))
  (rule
    (start program)
    (alt
      ((ref body))
      (module ...1)))
  (rule
    (start expr)
    (alt
      ((ref expr))
      1))
  (rule
    (name body)
    (alt
      ((ref stmt))
      (1))
    (alt
      ((ref body)
        (tok NEWLINE)
        (ref stmt))
      (...1 3))
    (alt
      ((ref body)
        (tok NEWLINE))
      1))
  (rule
    (name stmt)
    (alt
      ((ref expr))))
  (rule
    (name expr)
    (alt
      ((at_ref infix))))
  (rule
    (name unary)
    (alt
      ((lit "-")
        (ref unary))
      (neg 2))
    (alt
      ((ref atom))))
  (rule
    (name atom)
    (alt
      ((ref name)))
    (alt
      ((tok INTEGER)))
    (alt
      ((lit "(")
        (ref expr)
        (lit ")"))
      2))
  (infix
    unary
    (level
      (infix_op "+" left)
      (infix_op "-" left))
    (level
      (infix_op "*" left)
      (infix_op "/" left))
    (level
      (infix_op "**" right))))
