(grammar
  (conflicts `44`)
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
      ((ref `shadow`)))
    (alt
      _
      ((ref `drop`)))
    (alt
      _
      ((ref `typed`)))
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
    (name `typed`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      `(set _     1 3 5)`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"=!"`)
        (ref `expr`))
      `(set fixed 1 3 5)`))
  (rule
    (name `drop`)
    (alt
      _
      ((tok `DROP_STMT`)
        (ref `name`))
      `(drop 2)`))
  (rule
    (name `shadow`)
    (alt
      _
      ((tok `NEW`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(set shadow 2 _ 4)`))
  (rule
    (name `extvar`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `CONST`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      `(extern fixed 3 5)`)
    (alt
      _
      ((tok `EXTERN`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      `(extern _     2 4)`))
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
      `(type 2 4)`)
    (alt
      _
      ((tok `TYPE`)
        (ref `name`)
        (ref `params`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(generic_type 2 3 ...5)`)
    (alt
      _
      ((tok `TYPE`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(generic_type 2 _ ...4)`))
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
    (name `fname`)
    (alt
      _
      ((ref `name`))
      `1`)
    (alt
      _
      ((tok `KWARG_NAME`))
      `1`))
  (rule
    (name `field`)
    (alt
      _
      ((tok `PRE`)
        (ref `fname`)
        (lit `":"`)
        (ref `type`))
      `(pre_param 2 4)`)
    (alt
      _
      ((ref `fname`))
      `1`)
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`))
      `(: 1 3)`)
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`)
        (tok `ALIGN`)
        (ref `atom`))
      `(aligned 1 3 5)`)
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      `(default 1 3 5)`))
  (rule
    (name `params`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `field`))
        (lit `")"`))
      `(...2)`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      `()`)
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
      ((ref `type`)
        (tok `SUFFIX_Q`))
      `(optional 1)     # T?  optional type (suffix binds tightest)`)
    (alt
      _
      ((ref `type`)
        (tok `SUFFIX_BANG`))
      `(error_union 1)  # T!  fallible type (error union)`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `type`))
      `(borrow_read 2)  # ?T  read-borrowed type (param/return)`)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `type`))
      `(borrow_write 2) # !T  write-borrowed type (param/return)`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `type`))
      `(ptr 2)`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (tok `CONST`)
        (ref `type`))
      `(const_ptr 3)`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (tok `VOLATILE`)
        (ref `type`))
      `(volatile_ptr 3)`)
    (alt
      _
      ((lit `"("`)
        (ref `type`)
        (lit `")"`))
      `2                # parens for grouping (e.g., ([]T)?)`)
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
        (tok `SHARE_PFX`)
        (lit `"]"`)
        (ref `type`))
      `(many_ptr 4)`)
    (alt
      _
      ((lit `"["`)
        (tok `SHARE_PFX`)
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
      ((ref `try_block`)))
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
      ((ref `pre`)))
    (alt
      _
      ((ref `inline`)))
    (alt
      _
      ((ref `assign`)))
    (alt
      _
      ((ref `fixed`)))
    (alt
      _
      ((ref `moveassign`)))
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
        (tok `SHARE_PFX`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for ptr  3 _ 5 6 else:8)`)
    (alt
      _
      ((tok `FOR`)
        (tok `SHARE_PFX`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for ptr  3 5 7 8 else:10)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for iter 2 _ 4 5 else:7)`)
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
      `(for iter 2 4 6 7 else:9)`)
    (alt
      _
      ((tok `FOR`)
        (tok `SHARE_PFX`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for ptr  3 _ 5 6)`)
    (alt
      _
      ((tok `FOR`)
        (tok `SHARE_PFX`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for ptr  3 5 7 8)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for iter 2 _ 4 5)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      `(for iter 2 4 6 7)`))
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
    (name `try_block`)
    (alt
      _
      ((tok `TRY`)
        (ref `block`)
        (ref `catch_part`))
      `(try_block 2 3)`)
    (alt
      _
      ((tok `TRY`)
        (ref `block`))
      `(try_block 2)`))
  (rule
    (name `catch_part`)
    (alt
      _
      ((tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`)
        (ref `block`))
      `(catch_block 3 5)`)
    (alt
      _
      ((tok `CATCH`)
        (tok `AS`)
        (ref `name`)
        (ref `block`))
      `(catch_block 3 4)`))
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
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`)
        (ref `expr`))
      `(catch 1 4 6)`)
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
    (name `pre`)
    (alt
      _
      ((tok `PRE`)
        (ref `block`))
      `(pre_block 2)`)
    (alt
      _
      ((tok `PRE`)
        (ref `expr`))
      `(pre 2)`))
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
        (lit `"="`)
        (ref `expr`))
      `(set _      1 _ 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"+="`)
        (ref `expr`))
      `(set +=     1 _ 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"-="`)
        (ref `expr`))
      `(set -=     1 _ 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"*="`)
        (ref `expr`))
      `(set *=     1 _ 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"/="`)
        (ref `expr`))
      `(set /=     1 _ 3)`))
  (rule
    (name `fixed`)
    (alt
      _
      ((ref `call`)
        (lit `"=!"`)
        (ref `expr`))
      `(set fixed  1 _ 3)`))
  (rule
    (name `moveassign`)
    (alt
      _
      ((ref `call`)
        (lit `"<-"`)
        (ref `expr`))
      `(set move   1 _ 3)`))
  (rule
    (name `unary`)
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
      `(weak 2)        # weak reference (replaces Zag bit_not)`)
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `unary`))
      `(move 2)        # <x   move ownership`)
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `unary`))
      `(clone 2)       # +x   clone`)
    (alt
      _
      ((tok `PIN_PFX`)
        (ref `unary`))
      `(pin 2)         # @x   pin (non-builtin form)`)
    (alt
      _
      ((tok `RAW_PFX`)
        (ref `unary`))
      `(raw 2)         # %x   raw / unsafe`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `unary`))
      `(read 2)        # ?x   read borrow`)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `unary`))
      `(write 2)       # !x   write borrow`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `unary`))
      `(share 2)       # *x   share ownership`)
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
      `(member 1 3)`)
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
      ((ref `call`)
        (tok `SUFFIX_BANG`))
      `(propagate 1)   # x!  propagate failure (suffix on expression);`)
    (alt
      _
      ((ref `atom`))))
  (rule
    (name `args`)
    (alt
      _
      ((list_req
          `L`
          (plain `callarg`)))
      `(...1)`)
    (alt _ () `()`))
  (rule
    (name `callarg`)
    (alt
      _
      ((tok `KWARG_NAME`)
        (lit `":"`)
        (ref `expr`))
      `(kwarg 1 3)`)
    (alt
      _
      ((ref `expr`))))
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
      ((lit `"~"`)
        (ref `term`))
      `(weak 2)`)
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `term`))
      `(move 2)`)
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `term`))
      `(clone 2)`)
    (alt
      _
      ((tok `PIN_PFX`)
        (ref `term`))
      `(pin 2)`)
    (alt
      _
      ((tok `RAW_PFX`)
        (ref `term`))
      `(raw 2)`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `term`))
      `(read 2)`)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `term`))
      `(write 2)`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `term`))
      `(share 2)`)
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
      ((tok `DOT_LIT`)
        (ref `name`))
      `(enum_lit 2)     # .strict (inferred-type enum value, SPEC §"Compile-Time Specialization")`)
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
      `(kwarg 1 3)`))
  (rule
    (name `dotpair`)
    (alt
      _
      ((lit `"."`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(kwarg 2 4)`))
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
