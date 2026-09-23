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
      (node
        `module`
        (spread `1`))))
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
    (name `block`)
    (alt
      _
      ((tok `INDENT`)
        (ref `body`)
        (tok `OUTDENT`))
      (node
        `block`
        (spread `2`)))
    (alt
      _
      ((tok `INDENT`)
        (tok `OUTDENT`))
      (node `block`)))
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
      (node
        `labeled`
        (pos `2`)
        (pos `3`)))
    (alt
      _
      ((ref `simple`)))
    (alt
      _
      ((ref `guarded`)
        (tok `POST_IF`)
        (ref `value`))
      (node
        `if`
        (pos `3`)
        (pos `1`))))
  (rule
    (name `guarded`)
    (alt
      _
      ((ref `simple`))
      (node
        `block`
        (pos `1`))))
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
      (node
        `set`
        (null)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"+="`)
        (ref `tail`))
      (node
        `set`
        (tag `+=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"-="`)
        (ref `tail`))
      (node
        `set`
        (tag `-=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"*="`)
        (ref `tail`))
      (node
        `set`
        (tag `*=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"/="`)
        (ref `tail`))
      (node
        `set`
        (tag `/=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"%="`)
        (ref `tail`))
      (node
        `set`
        (tag `%=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"&="`)
        (ref `tail`))
      (node
        `set`
        (tag `&=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"|="`)
        (ref `tail`))
      (node
        `set`
        (tag `|=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"^="`)
        (ref `tail`))
      (node
        `set`
        (tag `^=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"<<="`)
        (ref `tail`))
      (node
        `set`
        (tag `<<=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `">>="`)
        (ref `tail`))
      (node
        `set`
        (tag `>>=`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"=!"`)
        (ref `tail`))
      (node
        `set`
        (tag `fixed`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (lit `"<-"`)
        (ref `tail`))
      (node
        `set`
        (tag `move`)
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `tail`))
      (node
        `set`
        (null)
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"=!"`)
        (ref `tail`))
      (node
        `set`
        (tag `fixed`)
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `NEW`)
        (ref `name`)
        (lit `"="`)
        (ref `tail`))
      (node
        `set`
        (tag `shadow`)
        (pos `2`)
        (null)
        (pos `4`)))
    (alt
      _
      ((tok `DROP_STMT`)
        (ref `name`))
      (node
        `drop`
        (pos `2`)))
    (alt
      _
      ((tok `RETURN`)
        (ref `tail`))
      (node
        `return`
        (pos `2`)))
    (alt
      _
      ((tok `RETURN`))
      (node `return`))
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (ref `tail`))
      (node
        `break`
        (pos `4`)
        (pos `3`)))
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`))
      (node
        `break`
        (null)
        (pos `3`)))
    (alt
      _
      ((tok `BREAK`)
        (ref `tail`))
      (node
        `break`
        (pos `2`)))
    (alt
      _
      ((tok `BREAK`))
      (node `break`))
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`))
      (node
        `continue`
        (pos `3`)))
    (alt
      _
      ((tok `CONTINUE`))
      (node `continue`))
    (alt
      _
      ((tok `DEFER`)
        (ref `block`))
      (node
        `defer`
        (pos `2`)))
    (alt
      _
      ((tok `DEFER`)
        (ref `simple`))
      (node
        `defer`
        (pos `2`)))
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `block`))
      (node
        `errdefer`
        (pos `2`)))
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `simple`))
      (node
        `errdefer`
        (pos `2`)))
    (alt
      _
      ((tok `PRE`)
        (ref `block`))
      (node
        `pre_block`
        (pos `2`)))
    (alt
      _
      ((tok `RAW`)
        (ref `block`))
      (node
        `raw_block`
        (pos `2`))))
  (rule
    (name `decl`)
    (alt
      _
      ((ref `defn`)))
    (alt
      _
      ((tok `PUB`)
        (ref `defn`))
      (node
        `pub`
        (pos `2`))))
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
      (node
        `use`
        (pos `2`))))
  (rule
    (name `fun`)
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `params`)
        (ref `returns`)
        (ref `block`))
      (node
        `fun`
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)))
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `params`)
        (ref `block`))
      (node
        `fun`
        (pos `2`)
        (pos `3`)
        (null)
        (pos `4`)))
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `returns`)
        (ref `block`))
      (node
        `fun`
        (pos `2`)
        (null)
        (pos `3`)
        (pos `4`)))
    (alt
      _
      ((tok `FUN`)
        (ref `name`)
        (ref `block`))
      (node
        `fun`
        (pos `2`)
        (null)
        (null)
        (pos `3`))))
  (rule
    (name `sub`)
    (alt
      _
      ((tok `SUB`)
        (ref `name`)
        (ref `params`)
        (ref `block`))
      (node
        `sub`
        (pos `2`)
        (pos `3`)
        (null)
        (pos `4`)))
    (alt
      _
      ((tok `SUB`)
        (ref `name`)
        (ref `block`))
      (node
        `sub`
        (pos `2`)
        (null)
        (null)
        (pos `3`))))
  (rule
    (name `returns`)
    (alt
      _
      ((lit `"->"`)
        (ref `type`))
      (pos `2`)))
  (rule
    (name `params`)
    (alt
      _
      ((ref `lparen`)
        (list_req
          `L`
          (plain `field`))
        (lit `")"`))
      (list
        (spread `2`)))
    (alt
      _
      ((ref `lparen`)
        (lit `")"`))
      (list)))
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
      (pos `1`))
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`))
      (node
        `:`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      (node
        `default`
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `PRE`)
        (ref `fname`)
        (lit `":"`)
        (ref `type`))
      (node
        `pre_param`
        (pos `2`)
        (pos `4`)))
    (alt
      _
      ((tok `READ_PFX`)
        (ref `fname`))
      (node
        `read`
        (pos `2`)))
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `fname`))
      (node
        `write`
        (pos `2`))))
  (rule
    (name `fname`)
    (alt
      _
      ((ref `name`))
      (pos `1`))
    (alt
      _
      ((tok `KWARG_NAME`))
      (pos `1`)))
  (rule
    (name `enum`)
    (alt
      _
      ((tok `ENUM`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      (node
        `enum`
        (pos `2`)
        (spread `4`)))
    (alt
      _
      ((tok `ENUM`)
        (ref `name`)
        (ref `params`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      (node
        `generic_enum`
        (pos `2`)
        (pos `3`)
        (spread `5`))))
  (rule
    (name `errors`)
    (alt
      _
      ((tok `ERROR`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      (node
        `errors`
        (pos `2`)
        (spread `4`))))
  (rule
    (name `struct`)
    (alt
      _
      ((tok `STRUCT`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      (node
        `struct`
        (pos `2`)
        (spread `4`))))
  (rule
    (name `typedef`)
    (alt
      _
      ((tok `TYPE`)
        (ref `name`)
        (lit `"="`)
        (ref `type`))
      (node
        `type`
        (pos `2`)
        (pos `4`)))
    (alt
      _
      ((tok `TYPE`)
        (ref `name`)
        (ref `params`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      (node
        `generic_type`
        (pos `2`)
        (pos `3`)
        (spread `5`)))
    (alt
      _
      ((tok `TYPE`)
        (ref `name`)
        (tok `INDENT`)
        (ref `members`)
        (tok `OUTDENT`))
      (node
        `generic_type`
        (pos `2`)
        (null)
        (spread `4`))))
  (rule
    (name `members`)
    (alt
      _
      ((ref `member`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `members`)
        (tok `NEWLINE`)
        (ref `member`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `members`)
        (tok `NEWLINE`))
      (pos `1`)))
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
      (node
        `valued`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `name`)
        (ref `params`))
      (node
        `variant`
        (pos `1`)
        (pos `2`)))
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
      (node
        `drop_decl`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `dparams`)
    (alt
      _
      ((list_req
          `L`
          (plain `field`)))
      (list
        (spread `1`))))
  (rule
    (name `test`)
    (alt
      _
      ((tok `TEST`)
        (tok `STRING_DQ`)
        (ref `block`))
      (node
        `test`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `extvar`)
    (alt
      _
      ((tok `EXTERN`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      (node
        `extern`
        (null)
        (pos `2`)
        (pos `4`))))
  (rule
    (name `ext_fun`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`)
        (ref `params`)
        (ref `returns`))
      (node
        `extern_fun`
        (pos `3`)
        (pos `4`)
        (pos `5`)))
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`)
        (ref `returns`))
      (node
        `extern_fun`
        (pos `3`)
        (null)
        (pos `4`)))
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`)
        (ref `params`))
      (node
        `extern_fun`
        (pos `3`)
        (pos `4`)
        (null)))
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`))
      (node
        `extern_fun`
        (pos `3`)
        (null)
        (null))))
  (rule
    (name `ext_sub`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `SUB`)
        (ref `name`)
        (ref `params`))
      (node
        `extern_sub`
        (pos `3`)
        (pos `4`)))
    (alt
      _
      ((tok `EXTERN`)
        (tok `SUB`)
        (ref `name`))
      (node
        `extern_sub`
        (pos `3`)
        (null))))
  (rule
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_DQ`))
      (node
        `zig`
        (pos `2`)))
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_SQ`))
      (node
        `zig`
        (pos `2`))))
  (rule
    (name `type`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `type`))
      (node
        `borrow_read`
        (pos `2`)))
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `type`))
      (node
        `borrow_write`
        (pos `2`)))
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `type`))
      (node
        `shared`
        (pos `2`)))
    (alt
      _
      ((lit `"~"`)
        (ref `type`))
      (node
        `weak`
        (pos `2`)))
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `type`))
      (node
        `slice`
        (pos `3`)))
    (alt
      _
      ((lit `"["`)
        (tok `INTEGER`)
        (lit `"]"`)
        (ref `type`))
      (node
        `array_type`
        (pos `2`)
        (pos `4`)))
    (alt
      _
      ((tok `FUN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`)
        (ref `type`))
      (node
        `fun_type`
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `FUN`)
        (lit `"("`)
        (lit `")"`)
        (ref `type`))
      (node
        `fun_type`
        (null)
        (pos `4`)))
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`))
      (node
        `fun_type`
        (pos `3`)))
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (lit `")"`))
      (node `fun_type`))
    (alt
      _
      ((ref `tsuffix`))))
  (rule
    (name `tsuffix`)
    (alt
      _
      ((ref `tsuffix`)
        (tok `SUFFIX_Q`))
      (node
        `optional`
        (pos `1`)))
    (alt
      _
      ((ref `tsuffix`)
        (tok `SUFFIX_BANG`))
      (node
        `error_union`
        (pos `1`)))
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
      (node
        `member`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((tok `TYPE`))
      (pos `1`))
    (alt
      _
      ((ref `name`)
        (tok `LPAREN_CALL`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`))
      (node
        `generic_inst`
        (pos `1`)
        (spread `3`)))
    (alt
      _
      ((ref `name`)
        (tok `LPAREN_CALL`)
        (lit `")"`))
      (node
        `generic_inst`
        (pos `1`)))
    (alt
      _
      ((lit `"("`)
        (ref `type`)
        (lit `")"`))
      (pos `2`)))
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
      (node
        `catch`
        (pos `1`)
        (pos `4`)
        (pos `6`)))
    (alt
      _
      ((ref `closure`)))
    (alt
      _
      ((tok `PRE`)
        (ref `value`))
      (node
        `pre`
        (pos `2`))))
  (rule
    (name `value`)
    (alt
      _
      ((ref `logic`)
        (tok `TERNARY_IF`)
        (ref `logic`)
        (tok `ELSE`)
        (ref `value`))
      (node
        `if`
        (pos `3`)
        (pos `1`)
        (pos `5`)))
    (alt
      _
      ((ref `logic`)
        (tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`)
        (ref `value`))
      (node
        `catch`
        (pos `1`)
        (pos `4`)
        (pos `6`)))
    (alt
      _
      ((ref `logic`)
        (tok `CATCH`)
        (ref `value`))
      (node
        `catch`
        (pos `1`)
        (null)
        (pos `3`)))
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
      (node
        `or`
        (pos `1`)
        (pos `3`)))
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
      (node
        `and`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `neg`))))
  (rule
    (name `neg`)
    (alt
      _
      ((tok `NOT`)
        (ref `neg`))
      (node
        `not`
        (pos `2`)))
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
      (node
        `call`
        (pos `1`)
        (spread `2`))))
  (rule
    (name `cmdargs`)
    (alt
      _
      ((ref `exprs`))
      (pos `1`))
    (alt
      _
      ((ref `exprs`)
        (lit `","`)
        (ref `cmdtail`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `cmdtail`))
      (list
        (pos `1`))))
  (rule
    (name `exprs`)
    (alt
      _
      ((ref `expr`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `exprs`)
        (lit `","`)
        (ref `expr`))
      (list
        (spread `1`)
        (pos `3`))))
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
      (node
        `as`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `if`)
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `if`))
      (node
        `if`
        (pos `2`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `if`
        (pos `2`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`))
      (node
        `if`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `while`)
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `while`
        (pos `2`)
        (null)
        (pos `3`)
        (named
          `else`
          (pos `5`))))
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (lit `":"`)
        (ref `simple`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `while`
        (pos `2`)
        (pos `4`)
        (pos `5`)
        (named
          `else`
          (pos `7`))))
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (ref `block`))
      (node
        `while`
        (pos `2`)
        (null)
        (pos `3`)))
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (lit `":"`)
        (ref `simple`)
        (ref `block`))
      (node
        `while`
        (pos `2`)
        (pos `4`)
        (pos `5`))))
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
      (node
        `for`
        (tag `ptr`)
        (pos `3`)
        (null)
        (pos `5`)
        (pos `6`)
        (named
          `else`
          (pos `8`))))
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
      (node
        `for`
        (tag `ptr`)
        (pos `3`)
        (pos `5`)
        (pos `7`)
        (pos `8`)
        (named
          `else`
          (pos `10`))))
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `for`
        (tag `iter`)
        (pos `2`)
        (null)
        (pos `4`)
        (pos `5`)
        (named
          `else`
          (pos `7`))))
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
      (node
        `for`
        (tag `iter`)
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (pos `7`)
        (named
          `else`
          (pos `9`))))
    (alt
      _
      ((tok `FOR`)
        (tok `SHARE_PFX`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
        (ref `block`))
      (node
        `for`
        (tag `ptr`)
        (pos `3`)
        (null)
        (pos `5`)
        (pos `6`)))
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
      (node
        `for`
        (tag `ptr`)
        (pos `3`)
        (pos `5`)
        (pos `7`)
        (pos `8`)))
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
        (ref `block`))
      (node
        `for`
        (tag `iter`)
        (pos `2`)
        (null)
        (pos `4`)
        (pos `5`)))
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `cond`)
        (ref `block`))
      (node
        `for`
        (tag `iter`)
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (pos `7`))))
  (rule
    (name `match`)
    (alt
      _
      ((tok `MATCH`)
        (ref `cond`)
        (tok `INDENT`)
        (ref `arms`)
        (tok `OUTDENT`))
      (node
        `match`
        (pos `2`)
        (spread `4`))))
  (rule
    (name `arms`)
    (alt
      _
      ((ref `arm`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `arms`)
        (tok `NEWLINE`)
        (ref `arm`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `arms`)
        (tok `NEWLINE`))
      (pos `1`)))
  (rule
    (name `arm`)
    (alt
      _
      ((ref `pattern`)
        (lit `"=>"`)
        (ref `simple`))
      (node
        `arm`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `pattern`)
        (ref `block`))
      (node
        `arm`
        (pos `1`)
        (pos `2`))))
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
      (node
        `range_pattern`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `patatom`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((tok `ELSE`))
      (pos `1`))
    (alt
      _
      ((tok `INTEGER`)))
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (tok `INTEGER`))
      (node
        `neg`
        (pos `2`)))
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
      (node
        `enum_lit`
        (pos `2`)))
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (list_req
          `L`
          (plain `name`))
        (lit `")"`))
      (node
        `variant_pattern`
        (pos `2`)
        (spread `4`)))
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (lit `")"`))
      (node
        `variant_pattern`
        (pos `2`))))
  (rule
    (name `try_block`)
    (alt
      _
      ((tok `TRY`)
        (ref `block`)
        (ref `catch_part`))
      (node
        `try_block`
        (pos `2`)
        (pos `3`)))
    (alt
      _
      ((tok `TRY`)
        (ref `block`))
      (node
        `try_block`
        (pos `2`))))
  (rule
    (name `catch_part`)
    (alt
      _
      ((tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`)
        (ref `block`))
      (node
        `catch_block`
        (pos `3`)
        (pos `5`))))
  (rule
    (name `closure`)
    (alt
      _
      ((ref `lambda`)))
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `lambda`))
      (node
        `share`
        (pos `2`))))
  (rule
    (name `lambda`)
    (alt
      _
      ((ref `bars`)
        (ref `block`))
      (node
        `lambda`
        (pos `1`)
        (null)
        (null)
        (pos `2`)))
    (alt
      _
      ((ref `bars`)
        (ref `ebody`))
      (node
        `lambda`
        (pos `1`)
        (null)
        (null)
        (pos `2`))))
  (rule
    (name `cclosure`)
    (alt
      _
      ((ref `clambda`)))
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `clambda`))
      (node
        `share`
        (pos `2`))))
  (rule
    (name `clambda`)
    (alt
      _
      ((ref `bars`)
        (ref `cbody`))
      (node
        `lambda`
        (pos `1`)
        (null)
        (null)
        (pos `2`))))
  (rule
    (name `bars`)
    (alt
      _
      ((tok `BAR_CAPTURE`)
        (list_req
          `L`
          (plain `barent`))
        (tok `BAR_CAPTURE`))
      (list
        (spread `2`)))
    (alt
      _
      ((tok `BAR_EMPTY`))
      (list)))
  (rule
    (name `barent`)
    (alt
      _
      ((ref `fname`))
      (pos `1`))
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`))
      (node
        `:`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `name`))
      (node
        `cap_clone`
        (pos `2`)))
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `name`))
      (node
        `cap_move`
        (pos `2`)))
    (alt
      _
      ((lit `"~"`)
        (ref `name`))
      (node
        `cap_weak`
        (pos `2`))))
  (rule
    (name `ebody`)
    (alt
      _
      ((ref `expr`))
      (node
        `block`
        (pos `1`))))
  (rule
    (name `cbody`)
    (alt
      _
      ((ref `cmd`))
      (node
        `block`
        (pos `1`))))
  (rule
    (name `unary`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `unary`))
      (node
        `neg`
        (pos `2`)))
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `unary`))
      (node
        `move`
        (pos `2`)))
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `unary`))
      (node
        `clone`
        (pos `2`)))
    (alt
      _
      ((tok `READ_PFX`)
        (ref `unary`))
      (node
        `read`
        (pos `2`)))
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `unary`))
      (node
        `write`
        (pos `2`)))
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `unary`))
      (node
        `share`
        (pos `2`)))
    (alt
      _
      ((lit `"~"`)
        (ref `unary`))
      (node
        `weak`
        (pos `2`)))
    (alt
      _
      ((tok `PIN_PFX`)
        (ref `unary`))
      (node
        `pin`
        (pos `2`)))
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
      (node
        `member`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (tok `LBRACKET_INDEX`)
        (ref `expr`)
        (lit `"]"`))
      (node
        `index`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `postfix`)
        (tok `LPAREN_CALL`)
        (ref `args`)
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`)))
    (alt
      _
      ((ref `postfix`)
        (tok `SUFFIX_BANG`))
      (node
        `propagate`
        (pos `1`)))
    (alt
      _
      ((ref `atom`))))
  (rule
    (name `args`)
    (alt
      _
      ((ref `callargs`))
      (pos `1`))
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `cmdtail`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `cmdtail`))
      (list
        (pos `1`)))
    (alt
      _
      ()
      (list)))
  (rule
    (name `callargs`)
    (alt
      _
      ((ref `callarg`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `callarg`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `callarg`)
    (alt
      _
      ((tok `KWARG_NAME`)
        (lit `":"`)
        (ref `expr`))
      (node
        `kwarg`
        (pos `1`)
        (pos `3`)))
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
      (node
        `enum_lit`
        (pos `2`)))
    (alt
      _
      ((lit `"@"`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (ref `args`)
        (lit `")"`))
      (node
        `builtin`
        (pos `2`)
        (spread `4`)))
    (alt
      _
      ((lit `"["`)
        (ref `elems`)
        (lit `"]"`))
      (node
        `array`
        (spread `2`)))
    (alt
      _
      ((lit `"("`)
        (ref `tail`)
        (lit `")"`))
      (pos `2`)))
  (rule
    (name `elems`)
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
