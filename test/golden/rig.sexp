(grammar
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
    (name `stmt`)
    (alt
      _
      ((ref `use`)))
    (alt
      _
      ((ref `decl`)))
    (alt
      _
      ((ref `extvar`)))
    (alt
      _
      ((ref `ext_fun`)))
    (alt
      _
      ((ref `ext_sub`)))
    (alt
      _
      ((ref `zig`)))
    (alt
      _
      ((lit `":"`)
        (ref `name`)
        (ref `stmt`))
      `(labeled 2 3)`)
    (alt
      _
      ((ref `simple`)))
    (alt
      _
      ((ref `guarded`)
        (tok `POST_IF`)
        (ref `value`))
      `(if 3 1)`))
  (rule
    (name `guarded`)
    (alt
      _
      ((ref `simple`))
      `(block 1)`))
  (rule
    (name `simple`)
    (alt
      _
      ((ref `tail`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"="`)
        (ref `tail`))
      `(set _      1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"+="`)
        (ref `tail`))
      `(set +=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"-="`)
        (ref `tail`))
      `(set -=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"*="`)
        (ref `tail`))
      `(set *=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"/="`)
        (ref `tail`))
      `(set /=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"%="`)
        (ref `tail`))
      `(set %=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"&="`)
        (ref `tail`))
      `(set &=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"|="`)
        (ref `tail`))
      `(set |=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"^="`)
        (ref `tail`))
      `(set ^=     1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"<<="`)
        (ref `tail`))
      `(set <<=    1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `">>="`)
        (ref `tail`))
      `(set >>=    1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"=!"`)
        (ref `tail`))
      `(set fixed  1 _ 3)`)
    (alt
      _
      ((ref `postfix`)
        (lit `"<-"`)
        (ref `tail`))
      `(set move   1 _ 3)`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `tail`))
      `(set _      1 3 5)`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"=!"`)
        (ref `tail`))
      `(set fixed  1 3 5)`)
    (alt
      _
      ((tok `NEW`)
        (ref `name`)
        (lit `"="`)
        (ref `tail`))
      `(set shadow 2 _ 4)`)
    (alt
      _
      ((tok `DROP_STMT`)
        (ref `name`))
      `(drop 2)`)
    (alt
      _
      ((tok `RETURN`)
        (ref `tail`))
      `(return 2)`)
    (alt
      _
      ((tok `RETURN`))
      `(return)`)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (ref `tail`))
      `(break 4 3)`)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`))
      `(break _ 3)`)
    (alt
      _
      ((tok `BREAK`)
        (ref `tail`))
      `(break 2)`)
    (alt
      _
      ((tok `BREAK`))
      `(break)`)
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`))
      `(continue 3)`)
    (alt
      _
      ((tok `CONTINUE`))
      `(continue)`)
    (alt
      _
      ((tok `DEFER`)
        (ref `block`))
      `(defer 2)`)
    (alt
      _
      ((tok `DEFER`)
        (ref `simple`))
      `(defer 2)`)
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `block`))
      `(errdefer 2)`)
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `simple`))
      `(errdefer 2)`)
    (alt
      _
      ((tok `PRE`)
        (ref `block`))
      `(pre_block 2)`)
    (alt
      _
      ((tok `RAW`)
        (ref `block`))
      `(raw_block 2)`))
  (rule
    (name `decl`)
    (alt
      _
      ((ref `defn`)))
    (alt
      _
      ((tok `PUB`)
        (ref `defn`))
      `(pub 2)`))
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
      ((ref `test`))))
  (rule
    (name `use`)
    (alt
      _
      ((tok `USE`)
        (ref `name`))
      `(use 2)`))
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
    (name `returns`)
    (alt
      _
      ((lit `"->"`)
        (ref `type`))
      `2`))
  (rule
    (name `params`)
    (alt
      _
      ((ref `lparen`)
        (list_req
          `L`
          (plain `field`))
        (lit `")"`))
      `(...2)`)
    (alt
      _
      ((ref `lparen`)
        (lit `")"`))
      `()`))
  (rule
    (name `lparen`)
    (alt
      _
      ((tok `LPAREN_CALL`)))
    (alt
      _
      ((lit `"("`))))
  (rule
    (name `field`)
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
        (lit `"="`)
        (ref `expr`))
      `(default 1 3 5)`)
    (alt
      _
      ((tok `PRE`)
        (ref `fname`)
        (lit `":"`)
        (ref `type`))
      `(pre_param 2 4)`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `fname`))
      `(read 2)        # \`?self\``)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `fname`))
      `(write 2)       # \`!self\``))
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
    (name `enum`)
    (alt
      _
      ((tok `ENUM`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(enum 2 ...4)`)
    (alt
      _
      ((tok `ENUM`)
        (ref `name`)
        (ref `params`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      `(generic_enum 2 3 ...5)`))
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
      `(valued 1 3)    # enum value: \`ok = 200\``)
    (alt
      _
      ((ref `name`)
        (ref `params`))
      `(variant 1 2)   # payload variant: \`circle(r: Int)\``)
    (alt
      _
      ((ref `fun`)))
    (alt
      _
      ((ref `sub`)))
    (alt
      _
      ((tok `DROP`)
        (ref `dparams`)
        (ref `block`))
      `(drop_decl 2 3) # \`drop self: !Self\``))
  (rule
    (name `dparams`)
    (alt
      _
      ((list_req
          `L`
          (plain `field`)))
      `(...1)`))
  (rule
    (name `test`)
    (alt
      _
      ((tok `TEST`)
        (tok `STRING_DQ`)
        (ref `block`))
      `(test 2 3)`))
  (rule
    (name `extvar`)
    (alt
      _
      ((tok `EXTERN`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      `(extern _ 2 4)`))
  (rule
    (name `ext_fun`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`)
        (ref `params`)
        (ref `returns`))
      `(extern_fun 3 4 5)`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`)
        (ref `returns`))
      `(extern_fun 3 _ 4)`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`)
        (ref `params`))
      `(extern_fun 3 4 _)`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`))
      `(extern_fun 3 _ _)`))
  (rule
    (name `ext_sub`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `SUB`)
        (ref `name`)
        (ref `params`))
      `(extern_sub 3 4)`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `SUB`)
        (ref `name`))
      `(extern_sub 3 _)`))
  (rule
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_DQ`))
      `(zig 2)`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_SQ`))
      `(zig 2)`))
  (rule
    (name `type`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `type`))
      `(borrow_read 2)`)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `type`))
      `(borrow_write 2)`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `type`))
      `(shared 2)`)
    (alt
      _
      ((lit `"~"`)
        (ref `type`))
      `(weak 2)`)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `type`))
      `(slice 3)`)
    (alt
      _
      ((lit `"["`)
        (tok `INTEGER`)
        (lit `"]"`)
        (ref `type`))
      `(array_type 2 4)`)
    (alt
      _
      ((tok `FUN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`)
        (ref `type`))
      `(fun_type 3 5)   # \`fun(Int) Int\``)
    (alt
      _
      ((tok `FUN`)
        (lit `"("`)
        (lit `")"`)
        (ref `type`))
      `(fun_type _ 4)`)
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`))
      `(fun_type 3)     # \`sub(Int)\``)
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (lit `")"`))
      `(fun_type)`)
    (alt
      _
      ((ref `tsuffix`))))
  (rule
    (name `tsuffix`)
    (alt
      _
      ((ref `tsuffix`)
        (tok `SUFFIX_Q`))
      `(optional 1)`)
    (alt
      _
      ((ref `tsuffix`)
        (tok `SUFFIX_BANG`))
      `(error_union 1)`)
    (alt
      _
      ((ref `tatom`))))
  (rule
    (name `tatom`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((ref `name`)
        (lit `"."`)
        (ref `name`))
      `(member 1 3)  # \`geo.Point\``)
    (alt
      _
      ((tok `TYPE`))
      `1  # \`pre T: type\``)
    (alt
      _
      ((ref `name`)
        (tok `LPAREN_CALL`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`))
      `(generic_inst 1 ...3)`)
    (alt
      _
      ((ref `name`)
        (tok `LPAREN_CALL`)
        (lit `")"`))
      `(generic_inst 1)`)
    (alt
      _
      ((lit `"("`)
        (ref `type`)
        (lit `")"`))
      `2`))
  (rule
    (name `tail`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((ref `cmd`)))
    (alt
      _
      ((ref `cclosure`))))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `value`)))
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
      ((ref `logic`)
        (tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`)
        (ref `block`))
      `(catch 1 4 6)`)
    (alt
      _
      ((ref `closure`)))
    (alt
      _
      ((tok `PRE`)
        (ref `value`))
      `(pre 2)`))
  (rule
    (name `value`)
    (alt
      _
      ((ref `logic`)
        (tok `TERNARY_IF`)
        (ref `logic`)
        (tok `ELSE`)
        (ref `value`))
      `(if 3 1 5)`)
    (alt
      _
      ((ref `logic`)
        (tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`)
        (ref `value`))
      `(catch 1 4 6)`)
    (alt
      _
      ((ref `logic`)
        (tok `CATCH`)
        (ref `value`))
      `(catch 1 _ 3)`)
    (alt
      _
      ((ref `logic`))))
  (rule
    (name `logic`)
    (alt
      _
      ((ref `logic`)
        (tok `OR`)
        (ref `conj`))
      `(or 1 3)`)
    (alt
      _
      ((ref `conj`))))
  (rule
    (name `conj`)
    (alt
      _
      ((ref `conj`)
        (tok `AND`)
        (ref `neg`))
      `(and 1 3)`)
    (alt
      _
      ((ref `neg`))))
  (rule
    (name `neg`)
    (alt
      _
      ((tok `NOT`)
        (ref `neg`))
      `(not 2)`)
    (alt
      _
      ((at_ref `infix`))))
  (rule
    (name `cond`)
    (alt
      _
      ((ref `value`)))
    (alt
      _
      ((ref `cmd`))))
  (rule
    (name `cmd`)
    (alt
      _
      ((ref `postfix`)
        (ref `cmdargs`))
      `(call 1 ...2)`))
  (rule
    (name `cmdargs`)
    (alt
      _
      ((ref `exprs`))
      `1`)
    (alt
      _
      ((ref `exprs`)
        (lit `","`)
        (ref `cmdtail`))
      `(...1 3)`)
    (alt
      _
      ((ref `cmdtail`))
      `(1)`))
  (rule
    (name `exprs`)
    (alt
      _
      ((ref `expr`))
      `(1)`)
    (alt
      _
      ((ref `exprs`)
        (lit `","`)
        (ref `expr`))
      `(...1 3)`))
  (rule
    (name `cmdtail`)
    (alt
      _
      ((ref `cmd`)))
    (alt
      _
      ((ref `cclosure`))))
  (rule
    (name `ifcond`)
    (alt
      _
      ((ref `cond`)))
    (alt
      _
      ((ref `value`)
        (tok `AS`)
        (ref `name`))
      `(as 1 3)`))
  (rule
    (name `if`)
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `if`))
      `(if 2 3 5)`)
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(if 2 3 5)`)
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`))
      `(if 2 3)`))
  (rule
    (name `while`)
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(while 2 _ 3 else:5)`)
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (lit `":"`)
        (ref `simple`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(while 2 4 5 else:7)`)
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (ref `block`))
      `(while 2 _ 3)`)
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (lit `":"`)
        (ref `simple`)
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
        (ref `cond`)
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
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      `(for ptr  3 5 7 8 else:10)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
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
        (ref `cond`)
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
        (ref `cond`)
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
        (ref `cond`)
        (ref `block`))
      `(for ptr  3 5 7 8)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
        (ref `block`))
      `(for iter 2 _ 4 5)`)
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
        (ref `block`))
      `(for iter 2 4 6 7)`))
  (rule
    (name `match`)
    (alt
      _
      ((tok `MATCH`)
        (ref `cond`)
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
    (name `arm`)
    (alt
      _
      ((ref `pattern`)
        (lit `"=>"`)
        (ref `simple`))
      `(arm 1 3)`)
    (alt
      _
      ((ref `pattern`)
        (ref `block`))
      `(arm 1 2)`))
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
    (name `patatom`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((tok `ELSE`))
      `1  # default arm`)
    (alt
      _
      ((tok `INTEGER`)))
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (tok `INTEGER`))
      `(neg 2)`)
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
      ((tok `DOT_LIT`)
        (ref `name`))
      `(enum_lit 2)`)
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (list_req
          `L`
          (plain `name`))
        (lit `")"`))
      `(variant_pattern 2 ...4)`)
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (lit `")"`))
      `(variant_pattern 2)`))
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
      `(catch_block 3 5)`))
  (rule
    (name `closure`)
    (alt
      _
      ((ref `lambda`)))
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `lambda`))
      `(share 2)`))
  (rule
    (name `lambda`)
    (alt
      _
      ((ref `bars`)
        (ref `block`))
      `(lambda 1 _ _ 2)`)
    (alt
      _
      ((ref `bars`)
        (ref `ebody`))
      `(lambda 1 _ _ 2)`))
  (rule
    (name `cclosure`)
    (alt
      _
      ((ref `clambda`)))
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `clambda`))
      `(share 2)`))
  (rule
    (name `clambda`)
    (alt
      _
      ((ref `bars`)
        (ref `cbody`))
      `(lambda 1 _ _ 2)`))
  (rule
    (name `bars`)
    (alt
      _
      ((tok `BAR_CAPTURE`)
        (list_req
          `L`
          (plain `barent`))
        (tok `BAR_CAPTURE`))
      `(...2)`)
    (alt
      _
      ((tok `BAR_EMPTY`))
      `()`))
  (rule
    (name `barent`)
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
      ((tok `CLONE_PFX`)
        (ref `name`))
      `(cap_clone 2)`)
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `name`))
      `(cap_move 2)`)
    (alt
      _
      ((lit `"~"`)
        (ref `name`))
      `(cap_weak 2)`))
  (rule
    (name `ebody`)
    (alt
      _
      ((ref `expr`))
      `(block 1)`))
  (rule
    (name `cbody`)
    (alt
      _
      ((ref `cmd`))
      `(block 1)`))
  (rule
    (name `unary`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `unary`))
      `(neg 2)`)
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `unary`))
      `(move 2)`)
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `unary`))
      `(clone 2)`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `unary`))
      `(read 2)`)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `unary`))
      `(write 2)`)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `unary`))
      `(share 2)`)
    (alt
      _
      ((lit `"~"`)
        (ref `unary`))
      `(weak 2)`)
    (alt
      _
      ((tok `PIN_PFX`)
        (ref `unary`))
      `(pin 2)`)
    (alt
      _
      ((ref `postfix`))))
  (rule
    (name `postfix`)
    (alt
      _
      ((ref `postfix`)
        (lit `"."`)
        (ref `name`))
      `(member 1 3)`)
    (alt
      _
      ((ref `postfix`)
        (tok `LBRACKET_INDEX`)
        (ref `expr`)
        (lit `"]"`))
      `(index 1 3)`)
    (alt
      _
      ((ref `postfix`)
        (tok `LPAREN_CALL`)
        (ref `args`)
        (lit `")"`))
      `(call 1 ...3)`)
    (alt
      _
      ((ref `postfix`)
        (tok `SUFFIX_BANG`))
      `(propagate 1)`)
    (alt
      _
      ((ref `atom`))))
  (rule
    (name `args`)
    (alt
      _
      ((ref `callargs`))
      `1`)
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `cmdtail`))
      `(...1 3)`)
    (alt
      _
      ((ref `cmdtail`))
      `(1)`)
    (alt _ () `()`))
  (rule
    (name `callargs`)
    (alt
      _
      ((ref `callarg`))
      `(1)`)
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `callarg`))
      `(...1 3)`))
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
      ((tok `DOT_LIT`)
        (ref `name`))
      `(enum_lit 2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (ref `args`)
        (lit `")"`))
      `(builtin 2 ...4)`)
    (alt
      _
      ((lit `"["`)
        (ref `elems`)
        (lit `"]"`))
      `(array ...2)`)
    (alt
      _
      ((lit `"("`)
        (ref `tail`)
        (lit `")"`))
      `2`))
  (rule
    (name `elems`)
    (alt
      _
      ((list_req
          `L`
          (plain `expr`)))
      `(...1)`)
    (alt _ () `()`))
  (infix
    `unary`
    (level
      (infix_op `"=="` `none`)
      (infix_op `"!="` `none`)
      (infix_op `"<"` `none`)
      (infix_op `">"` `none`)
      (infix_op `"<="` `none`)
      (infix_op `">="` `none`))
    (level
      (infix_op `"??"` `right`))
    (level
      (infix_op `".."` `none`))
    (level
      (infix_op `"|"` `left`))
    (level
      (infix_op `"^"` `left`))
    (level
      (infix_op `"&"` `left`))
    (level
      (infix_op `"<<"` `left`)
      (infix_op `">>"` `left`))
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`)
      (infix_op `"%"` `left`))))
