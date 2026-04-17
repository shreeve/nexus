(grammar
  (conflicts 19)
  (as
    ident
    (as_strict keyword))
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
      ((ref use)))
    (alt
      ((ref decl)))
    (alt
      ((ref zig)))
    (alt
      ((ref extvar)))
    (alt
      ((lit ":")
        (ref name)
        (ref stmt))
      (labeled 2 3))
    (alt
      ((ref expr))))
  (rule
    (name extvar)
    (alt
      ((tok EXTERN)
        (tok CONST)
        (ref name)
        (lit ":")
        (ref type))
      (extern_const 3 5))
    (alt
      ((tok EXTERN)
        (ref name)
        (lit ":")
        (ref type))
      (extern_var 2 4)))
  (rule
    (name zig)
    (alt
      ((tok ZIG)
        (tok STRING_SQ))
      (zig 2))
    (alt
      ((tok ZIG)
        (tok STRING_DQ))
      (zig 2)))
  (rule
    (name decl)
    (alt
      ((ref defn)))
    (alt
      ((tok PUB)
        (ref decl))
      (pub 2))
    (alt
      ((tok EXTERN)
        (ref decl))
      (extern 2))
    (alt
      ((tok EXPORT)
        (ref decl))
      (export 2))
    (alt
      ((tok PACKED)
        (ref decl))
      (packed 2))
    (alt
      ((tok CALLCONV)
        (ref name)
        (ref decl))
      (callconv 2 3)))
  (rule
    (name defn)
    (alt
      ((ref fun)))
    (alt
      ((ref sub)))
    (alt
      ((ref enum)))
    (alt
      ((ref struct)))
    (alt
      ((ref errors)))
    (alt
      ((ref typedef)))
    (alt
      ((ref test)))
    (alt
      ((ref opaq))))
  (rule
    (name block)
    (alt
      ((tok INDENT)
        (ref body)
        (tok OUTDENT))
      (block ...2))
    (alt
      ((tok INDENT)
        (tok OUTDENT))
      (block)))
  (rule
    (name fun)
    (alt
      ((tok FUN)
        (ref name)
        (ref params)
        (ref returns)
        (ref block))
      (fun 2 3 4 5))
    (alt
      ((tok FUN)
        (ref name)
        (ref params)
        (ref block))
      (fun 2 3 _ 4))
    (alt
      ((tok FUN)
        (ref name)
        (ref returns)
        (ref block))
      (fun 2 _ 3 4))
    (alt
      ((tok FUN)
        (ref name)
        (ref block))
      (fun 2 _ _ 3)))
  (rule
    (name sub)
    (alt
      ((tok SUB)
        (ref name)
        (ref params)
        (ref block))
      (sub 2 3 _ 4))
    (alt
      ((tok SUB)
        (ref name)
        (ref block))
      (sub 2 _ _ 3)))
  (rule
    (name use)
    (alt
      ((tok USE)
        (ref name))
      (use 2)))
  (rule
    (name typedef)
    (alt
      ((tok TYPE)
        (ref name)
        (lit "=")
        (ref type))
      (type 2 4)))
  (rule
    (name test)
    (alt
      ((tok TEST)
        (tok STRING_DQ)
        (ref block))
      (test 2 3)))
  (rule
    (name opaq)
    (alt
      ((tok OPAQUE)
        (ref name))
      (opaque 2)))
  (rule
    (name enum)
    (alt
      ((tok ENUM)
        (ref name)
        (tok INDENT)
        (ref members)
        (tok OUTDENT))
      (enum 2 ...4)))
  (rule
    (name errors)
    (alt
      ((tok ERROR)
        (ref name)
        (tok INDENT)
        (ref members)
        (tok OUTDENT))
      (errors 2 ...4)))
  (rule
    (name struct)
    (alt
      ((tok STRUCT)
        (ref name)
        (tok INDENT)
        (ref members)
        (tok OUTDENT))
      (struct 2 ...4)))
  (rule
    (name members)
    (alt
      ((ref member))
      (1))
    (alt
      ((ref members)
        (tok NEWLINE)
        (ref member))
      (...1 3))
    (alt
      ((ref members)
        (tok NEWLINE))
      1))
  (rule
    (name member)
    (alt
      ((ref field)))
    (alt
      ((ref name)
        (lit "=")
        (ref expr))
      (valued 1 3))
    (alt
      ((ref fun)))
    (alt
      ((ref sub))))
  (rule
    (name field)
    (alt
      ((tok COMPTIME)
        (ref name)
        (lit ":")
        (ref type))
      (comptime_param 2 4))
    (alt
      ((ref name))
      1)
    (alt
      ((ref name)
        (lit ":")
        (ref type))
      (: 1 3))
    (alt
      ((ref name)
        (lit ":")
        (ref type)
        (tok ALIGN)
        (ref atom))
      (aligned 1 3 5))
    (alt
      ((ref name)
        (lit ":")
        (ref type)
        (lit "=")
        (ref expr))
      (default 1 3 5)))
  (rule
    (name params)
    (alt
      ((list_req
          L
          (plain field)))
      (...1)))
  (rule
    (name returns)
    (alt
      ((lit "->")
        (ref type))
      2))
  (rule
    (name type)
    (alt
      ((ref name)))
    (alt
      ((lit "!")
        (ref type))
      (error_union 2))
    (alt
      ((lit "?")
        (ref type))
      (? 2))
    (alt
      ((lit "*")
        (ref type))
      (ptr 2))
    (alt
      ((lit "*")
        (tok CONST)
        (ref type))
      (const_ptr 3))
    (alt
      ((lit "*")
        (tok VOLATILE)
        (ref type))
      (volatile_ptr 3))
    (alt
      ((lit "[")
        (lit "]")
        (ref type))
      (slice 3))
    (alt
      ((lit "[")
        (lit ":")
        (ref atom)
        (lit "]")
        (ref type))
      (sentinel_slice 3 5))
    (alt
      ((lit "[")
        (tok INTEGER)
        (lit "]")
        (ref type))
      (array_type 2 4))
    (alt
      ((lit "[")
        (lit "*")
        (lit "]")
        (ref type))
      (many_ptr 4))
    (alt
      ((lit "[")
        (lit "*")
        (lit ":")
        (ref atom)
        (lit "]")
        (ref type))
      (sentinel_ptr 4 6))
    (alt
      ((tok FN)
        (lit "(")
        (list_req
          L
          (plain type))
        (lit ")")
        (ref type))
      (fn_type 3 5))
    (alt
      ((tok FN)
        (lit "(")
        (lit ")")
        (ref type))
      (fn_type _ 4)))
  (rule
    (name expr)
    (alt
      ((ref if)))
    (alt
      ((ref while)))
    (alt
      ((ref for)))
    (alt
      ((ref match)))
    (alt
      ((ref postif)))
    (alt
      ((ref coalesce)))
    (alt
      ((ref catch)))
    (alt
      ((ref return)))
    (alt
      ((ref break)))
    (alt
      ((ref continue)))
    (alt
      ((ref defer)))
    (alt
      ((ref errdefer)))
    (alt
      ((ref comptime)))
    (alt
      ((ref inline)))
    (alt
      ((ref assign)))
    (alt
      ((ref const)))
    (alt
      ((at_ref infix))))
  (rule
    (name cond)
    (alt
      ((ref expr)))
    (alt
      ((ref expr)
        (tok AS)
        (ref name))
      (as 1 3))
    (alt
      ((ref expr)
        (tok BAR_CAPTURE)
        (ref name)
        (tok BAR_CAPTURE))
      (as 1 3)))
  (rule
    (name if)
    (alt
      ((tok IF)
        (ref cond)
        (ref block)
        (tok ELSE)
        (tok AS)
        (ref name)
        (ref block))
      (if 2 3 6 7))
    (alt
      ((tok IF)
        (ref cond)
        (ref block)
        (tok ELSE)
        (tok AS)
        (ref name)
        (ref if))
      (if 2 3 6 7))
    (alt
      ((tok IF)
        (ref cond)
        (ref block)
        (tok ELSE)
        (ref if))
      (if 2 3 5))
    (alt
      ((tok IF)
        (ref cond)
        (ref block)
        (tok ELSE)
        (ref block))
      (if 2 3 5))
    (alt
      ((tok IF)
        (ref cond)
        (ref block))
      (if 2 3)))
  (rule
    (name while)
    (alt
      ((tok WHILE)
        (ref cond)
        (ref block)
        (tok ELSE)
        (ref block))
      (while 2 _ 3 else:5))
    (alt
      ((tok WHILE)
        (ref cond)
        (lit ":")
        (ref expr)
        (ref block)
        (tok ELSE)
        (ref block))
      (while 2 4 5 else:7))
    (alt
      ((tok WHILE)
        (ref cond)
        (ref block))
      (while 2 _ 3))
    (alt
      ((tok WHILE)
        (ref cond)
        (lit ":")
        (ref expr)
        (ref block))
      (while 2 4 5)))
  (rule
    (name for)
    (alt
      ((tok FOR)
        (lit "*")
        (ref name)
        (tok IN)
        (ref expr)
        (ref block)
        (tok ELSE)
        (ref block))
      (for_ptr 3 _ 5 6 else:8))
    (alt
      ((tok FOR)
        (lit "*")
        (ref name)
        (lit ",")
        (ref name)
        (tok IN)
        (ref expr)
        (ref block)
        (tok ELSE)
        (ref block))
      (for_ptr 3 5 7 8 else:10))
    (alt
      ((tok FOR)
        (ref name)
        (tok IN)
        (ref expr)
        (ref block)
        (tok ELSE)
        (ref block))
      (for 2 _ 4 5 else:7))
    (alt
      ((tok FOR)
        (ref name)
        (lit ",")
        (ref name)
        (tok IN)
        (ref expr)
        (ref block)
        (tok ELSE)
        (ref block))
      (for 2 4 6 7 else:9))
    (alt
      ((tok FOR)
        (lit "*")
        (ref name)
        (tok IN)
        (ref expr)
        (ref block))
      (for_ptr 3 _ 5 6))
    (alt
      ((tok FOR)
        (lit "*")
        (ref name)
        (lit ",")
        (ref name)
        (tok IN)
        (ref expr)
        (ref block))
      (for_ptr 3 5 7 8))
    (alt
      ((tok FOR)
        (ref name)
        (tok IN)
        (ref expr)
        (ref block))
      (for 2 _ 4 5))
    (alt
      ((tok FOR)
        (ref name)
        (lit ",")
        (ref name)
        (tok IN)
        (ref expr)
        (ref block))
      (for 2 4 6 7)))
  (rule
    (name match)
    (alt
      ((tok MATCH)
        (ref expr)
        (tok INDENT)
        (ref arms)
        (tok OUTDENT))
      (match 2 ...4)))
  (rule
    (name arms)
    (alt
      ((ref arm))
      (1))
    (alt
      ((ref arms)
        (tok NEWLINE)
        (ref arm))
      (...1 3))
    (alt
      ((ref arms)
        (tok NEWLINE))
      1))
  (rule
    (name patatom)
    (alt
      ((ref atom)))
    (alt
      ((lit ".")
        (ref name))
      (enum_pattern 2)))
  (rule
    (name pattern)
    (alt
      ((ref patatom)))
    (alt
      ((ref patatom)
        (lit "..")
        (ref patatom))
      (range_pattern 1 3)))
  (rule
    (name arm)
    (alt
      ((ref pattern)
        (tok AS)
        (ref name)
        (lit "=>")
        (ref expr))
      (arm 1 3 5))
    (alt
      ((ref pattern)
        (tok AS)
        (ref name)
        (ref block))
      (arm 1 3 4))
    (alt
      ((ref pattern)
        (lit "=>")
        (ref expr))
      (arm 1 _ 3))
    (alt
      ((ref pattern)
        (ref block))
      (arm 1 _ 2)))
  (rule
    (name postif)
    (alt
      ((at_ref infix)
        (tok IF)
        (ref expr)
        (tok ELSE)
        (ref expr))
      (ternary 3 1 5))
    (alt
      ((at_ref infix)
        (tok IF)
        (ref expr))
      (if 3 1))
    (alt
      ((at_ref infix)
        (tok TERNARY_IF)
        (ref expr)
        (tok ELSE)
        (ref expr))
      (ternary 3 1 5)))
  (rule
    (name coalesce)
    (alt
      ((at_ref infix)
        (lit "??")
        (ref expr))
      (?? 1 3)))
  (rule
    (name catch)
    (alt
      ((at_ref infix)
        (tok CATCH)
        (tok AS)
        (ref name)
        (ref expr))
      (catch 1 4 5))
    (alt
      ((at_ref infix)
        (tok CATCH)
        (ref expr))
      (catch 1 3)))
  (rule
    (name return)
    (alt
      ((tok RETURN)
        (ref expr)
        (tok POST_IF)
        (ref expr))
      (return value:2 if:4))
    (alt
      ((tok RETURN)
        (tok POST_IF)
        (ref expr))
      (return value:_ if:3))
    (alt
      ((tok RETURN)
        (ref expr))
      (return value:2))
    (alt
      ((tok RETURN))
      (return)))
  (rule
    (name break)
    (alt
      ((tok BREAK)
        (lit ":")
        (ref name)
        (tok POST_IF)
        (ref expr))
      (break value:_ to:3 if:5))
    (alt
      ((tok BREAK)
        (lit ":")
        (ref name)
        (ref expr))
      (break value:4 to:3))
    (alt
      ((tok BREAK)
        (lit ":")
        (ref name))
      (break value:_ to:3))
    (alt
      ((tok BREAK)
        (tok POST_IF)
        (ref expr))
      (break value:_ to:_ if:3))
    (alt
      ((tok BREAK)
        (ref expr))
      (break value:2))
    (alt
      ((tok BREAK))
      (break)))
  (rule
    (name continue)
    (alt
      ((tok CONTINUE)
        (lit ":")
        (ref name)
        (tok POST_IF)
        (ref expr))
      (continue to:3 if:5))
    (alt
      ((tok CONTINUE)
        (lit ":")
        (ref name))
      (continue to:3))
    (alt
      ((tok CONTINUE)
        (tok POST_IF)
        (ref expr))
      (continue to:_ if:3))
    (alt
      ((tok CONTINUE))
      (continue)))
  (rule
    (name defer)
    (alt
      ((tok DEFER)
        (ref block))
      (defer 2))
    (alt
      ((tok DEFER)
        (ref expr))
      (defer 2)))
  (rule
    (name errdefer)
    (alt
      ((tok ERRDEFER)
        (ref block))
      (errdefer 2))
    (alt
      ((tok ERRDEFER)
        (ref expr))
      (errdefer 2)))
  (rule
    (name comptime)
    (alt
      ((tok COMPTIME)
        (ref expr))
      (comptime 2)))
  (rule
    (name inline)
    (alt
      ((tok INLINE)
        (ref expr))
      (inline 2)))
  (rule
    (name assign)
    (alt
      ((ref call)
        (lit ":")
        (ref type)
        (lit "=")
        (ref expr))
      (typed_assign 1 3 5))
    (alt
      ((ref call)
        (lit "=")
        (ref expr))
      ( = 1 3))
    (alt
      ((ref call)
        (lit "+=")
        (ref expr))
      (+= 1 3))
    (alt
      ((ref call)
        (lit "-=")
        (ref expr))
      (-= 1 3))
    (alt
      ((ref call)
        (lit "*=")
        (ref expr))
      (*= 1 3))
    (alt
      ((ref call)
        (lit "/=")
        (ref expr))
      (/= 1 3)))
  (rule
    (name const)
    (alt
      ((ref call)
        (lit ":")
        (ref type)
        (lit "=!")
        (ref expr))
      (typed_const 1 3 5))
    (alt
      ((ref call)
        (lit "=!")
        (ref expr))
      (const 1 3)))
  (rule
    (name unary)
    (alt
      ((lit "!")
        (ref unary))
      (not 2))
    (alt
      ((tok MINUS_PREFIX)
        (ref unary))
      (neg 2))
    (alt
      ((tok TRY)
        (ref unary))
      (try 2))
    (alt
      ((lit "&")
        (ref unary))
      (addr_of 2))
    (alt
      ((lit "~")
        (ref unary))
      (bit_not 2))
    (alt
      ((ref call))))
  (rule
    (name call)
    (alt
      ((ref call)
        (lit ".")
        (lit "*"))
      (deref 1))
    (alt
      ((ref call)
        (lit ".")
        (ref name))
      (. 1 3))
    (alt
      ((ref call)
        (lit "[")
        (ref expr)
        (lit "]"))
      (index 1 3))
    (alt
      ((ref call)
        (list_req
          L
          (plain arg)))
      (call 1 ...2))
    (alt
      ((ref call)
        (lit "(")
        (ref args)
        (lit ")"))
      (call 1 ...3))
    (alt
      ((ref atom))))
  (rule
    (name args)
    (alt
      ((list_req
          L
          (plain expr)))
      (...1))
    (alt () ()))
  (rule
    (name arg)
    (alt
      ((ref term)
        (tok TERNARY_IF)
        (ref expr)
        (tok ELSE)
        (ref arg))
      (ternary 3 1 5))
    (alt
      ((ref term))))
  (rule
    (name term)
    (alt
      ((tok MINUS_PREFIX)
        (ref term))
      (neg 2))
    (alt
      ((lit "!")
        (ref term))
      (not 2))
    (alt
      ((ref atom))))
  (rule
    (name atom)
    (alt
      ((ref name)))
    (alt
      ((tok INTEGER)))
    (alt
      ((tok REAL)))
    (alt
      ((tok STRING_SQ)))
    (alt
      ((tok STRING_DQ)))
    (alt
      ((tok TRUE)))
    (alt
      ((tok FALSE)))
    (alt
      ((tok NULL))
      (null))
    (alt
      ((tok UNREACHABLE))
      (unreachable))
    (alt
      ((tok UNDEFINED))
      (undefined))
    (alt
      ((lit "?")
        (ref atom))
      (? 2))
    (alt
      ((lit "@")
        (ref name)
        (lit "(")
        (ref args)
        (lit ")"))
      (builtin 2 ...4))
    (alt
      ((ref record)))
    (alt
      ((ref lambda)))
    (alt
      ((lit "[")
        (ref args)
        (lit "]"))
      (array ...2))
    (alt
      ((lit "(")
        (ref expr)
        (lit ")"))
      2)
    (alt
      ((tok DOT_LBRACE)
        (list_req
          L
          (plain dotpair))
        (lit "}"))
      (anon_init ...2))
    (alt
      ((tok DOT_LBRACE)
        (ref args)
        (lit "}"))
      (anon_init ...2))
    (alt
      ((tok DOT_LBRACE)
        (lit "}"))
      (anon_init)))
  (rule
    (name record)
    (alt
      ((ref name)
        (lit "{")
        (list_req
          L
          (plain pair))
        (lit "}"))
      (record 1 ...3)))
  (rule
    (name pair)
    (alt
      ((ref name)
        (lit ":")
        (ref expr))
      (pair 1 3)))
  (rule
    (name dotpair)
    (alt
      ((lit ".")
        (ref name)
        (lit "=")
        (ref expr))
      (pair 2 4)))
  (rule
    (name lambda)
    (alt
      ((tok FN)
        (ref params)
        (ref block))
      (lambda 2 returns:_ 3))
    (alt
      ((tok FN)
        (ref block))
      (lambda params:_ returns:_ 2)))
  (infix
    unary
    (level
      (infix_op "|>" left))
    (level
      (infix_op "||" left))
    (level
      (infix_op "&&" left))
    (level
      (infix_op "|" left))
    (level
      (infix_op "^" left))
    (level
      (infix_op "&" left))
    (level
      (infix_op "==" none)
      (infix_op "!=" none)
      (infix_op "<" none)
      (infix_op ">" none)
      (infix_op "<=" none)
      (infix_op ">=" none))
    (level
      (infix_op ".." none))
    (level
      (infix_op "<<" left)
      (infix_op ">>" left))
    (level
      (infix_op "+" left)
      (infix_op "-" left))
    (level
      (infix_op "*" left)
      (infix_op "/" left)
      (infix_op "%" left))
    (level
      (infix_op "**" right))))
