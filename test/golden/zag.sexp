(grammar
  (conflicts `19`)
  (as
    `ident`
    (as_entry _ `keyword`))
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
      ((ref `use`)))
    (alt
      _
      ((ref `decl`)))
    (alt
      _
      ((ref `zig`)))
    (alt
      _
      ((ref `extvar`)))
    (alt
      _
      ((lit `":"`)
        (ref `name`)
        (ref `stmt`))
      `(labeled 2 3)`)
    (alt
      _
      ((ref `expr`))))
  (rule
    (name `extvar`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `CONST`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      `(extern_const 3 5)`)
    (alt
      _
      ((tok `EXTERN`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      `(extern_var 2 4)`))
  (rule
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_SQ`))
      `(zig 2)`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_DQ`))
      `(zig 2)`))
  (rule
    (name `decl`)
    (alt
      _
      ((ref `defn`)))
    (alt
      _
      ((tok `PUB`)
        (ref `decl`))
      `(pub 2)`)
    (alt
      _
      ((tok `EXTERN`)
        (ref `decl`))
      `(extern 2)`)
    (alt
      _
      ((tok `EXPORT`)
        (ref `decl`))
      `(export 2)`)
    (alt
      _
      ((tok `PACKED`)
        (ref `decl`))
      `(packed 2)`)
    (alt
      _
      ((tok `CALLCONV`)
        (ref `name`)
        (ref `decl`))
      `(callconv 2 3)`))
  (rule
    (name `defn`)
    (alt
      _
      ((ref `fun`)))
    (alt
      _
      ((ref `sub`)))
    (alt
      _
      ((ref `enum`)))
    (alt
      _
      ((ref `struct`)))
    (alt
      _
      ((ref `errors`)))
    (alt
      _
      ((ref `typedef`)))
    (alt
      _
      ((ref `test`)))
    (alt
      _
      ((ref `opaq`))))
  (rule
    (name `block`)
    (alt
      _
      ((tok `INDENT`)
        (ref `body`)
        (tok `OUTDENT`))
      `(block ...2)`)
    (alt
      _
      ((tok `INDENT`)
        (tok `OUTDENT`))
      `(block)`))
  (rule
    (name `fun`)
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `params`)
        (ref `returns`)
        (ref `block`))
      `(fun 2 3 4 5)`)
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `params`)
        (ref `block`))
      `(fun 2 3 _ 4)`)
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `returns`)
        (ref `block`))
      `(fun 2 _ 3 4)`)
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `block`))
      `(fun 2 _ _ 3)`))
  (rule
    (name `sub`)
    (alt
      _
      ((tok `SUB`)
        (ref `name`)
        (ref `params`)
        (ref `block`))
      `(sub 2 3 _ 4)`)
    (alt
      _
      ((tok `SUB`)
        (ref `name`)
        (ref `block`))
      `(sub 2 _ _ 3)`))
  (rule
    (name `use`)
    (alt
      _
      ((tok `USE`)
        (ref `name`))
      `(use 2)`))
  (rule
    (name `typedef`)
    (alt
      _
      ((tok `TYPE`)
        (ref `name`)
        (lit `"="`)
        (ref `type`))
      `(type 2 4)`))
  (rule
    (name `test`)
    (alt
      _
      ((tok `TEST`)
        (tok `STRING_DQ`)
        (ref `block`))
      `(test 2 3)`))
  (rule
    (name `opaq`)
    (alt
      _
      ((tok `OPAQUE`)
        (ref `name`))
      `(opaque 2)`))
  (rule
    (name `enum`)
    (alt
      _
      ((tok `ENUM`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(enum 2 ...4)`))
  (rule
    (name `errors`)
    (alt
      _
      ((tok `ERROR`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(errors 2 ...4)`))
  (rule
    (name `struct`)
    (alt
      _
      ((tok `STRUCT`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(struct 2 ...4)`))
  (rule
    (name `members`)
    (alt
      _
      ((ref `member`))
      `(1)`)
    (alt
      _
      ((ref `members`)
        (tok `NEWLINE`)
        (ref `member`))
      `(...1 3)`)
    (alt
      _
      ((ref `members`)
        (tok `NEWLINE`))
      `1`))
  (rule
    (name `member`)
    (alt
      _
      ((ref `field`)))
    (alt
      _
      ((ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(valued 1 3)`)
    (alt
      _
      ((ref `fun`)))
    (alt
      _
      ((ref `sub`))))
  (rule
    (name `field`)
    (alt
      _
      ((tok `COMPTIME`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      `(comptime_param 2 4)`)
    (alt
      _
      ((ref `name`))
      `1`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`))
      `(: 1 3)`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (tok `ALIGN`)
        (ref `atom`))
      `(aligned 1 3 5)`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      `(default 1 3 5)`))
  (rule
    (name `params`)
    (alt
      _
      ((list_req
          `L`
          (plain `field`)))
      `(...1)`))
  (rule
    (name `returns`)
    (alt
      _
      ((lit `"->"`)
        (ref `type`))
      `2`))
  (rule
    (name `type`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((lit `"!"`)
        (ref `type`))
      `(error_union 2)`)
    (alt
      _
      ((lit `"?"`)
        (ref `type`))
      `(? 2)`)
    (alt
      _
      ((lit `"*"`)
        (ref `type`))
      `(ptr 2)`)
    (alt
      _
      ((lit `"*"`)
        (tok `CONST`)
        (ref `type`))
      `(const_ptr 3)`)
    (alt
      _
      ((lit `"*"`)
        (tok `VOLATILE`)
        (ref `type`))
      `(volatile_ptr 3)`)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `type`))
      `(slice 3)`)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `atom`)
        (lit `"]"`)
        (ref `type`))
      `(sentinel_slice 3 5)`)
    (alt
      _
      ((lit `"["`)
        (tok `INTEGER`)
        (lit `"]"`)
        (ref `type`))
      `(array_type 2 4)`)
    (alt
      _
      ((lit `"["`)
        (lit `"*"`)
        (lit `"]"`)
        (ref `type`))
      `(many_ptr 4)`)
    (alt
      _
      ((lit `"["`)
        (lit `"*"`)
        (lit `":"`)
        (ref `atom`)
        (lit `"]"`)
        (ref `type`))
      `(sentinel_ptr 4 6)`)
    (alt
      _
      ((tok `FN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`)
        (ref `type`))
      `(fn_type 3 5)`)
    (alt
      _
      ((tok `FN`)
        (lit `"("`)
        (lit `")"`)
        (ref `type`))
      `(fn_type _ 4)`))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `if`)))
    (alt
      _
      ((ref `while`)))
    (alt
      _
      ((ref `for`)))
    (alt
      _
      ((ref `match`)))
    (alt
      _
      ((ref `postif`)))
    (alt
      _
      ((ref `coalesce`)))
    (alt
      _
      ((ref `catch`)))
    (alt
      _
      ((ref `return`)))
    (alt
      _
      ((ref `break`)))
    (alt
      _
      ((ref `continue`)))
    (alt
      _
      ((ref `defer`)))
    (alt
      _
      ((ref `errdefer`)))
    (alt
      _
      ((ref `comptime`)))
    (alt
      _
      ((ref `inline`)))
    (alt
      _
      ((ref `assign`)))
    (alt
      _
      ((ref `const`)))
    (alt
      _
      ((at_ref `infix`))))
  (rule
    (name `cond`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((ref `expr`)
        (tok `AS`)
        (ref `name`))
      `(as 1 3)`)
    (alt
      _
      ((ref `expr`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`))
      `(as 1 3)`))
  (rule
    (name `if`)
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (tok `AS`)
        (ref `name`)
        (ref `block`))
      `(if 2 3 6 7)`)
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (tok `AS`)
        (ref `name`)
        (ref `if`))
      `(if 2 3 6 7)`)
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `if`))
      `(if 2 3 5)`)
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(if 2 3 5)`)
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
        (ref `block`))
      `(if 2 3)`))
  (rule
    (name `while`)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(while 2 _ 3 else:5)`)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond`)
        (lit `":"`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(while 2 4 5 else:7)`)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond`)
        (ref `block`))
      `(while 2 _ 3)`)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond`)
        (lit `":"`)
        (ref `expr`)
        (ref `block`))
      `(while 2 4 5)`))
  (rule
    (name `for`)
    (alt
      _
      ((tok `FOR`)
        (lit `"*"`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for_ptr 3 _ 5 6 else:8)`)
    (alt
      _
      ((tok `FOR`)
        (lit `"*"`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for_ptr 3 5 7 8 else:10)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for 2 _ 4 5 else:7)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for 2 4 6 7 else:9)`)
    (alt
      _
      ((tok `FOR`)
        (lit `"*"`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for_ptr 3 _ 5 6)`)
    (alt
      _
      ((tok `FOR`)
        (lit `"*"`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for_ptr 3 5 7 8)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for 2 _ 4 5)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for 2 4 6 7)`))
  (rule
    (name `match`)
    (alt
      _
      ((tok `MATCH`)
        (ref `expr`)
        (tok `INDENT`)
        (ref `arms`)
        (tok `OUTDENT`))
      `(match 2 ...4)`))
  (rule
    (name `arms`)
    (alt
      _
      ((ref `arm`))
      `(1)`)
    (alt
      _
      ((ref `arms`)
        (tok `NEWLINE`)
        (ref `arm`))
      `(...1 3)`)
    (alt
      _
      ((ref `arms`)
        (tok `NEWLINE`))
      `1`))
  (rule
    (name `patatom`)
    (alt
      _
      ((ref `atom`)))
    (alt
      _
      ((lit `"."`)
        (ref `name`))
      `(enum_pattern 2)`))
  (rule
    (name `pattern`)
    (alt
      _
      ((ref `patatom`)))
    (alt
      _
      ((ref `patatom`)
        (lit `".."`)
        (ref `patatom`))
      `(range_pattern 1 3)`))
  (rule
    (name `arm`)
    (alt
      _
      ((ref `pattern`)
        (tok `AS`)
        (ref `name`)
        (lit `"=>"`)
        (ref `expr`))
      `(arm 1 3 5)`)
    (alt
      _
      ((ref `pattern`)
        (tok `AS`)
        (ref `name`)
        (ref `block`))
      `(arm 1 3 4)`)
    (alt
      _
      ((ref `pattern`)
        (lit `"=>"`)
        (ref `expr`))
      `(arm 1 _ 3)`)
    (alt
      _
      ((ref `pattern`)
        (ref `block`))
      `(arm 1 _ 2)`))
  (rule
    (name `postif`)
    (alt
      _
      ((at_ref `infix`)
        (tok `IF`)
        (ref `expr`)
        (tok `ELSE`)
        (ref `expr`))
      `(ternary 3 1 5)`)
    (alt
      _
      ((at_ref `infix`)
        (tok `IF`)
        (ref `expr`))
      `(if 3 1)`)
    (alt
      _
      ((at_ref `infix`)
        (tok `TERNARY_IF`)
        (ref `expr`)
        (tok `ELSE`)
        (ref `expr`))
      `(ternary 3 1 5)`))
  (rule
    (name `coalesce`)
    (alt
      _
      ((at_ref `infix`)
        (lit `"??"`)
        (ref `expr`))
      `(?? 1 3)`))
  (rule
    (name `catch`)
    (alt
      _
      ((at_ref `infix`)
        (tok `CATCH`)
        (tok `AS`)
        (ref `name`)
        (ref `expr`))
      `(catch 1 4 5)`)
    (alt
      _
      ((at_ref `infix`)
        (tok `CATCH`)
        (ref `expr`))
      `(catch 1 3)`))
  (rule
    (name `return`)
    (alt
      _
      ((tok `RETURN`)
        (ref `expr`)
        (tok `POST_IF`)
        (ref `expr`))
      `(return value:2 if:4)`)
    (alt
      _
      ((tok `RETURN`)
        (tok `POST_IF`)
        (ref `expr`))
      `(return value:_ if:3)`)
    (alt
      _
      ((tok `RETURN`)
        (ref `expr`))
      `(return value:2)`)
    (alt
      _
      ((tok `RETURN`))
      `(return)`))
  (rule
    (name `break`)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (tok `POST_IF`)
        (ref `expr`))
      `(break value:_ to:3 if:5)`)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (ref `expr`))
      `(break value:4 to:3)`)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`))
      `(break value:_ to:3)`)
    (alt
      _
      ((tok `BREAK`)
        (tok `POST_IF`)
        (ref `expr`))
      `(break value:_ to:_ if:3)`)
    (alt
      _
      ((tok `BREAK`)
        (ref `expr`))
      `(break value:2)`)
    (alt
      _
      ((tok `BREAK`))
      `(break)`))
  (rule
    (name `continue`)
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`)
        (tok `POST_IF`)
        (ref `expr`))
      `(continue to:3 if:5)`)
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`))
      `(continue to:3)`)
    (alt
      _
      ((tok `CONTINUE`)
        (tok `POST_IF`)
        (ref `expr`))
      `(continue to:_ if:3)`)
    (alt
      _
      ((tok `CONTINUE`))
      `(continue)`))
  (rule
    (name `defer`)
    (alt
      _
      ((tok `DEFER`)
        (ref `block`))
      `(defer 2)`)
    (alt
      _
      ((tok `DEFER`)
        (ref `expr`))
      `(defer 2)`))
  (rule
    (name `errdefer`)
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `block`))
      `(errdefer 2)`)
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `expr`))
      `(errdefer 2)`))
  (rule
    (name `comptime`)
    (alt
      _
      ((tok `COMPTIME`)
        (ref `expr`))
      `(comptime 2)`))
  (rule
    (name `inline`)
    (alt
      _
      ((tok `INLINE`)
        (ref `expr`))
      `(inline 2)`))
  (rule
    (name `assign`)
    (alt
      _
      ((ref `call`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      `(typed_assign 1 3 5)`)
    (alt
      _
      ((ref `call`)
        (lit `"="`)
        (ref `expr`))
      `( = 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"+="`)
        (ref `expr`))
      `(+= 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"-="`)
        (ref `expr`))
      `(-= 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"*="`)
        (ref `expr`))
      `(*= 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"/="`)
        (ref `expr`))
      `(/= 1 3)`))
  (rule
    (name `const`)
    (alt
      _
      ((ref `call`)
        (lit `":"`)
        (ref `type`)
        (lit `"=!"`)
        (ref `expr`))
      `(typed_const 1 3 5)`)
    (alt
      _
      ((ref `call`)
        (lit `"=!"`)
        (ref `expr`))
      `(const 1 3)`))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"!"`)
        (ref `unary`))
      `(not 2)`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `unary`))
      `(neg 2)`)
    (alt
      _
      ((tok `TRY`)
        (ref `unary`))
      `(try 2)`)
    (alt
      _
      ((lit `"&"`)
        (ref `unary`))
      `(addr_of 2)`)
    (alt
      _
      ((lit `"~"`)
        (ref `unary`))
      `(bit_not 2)`)
    (alt
      _
      ((ref `call`))))
  (rule
    (name `call`)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (lit `"*"`))
      `(deref 1)`)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (ref `name`))
      `(. 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (ref `expr`)
        (lit `"]"`))
      `(index 1 3)`)
    (alt
      _
      ((ref `call`)
        (list_req
          `L`
          (plain `arg`)))
      `(call 1 ...2)`)
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
    (name `arg`)
    (alt
      _
      ((ref `term`)
        (tok `TERNARY_IF`)
        (ref `expr`)
        (tok `ELSE`)
        (ref `arg`))
      `(ternary 3 1 5)`)
    (alt
      _
      ((ref `term`))))
  (rule
    (name `term`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `term`))
      `(neg 2)`)
    (alt
      _
      ((lit `"!"`)
        (ref `term`))
      `(not 2)`)
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
      ((tok `REAL`)))
    (alt
      _
      ((tok `STRING_SQ`)))
    (alt
      _
      ((tok `STRING_DQ`)))
    (alt
      _
      ((tok `TRUE`)))
    (alt
      _
      ((tok `FALSE`)))
    (alt
      _
      ((tok `NULL`))
      `(null)`)
    (alt
      _
      ((tok `UNREACHABLE`))
      `(unreachable)`)
    (alt
      _
      ((tok `UNDEFINED`))
      `(undefined)`)
    (alt
      _
      ((lit `"?"`)
        (ref `atom`))
      `(? 2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `name`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      `(builtin 2 ...4)`)
    (alt
      _
      ((ref `record`)))
    (alt
      _
      ((ref `lambda`)))
    (alt
      _
      ((lit `"["`)
        (ref `args`)
        (lit `"]"`))
      `(array ...2)`)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      `2`)
    (alt
      _
      ((tok `DOT_LBRACE`)
        (list_req
          `L`
          (plain `dotpair`))
        (lit `"}"`))
      `(anon_init ...2)`)
    (alt
      _
      ((tok `DOT_LBRACE`)
        (ref `args`)
        (lit `"}"`))
      `(anon_init ...2)`)
    (alt
      _
      ((tok `DOT_LBRACE`)
        (lit `"}"`))
      `(anon_init)`))
  (rule
    (name `record`)
    (alt
      _
      ((ref `name`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `pair`))
        (lit `"}"`))
      `(record 1 ...3)`))
  (rule
    (name `pair`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `expr`))
      `(pair 1 3)`))
  (rule
    (name `dotpair`)
    (alt
      _
      ((lit `"."`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(pair 2 4)`))
  (rule
    (name `lambda`)
    (alt
      _
      ((tok `FN`)
        (ref `params`)
        (ref `block`))
      `(lambda 2 returns:_ 3)`)
    (alt
      _
      ((tok `FN`)
        (ref `block`))
      `(lambda params:_ returns:_ 2)`))
  (infix
    `unary`
    (level
      (infix_op `"|>"` `left`))
    (level
      (infix_op `"||"` `left`))
    (level
      (infix_op `"&&"` `left`))
    (level
      (infix_op `"|"` `left`))
    (level
      (infix_op `"^"` `left`))
    (level
      (infix_op `"&"` `left`))
    (level
      (infix_op `"=="` `none`)
      (infix_op `"!="` `none`)
      (infix_op `"<"` `none`)
      (infix_op `">"` `none`)
      (infix_op `"<="` `none`)
      (infix_op `">="` `none`))
    (level
      (infix_op `".."` `none`))
    (level
      (infix_op `"<<"` `left`)
      (infix_op `">>"` `left`))
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`)
      (infix_op `"%"` `left`))
    (level
      (infix_op `"**"` `right`))))
