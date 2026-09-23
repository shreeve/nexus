(grammar
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
    (name `block`)
    (alt
      _
      ((tok `INDENT`)
        (ref `body`)
        (tok `OUTDENT`))
      (node
        `block`
        (spread `2`))
      _)
    (alt
      _
      ((tok `INDENT`)
        (tok `OUTDENT`))
      (node `block`)
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((ref `use`))
      _
      _)
    (alt
      _
      ((ref `decl`))
      _
      _)
    (alt
      _
      ((ref `extvar`))
      _
      _)
    (alt
      _
      ((ref `ext_fun`))
      _
      _)
    (alt
      _
      ((ref `ext_sub`))
      _
      _)
    (alt
      _
      ((ref `zig`))
      _
      _)
    (alt
      _
      ((lit `":"`)
        (ref `name`)
        (ref `stmt`))
      (node
        `labeled`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `simple`))
      _
      _)
    (alt
      _
      ((ref `guarded`)
        (tok `POST_IF`)
        (ref `value`))
      (node
        `if`
        (pos `3`)
        (pos `1`))
      _))
  (rule
    (name `guarded`)
    (alt
      _
      ((ref `simple`))
      (node
        `block`
        (pos `1`))
      _))
  (rule
    (name `simple`)
    (alt
      _
      ((ref `tail`))
      _
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `3`))
      _)
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
        (pos `5`))
      _)
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
        (pos `5`))
      _)
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
        (pos `4`))
      _)
    (alt
      _
      ((tok `DROP_STMT`)
        (ref `name`))
      (node
        `drop`
        (pos `2`))
      _)
    (alt
      _
      ((tok `RETURN`)
        (ref `tail`))
      (node
        `return`
        (pos `2`))
      _)
    (alt
      _
      ((tok `RETURN`))
      (node `return`)
      _)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (ref `tail`))
      (node
        `break`
        (pos `4`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`))
      (node
        `break`
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `BREAK`)
        (ref `tail`))
      (node
        `break`
        (pos `2`))
      _)
    (alt
      _
      ((tok `BREAK`))
      (node `break`)
      _)
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`))
      (node
        `continue`
        (pos `3`))
      _)
    (alt
      _
      ((tok `CONTINUE`))
      (node `continue`)
      _)
    (alt
      _
      ((tok `DEFER`)
        (ref `block`))
      (node
        `defer`
        (pos `2`))
      _)
    (alt
      _
      ((tok `DEFER`)
        (ref `simple`))
      (node
        `defer`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `block`))
      (node
        `errdefer`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ERRDEFER`)
        (ref `simple`))
      (node
        `errdefer`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PRE`)
        (ref `block`))
      (node
        `pre_block`
        (pos `2`))
      _)
    (alt
      _
      ((tok `RAW`)
        (ref `block`))
      (node
        `raw_block`
        (pos `2`))
      _))
  (rule
    (name `decl`)
    (alt
      _
      ((ref `defn`))
      _
      _)
    (alt
      _
      ((tok `PUB`)
        (ref `defn`))
      (node
        `pub`
        (pos `2`))
      _))
  (rule
    (name `defn`)
    (alt
      _
      ((ref `fun`))
      _
      _)
    (alt
      _
      ((ref `sub`))
      _
      _)
    (alt
      _
      ((ref `enum`))
      _
      _)
    (alt
      _
      ((ref `struct`))
      _
      _)
    (alt
      _
      ((ref `errors`))
      _
      _)
    (alt
      _
      ((ref `typedef`))
      _
      _)
    (alt
      _
      ((ref `test`))
      _
      _))
  (rule
    (name `use`)
    (alt
      _
      ((tok `USE`)
        (ref `name`))
      (node
        `use`
        (pos `2`))
      _))
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
        (pos `5`))
      _)
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
        (pos `4`))
      _)
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
        (pos `4`))
      _)
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
        (pos `3`))
      _))
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
        (pos `4`))
      _)
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
        (pos `3`))
      _))
  (rule
    (name `returns`)
    (alt
      _
      ((lit `"->"`)
        (ref `type`))
      (pos `2`)
      _))
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
        (spread `2`))
      _)
    (alt
      _
      ((ref `lparen`)
        (lit `")"`))
      (list)
      _))
  (rule
    (name `lparen`)
    (alt
      _
      ((tok `LPAREN_CALL`))
      _
      _)
    (alt
      _
      ((lit `"("`))
      _
      _))
  (rule
    (name `field`)
    (alt
      _
      ((ref `fname`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`))
      (node
        `:`
        (pos `1`)
        (pos `3`))
      _)
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
        (pos `5`))
      _)
    (alt
      _
      ((tok `PRE`)
        (ref `fname`)
        (lit `":"`)
        (ref `type`))
      (node
        `pre_param`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `fname`))
      (node
        `read`
        (pos `2`))
      _)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `fname`))
      (node
        `write`
        (pos `2`))
      _))
  (rule
    (name `fname`)
    (alt
      _
      ((ref `name`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `KWARG_NAME`))
      (pos `1`)
      _))
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
        (spread `4`))
      _)
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
        (spread `5`))
      _))
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
        (spread `4`))
      _))
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
        (spread `4`))
      _))
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
        (pos `4`))
      _)
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
        (spread `5`))
      _)
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
        (spread `4`))
      _))
  (rule
    (name `members`)
    (alt
      _
      ((ref `member`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `members`)
        (tok `NEWLINE`)
        (ref `member`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `members`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `member`)
    (alt
      _
      ((ref `field`))
      _
      _)
    (alt
      _
      ((ref `name`)
        (lit `"="`)
        (ref `expr`))
      (node
        `valued`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `name`)
        (ref `params`))
      (node
        `variant`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `fun`))
      _
      _)
    (alt
      _
      ((ref `sub`))
      _
      _)
    (alt
      _
      ((tok `DROP`)
        (ref `dparams`)
        (ref `block`))
      (node
        `drop_decl`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `dparams`)
    (alt
      _
      ((list_req
          `L`
          (plain `field`)))
      (list
        (spread `1`))
      _))
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
        (pos `3`))
      _))
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
        (pos `4`))
      _))
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
        (pos `5`))
      _)
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
        (pos `4`))
      _)
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
        (null))
      _)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (ref `name`))
      (node
        `extern_fun`
        (pos `3`)
        (null)
        (null))
      _))
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
        (pos `4`))
      _)
    (alt
      _
      ((tok `EXTERN`)
        (tok `SUB`)
        (ref `name`))
      (node
        `extern_sub`
        (pos `3`)
        (null))
      _))
  (rule
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_DQ`))
      (node
        `zig`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_SQ`))
      (node
        `zig`
        (pos `2`))
      _))
  (rule
    (name `type`)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `type`))
      (node
        `borrow_read`
        (pos `2`))
      _)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `type`))
      (node
        `borrow_write`
        (pos `2`))
      _)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `type`))
      (node
        `shared`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `type`))
      (node
        `weak`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `type`))
      (node
        `slice`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `INTEGER`)
        (lit `"]"`)
        (ref `type`))
      (node
        `array_type`
        (pos `2`)
        (pos `4`))
      _)
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
        (pos `5`))
      _)
    (alt
      _
      ((tok `FUN`)
        (lit `"("`)
        (lit `")"`)
        (ref `type`))
      (node
        `fun_type`
        (null)
        (pos `4`))
      _)
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
        (pos `3`))
      _)
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (lit `")"`))
      (node `fun_type`)
      _)
    (alt
      _
      ((ref `tsuffix`))
      _
      _))
  (rule
    (name `tsuffix`)
    (alt
      _
      ((ref `tsuffix`)
        (tok `SUFFIX_Q`))
      (node
        `optional`
        (pos `1`))
      _)
    (alt
      _
      ((ref `tsuffix`)
        (tok `SUFFIX_BANG`))
      (node
        `error_union`
        (pos `1`))
      _)
    (alt
      _
      ((ref `tatom`))
      _
      _))
  (rule
    (name `tatom`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((ref `name`)
        (lit `"."`)
        (ref `name`))
      (node
        `member`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `TYPE`))
      (pos `1`)
      _)
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
        (spread `3`))
      _)
    (alt
      _
      ((ref `name`)
        (tok `LPAREN_CALL`)
        (lit `")"`))
      (node
        `generic_inst`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `type`)
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `tail`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `cmd`))
      _
      _)
    (alt
      _
      ((ref `cclosure`))
      _
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `value`))
      _
      _)
    (alt
      _
      ((ref `if`))
      _
      _)
    (alt
      _
      ((ref `while`))
      _
      _)
    (alt
      _
      ((ref `for`))
      _
      _)
    (alt
      _
      ((ref `match`))
      _
      _)
    (alt
      _
      ((ref `try_block`))
      _
      _)
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
        (pos `6`))
      _)
    (alt
      _
      ((ref `closure`))
      _
      _)
    (alt
      _
      ((tok `PRE`)
        (ref `value`))
      (node
        `pre`
        (pos `2`))
      _))
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
        (pos `5`))
      _)
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
        (pos `6`))
      _)
    (alt
      _
      ((ref `logic`)
        (tok `CATCH`)
        (ref `value`))
      (node
        `catch`
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((ref `logic`))
      _
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((ref `conj`))
      _
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((ref `neg`))
      _
      _))
  (rule
    (name `neg`)
    (alt
      _
      ((tok `NOT`)
        (ref `neg`))
      (node
        `not`
        (pos `2`))
      _)
    (alt
      _
      ((at_ref `infix`))
      _
      _))
  (rule
    (name `cond`)
    (alt
      _
      ((ref `value`))
      _
      _)
    (alt
      _
      ((ref `cmd`))
      _
      _))
  (rule
    (name `cmd`)
    (alt
      _
      ((ref `postfix`)
        (ref `cmdargs`))
      (node
        `call`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `cmdargs`)
    (alt
      _
      ((ref `exprs`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `exprs`)
        (lit `","`)
        (ref `cmdtail`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `cmdtail`))
      (list
        (pos `1`))
      _))
  (rule
    (name `exprs`)
    (alt
      _
      ((ref `expr`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `exprs`)
        (lit `","`)
        (ref `expr`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `cmdtail`)
    (alt
      _
      ((ref `cmd`))
      _
      _)
    (alt
      _
      ((ref `cclosure`))
      _
      _))
  (rule
    (name `ifcond`)
    (alt
      _
      ((ref `cond`))
      _
      _)
    (alt
      _
      ((ref `value`)
        (tok `AS`)
        (ref `name`))
      (node
        `as`
        (pos `1`)
        (pos `3`))
      _))
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
        (pos `5`))
      _)
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
        (pos `5`))
      _)
    (alt
      _
      ((tok `IF`)
        (ref `ifcond`)
        (ref `block`))
      (node
        `if`
        (pos `2`)
        (pos `3`))
      _))
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
          (pos `5`)))
      _)
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
          (pos `7`)))
      _)
    (alt
      _
      ((tok `WHILE`)
        (ref `ifcond`)
        (ref `block`))
      (node
        `while`
        (pos `2`)
        (null)
        (pos `3`))
      _)
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
        (pos `5`))
      _))
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
          (pos `8`)))
      _)
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
          (pos `10`)))
      _)
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
          (pos `7`)))
      _)
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
          (pos `9`)))
      _)
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
        (pos `6`))
      _)
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
        (pos `8`))
      _)
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
        (pos `5`))
      _)
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
        (pos `7`))
      _))
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
        (spread `4`))
      _))
  (rule
    (name `arms`)
    (alt
      _
      ((ref `arm`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `arms`)
        (tok `NEWLINE`)
        (ref `arm`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `arms`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((ref `pattern`)
        (ref `block`))
      (node
        `arm`
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `pattern`)
    (alt
      _
      ((ref `patatom`))
      _
      _)
    (alt
      _
      ((ref `patatom`)
        (lit `".."`)
        (ref `patatom`))
      (node
        `range_pattern`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `patatom`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((tok `ELSE`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (tok `INTEGER`))
      (node
        `neg`
        (pos `2`))
      _)
    (alt
      _
      ((tok `REAL`))
      _
      _)
    (alt
      _
      ((tok `STRING_SQ`))
      _
      _)
    (alt
      _
      ((tok `STRING_DQ`))
      _
      _)
    (alt
      _
      ((tok `TRUE`))
      _
      _)
    (alt
      _
      ((tok `FALSE`))
      _
      _)
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`))
      (node
        `enum_lit`
        (pos `2`))
      _)
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
        (spread `4`))
      _)
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`)
        (tok `LPAREN_CALL`)
        (lit `")"`))
      (node
        `variant_pattern`
        (pos `2`))
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((tok `TRY`)
        (ref `block`))
      (node
        `try_block`
        (pos `2`))
      _))
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
        (pos `5`))
      _))
  (rule
    (name `closure`)
    (alt
      _
      ((ref `lambda`))
      _
      _)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `lambda`))
      (node
        `share`
        (pos `2`))
      _))
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
        (pos `2`))
      _)
    (alt
      _
      ((ref `bars`)
        (ref `ebody`))
      (node
        `lambda`
        (pos `1`)
        (null)
        (null)
        (pos `2`))
      _))
  (rule
    (name `cclosure`)
    (alt
      _
      ((ref `clambda`))
      _
      _)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `clambda`))
      (node
        `share`
        (pos `2`))
      _))
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
        (pos `2`))
      _))
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
        (spread `2`))
      _)
    (alt
      _
      ((tok `BAR_EMPTY`))
      (list)
      _))
  (rule
    (name `barent`)
    (alt
      _
      ((ref `fname`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `fname`)
        (lit `":"`)
        (ref `type`))
      (node
        `:`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `name`))
      (node
        `cap_clone`
        (pos `2`))
      _)
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `name`))
      (node
        `cap_move`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `name`))
      (node
        `cap_weak`
        (pos `2`))
      _))
  (rule
    (name `ebody`)
    (alt
      _
      ((ref `expr`))
      (node
        `block`
        (pos `1`))
      _))
  (rule
    (name `cbody`)
    (alt
      _
      ((ref `cmd`))
      (node
        `block`
        (pos `1`))
      _))
  (rule
    (name `unary`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `unary`))
      (node
        `neg`
        (pos `2`))
      _)
    (alt
      _
      ((tok `MOVE_PFX`)
        (ref `unary`))
      (node
        `move`
        (pos `2`))
      _)
    (alt
      _
      ((tok `CLONE_PFX`)
        (ref `unary`))
      (node
        `clone`
        (pos `2`))
      _)
    (alt
      _
      ((tok `READ_PFX`)
        (ref `unary`))
      (node
        `read`
        (pos `2`))
      _)
    (alt
      _
      ((tok `WRITE_PFX`)
        (ref `unary`))
      (node
        `write`
        (pos `2`))
      _)
    (alt
      _
      ((tok `SHARE_PFX`)
        (ref `unary`))
      (node
        `share`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `unary`))
      (node
        `weak`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PIN_PFX`)
        (ref `unary`))
      (node
        `pin`
        (pos `2`))
      _)
    (alt
      _
      ((ref `postfix`))
      _
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((ref `postfix`)
        (tok `LBRACKET_INDEX`)
        (ref `expr`)
        (lit `"]"`))
      (node
        `index`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `postfix`)
        (tok `LPAREN_CALL`)
        (ref `args`)
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `postfix`)
        (tok `SUFFIX_BANG`))
      (node
        `propagate`
        (pos `1`))
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
      ((ref `callargs`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `cmdtail`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `cmdtail`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `callargs`)
    (alt
      _
      ((ref `callarg`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `callarg`))
      (list
        (spread `1`)
        (pos `3`))
      _))
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
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`))
      _
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
      ((tok `REAL`))
      _
      _)
    (alt
      _
      ((tok `STRING_SQ`))
      _
      _)
    (alt
      _
      ((tok `STRING_DQ`))
      _
      _)
    (alt
      _
      ((tok `TRUE`))
      _
      _)
    (alt
      _
      ((tok `FALSE`))
      _
      _)
    (alt
      _
      ((tok `DOT_LIT`)
        (ref `name`))
      (node
        `enum_lit`
        (pos `2`))
      _)
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
        (spread `4`))
      _)
    (alt
      _
      ((lit `"["`)
        (ref `elems`)
        (lit `"]"`))
      (node
        `array`
        (spread `2`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `tail`)
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `elems`)
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
