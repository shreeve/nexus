(grammar
  (conflicts `19`)
  (as
    `ident`
    _
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
      (node
        `labeled`
        (pos `2`)
        (pos `3`)))
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
      (node
        `extern_const`
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `EXTERN`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      (node
        `extern_var`
        (pos `2`)
        (pos `4`))))
  (rule
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_SQ`))
      (node
        `zig`
        (pos `2`)))
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_DQ`))
      (node
        `zig`
        (pos `2`))))
  (rule
    (name `decl`)
    (alt
      _
      ((ref `defn`)))
    (alt
      _
      ((tok `PUB`)
        (ref `decl`))
      (node
        `pub`
        (pos `2`)))
    (alt
      _
      ((tok `EXTERN`)
        (ref `decl`))
      (node
        `extern`
        (pos `2`)))
    (alt
      _
      ((tok `EXPORT`)
        (ref `decl`))
      (node
        `export`
        (pos `2`)))
    (alt
      _
      ((tok `PACKED`)
        (ref `decl`))
      (node
        `packed`
        (pos `2`)))
    (alt
      _
      ((tok `CALLCONV`)
        (ref `name`)
        (ref `decl`))
      (node
        `callconv`
        (pos `2`)
        (pos `3`))))
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
      (node
        `block`
        (spread `2`)))
    (alt
      _
      ((tok `INDENT`)
        (tok `OUTDENT`))
      (node `block`)))
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
    (name `use`)
    (alt
      _
      ((tok `USE`)
        (ref `name`))
      (node
        `use`
        (pos `2`))))
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
        (pos `4`))))
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
    (name `opaq`)
    (alt
      _
      ((tok `OPAQUE`)
        (ref `name`))
      (node
        `opaque`
        (pos `2`))))
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
        (spread `4`))))
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
      (node
        `comptime_param`
        (pos `2`)
        (pos `4`)))
    (alt
      _
      ((ref `name`))
      (pos `1`))
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`))
      (node
        `:`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (tok `ALIGN`)
        (ref `atom`))
      (node
        `aligned`
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      (node
        `default`
        (pos `1`)
        (pos `3`)
        (pos `5`))))
  (rule
    (name `params`)
    (alt
      _
      ((list_req
          `L`
          (plain `field`)))
      (list
        (spread `1`))))
  (rule
    (name `returns`)
    (alt
      _
      ((lit `"->"`)
        (ref `type`))
      (pos `2`)))
  (rule
    (name `type`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((lit `"!"`)
        (ref `type`))
      (node
        `error_union`
        (pos `2`)))
    (alt
      _
      ((lit `"?"`)
        (ref `type`))
      (node
        `?`
        (pos `2`)))
    (alt
      _
      ((lit `"*"`)
        (ref `type`))
      (node
        `ptr`
        (pos `2`)))
    (alt
      _
      ((lit `"*"`)
        (tok `CONST`)
        (ref `type`))
      (node
        `const_ptr`
        (pos `3`)))
    (alt
      _
      ((lit `"*"`)
        (tok `VOLATILE`)
        (ref `type`))
      (node
        `volatile_ptr`
        (pos `3`)))
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
        (lit `":"`)
        (ref `atom`)
        (lit `"]"`)
        (ref `type`))
      (node
        `sentinel_slice`
        (pos `3`)
        (pos `5`)))
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
      ((lit `"["`)
        (lit `"*"`)
        (lit `"]"`)
        (ref `type`))
      (node
        `many_ptr`
        (pos `4`)))
    (alt
      _
      ((lit `"["`)
        (lit `"*"`)
        (lit `":"`)
        (ref `atom`)
        (lit `"]"`)
        (ref `type`))
      (node
        `sentinel_ptr`
        (pos `4`)
        (pos `6`)))
    (alt
      _
      ((tok `FN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `type`))
        (lit `")"`)
        (ref `type`))
      (node
        `fn_type`
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((tok `FN`)
        (lit `"("`)
        (lit `")"`)
        (ref `type`))
      (node
        `fn_type`
        (null)
        (pos `4`))))
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
      (node
        `as`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `expr`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`))
      (node
        `as`
        (pos `1`)
        (pos `3`))))
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
      (node
        `if`
        (pos `2`)
        (pos `3`)
        (pos `6`)
        (pos `7`)))
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
        (ref `block`)
        (tok `ELSE`)
        (tok `AS`)
        (ref `name`)
        (ref `if`))
      (node
        `if`
        (pos `2`)
        (pos `3`)
        (pos `6`)
        (pos `7`)))
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
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
        (ref `cond`)
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
        (ref `cond`)
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
        (ref `cond`)
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
        (ref `cond`)
        (lit `":"`)
        (ref `expr`)
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
        (ref `cond`)
        (ref `block`))
      (node
        `while`
        (pos `2`)
        (null)
        (pos `3`)))
    (alt
      _
      ((tok `WHILE`)
        (ref `cond`)
        (lit `":"`)
        (ref `expr`)
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
        (lit `"*"`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `for_ptr`
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
        (lit `"*"`)
        (ref `name`)
        (lit `","`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `for_ptr`
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
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `for`
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
        (ref `expr`)
        (ref `block`)
        (tok `ELSE`)
        (ref `block`))
      (node
        `for`
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
        (lit `"*"`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      (node
        `for_ptr`
        (pos `3`)
        (null)
        (pos `5`)
        (pos `6`)))
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
      (node
        `for_ptr`
        (pos `3`)
        (pos `5`)
        (pos `7`)
        (pos `8`)))
    (alt
      _
      ((tok `FOR`)
        (ref `name`)
        (tok `IN`)
        (ref `expr`)
        (ref `block`))
      (node
        `for`
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
        (ref `expr`)
        (ref `block`))
      (node
        `for`
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (pos `7`))))
  (rule
    (name `match`)
    (alt
      _
      ((tok `MATCH`)
        (ref `expr`)
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
    (name `patatom`)
    (alt
      _
      ((ref `atom`)))
    (alt
      _
      ((lit `"."`)
        (ref `name`))
      (node
        `enum_pattern`
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
    (name `arm`)
    (alt
      _
      ((ref `pattern`)
        (tok `AS`)
        (ref `name`)
        (lit `"=>"`)
        (ref `expr`))
      (node
        `arm`
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((ref `pattern`)
        (tok `AS`)
        (ref `name`)
        (ref `block`))
      (node
        `arm`
        (pos `1`)
        (pos `3`)
        (pos `4`)))
    (alt
      _
      ((ref `pattern`)
        (lit `"=>"`)
        (ref `expr`))
      (node
        `arm`
        (pos `1`)
        (null)
        (pos `3`)))
    (alt
      _
      ((ref `pattern`)
        (ref `block`))
      (node
        `arm`
        (pos `1`)
        (null)
        (pos `2`))))
  (rule
    (name `postif`)
    (alt
      _
      ((at_ref `infix`)
        (tok `IF`)
        (ref `expr`)
        (tok `ELSE`)
        (ref `expr`))
      (node
        `ternary`
        (pos `3`)
        (pos `1`)
        (pos `5`)))
    (alt
      _
      ((at_ref `infix`)
        (tok `IF`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `1`)))
    (alt
      _
      ((at_ref `infix`)
        (tok `TERNARY_IF`)
        (ref `expr`)
        (tok `ELSE`)
        (ref `expr`))
      (node
        `ternary`
        (pos `3`)
        (pos `1`)
        (pos `5`))))
  (rule
    (name `coalesce`)
    (alt
      _
      ((at_ref `infix`)
        (lit `"??"`)
        (ref `expr`))
      (node
        `??`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `catch`)
    (alt
      _
      ((at_ref `infix`)
        (tok `CATCH`)
        (tok `AS`)
        (ref `name`)
        (ref `expr`))
      (node
        `catch`
        (pos `1`)
        (pos `4`)
        (pos `5`)))
    (alt
      _
      ((at_ref `infix`)
        (tok `CATCH`)
        (ref `expr`))
      (node
        `catch`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `return`)
    (alt
      _
      ((tok `RETURN`)
        (ref `expr`)
        (tok `POST_IF`)
        (ref `expr`))
      (node
        `return`
        (named
          `value`
          (pos `2`))
        (named
          `if`
          (pos `4`))))
    (alt
      _
      ((tok `RETURN`)
        (tok `POST_IF`)
        (ref `expr`))
      (node
        `return`
        (named
          `value`
          (null))
        (named
          `if`
          (pos `3`))))
    (alt
      _
      ((tok `RETURN`)
        (ref `expr`))
      (node
        `return`
        (named
          `value`
          (pos `2`))))
    (alt
      _
      ((tok `RETURN`))
      (node `return`)))
  (rule
    (name `break`)
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (tok `POST_IF`)
        (ref `expr`))
      (node
        `break`
        (named
          `value`
          (null))
        (named
          `to`
          (pos `3`))
        (named
          `if`
          (pos `5`))))
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`)
        (ref `expr`))
      (node
        `break`
        (named
          `value`
          (pos `4`))
        (named
          `to`
          (pos `3`))))
    (alt
      _
      ((tok `BREAK`)
        (lit `":"`)
        (ref `name`))
      (node
        `break`
        (named
          `value`
          (null))
        (named
          `to`
          (pos `3`))))
    (alt
      _
      ((tok `BREAK`)
        (tok `POST_IF`)
        (ref `expr`))
      (node
        `break`
        (named
          `value`
          (null))
        (named
          `to`
          (null))
        (named
          `if`
          (pos `3`))))
    (alt
      _
      ((tok `BREAK`)
        (ref `expr`))
      (node
        `break`
        (named
          `value`
          (pos `2`))))
    (alt
      _
      ((tok `BREAK`))
      (node `break`)))
  (rule
    (name `continue`)
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`)
        (tok `POST_IF`)
        (ref `expr`))
      (node
        `continue`
        (named
          `to`
          (pos `3`))
        (named
          `if`
          (pos `5`))))
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`))
      (node
        `continue`
        (named
          `to`
          (pos `3`))))
    (alt
      _
      ((tok `CONTINUE`)
        (tok `POST_IF`)
        (ref `expr`))
      (node
        `continue`
        (named
          `to`
          (null))
        (named
          `if`
          (pos `3`))))
    (alt
      _
      ((tok `CONTINUE`))
      (node `continue`)))
  (rule
    (name `defer`)
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
        (ref `expr`))
      (node
        `defer`
        (pos `2`))))
  (rule
    (name `errdefer`)
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
        (ref `expr`))
      (node
        `errdefer`
        (pos `2`))))
  (rule
    (name `comptime`)
    (alt
      _
      ((tok `COMPTIME`)
        (ref `expr`))
      (node
        `comptime`
        (pos `2`))))
  (rule
    (name `inline`)
    (alt
      _
      ((tok `INLINE`)
        (ref `expr`))
      (node
        `inline`
        (pos `2`))))
  (rule
    (name `assign`)
    (alt
      _
      ((ref `call`)
        (lit `":"`)
        (ref `type`)
        (lit `"="`)
        (ref `expr`))
      (node
        `typed_assign`
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((ref `call`)
        (lit `"="`)
        (ref `expr`))
      (node
        `=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (lit `"+="`)
        (ref `expr`))
      (node
        `+=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (lit `"-="`)
        (ref `expr`))
      (node
        `-=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (lit `"*="`)
        (ref `expr`))
      (node
        `*=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (lit `"/="`)
        (ref `expr`))
      (node
        `/=`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `const`)
    (alt
      _
      ((ref `call`)
        (lit `":"`)
        (ref `type`)
        (lit `"=!"`)
        (ref `expr`))
      (node
        `typed_const`
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((ref `call`)
        (lit `"=!"`)
        (ref `expr`))
      (node
        `const`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"!"`)
        (ref `unary`))
      (node
        `not`
        (pos `2`)))
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `unary`))
      (node
        `neg`
        (pos `2`)))
    (alt
      _
      ((tok `TRY`)
        (ref `unary`))
      (node
        `try`
        (pos `2`)))
    (alt
      _
      ((lit `"&"`)
        (ref `unary`))
      (node
        `addr_of`
        (pos `2`)))
    (alt
      _
      ((lit `"~"`)
        (ref `unary`))
      (node
        `bit_not`
        (pos `2`)))
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
      (node
        `deref`
        (pos `1`)))
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (ref `name`))
      (node
        `.`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (ref `expr`)
        (lit `"]"`))
      (node
        `index`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (list_req
          `L`
          (plain `arg`)))
      (node
        `call`
        (pos `1`)
        (spread `2`)))
    (alt
      _
      ((ref `call`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`)))
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
      (list
        (spread `1`)))
    (alt
      _
      ()
      (list)))
  (rule
    (name `arg`)
    (alt
      _
      ((ref `term`)
        (tok `TERNARY_IF`)
        (ref `expr`)
        (tok `ELSE`)
        (ref `arg`))
      (node
        `ternary`
        (pos `3`)
        (pos `1`)
        (pos `5`)))
    (alt
      _
      ((ref `term`))))
  (rule
    (name `term`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `term`))
      (node
        `neg`
        (pos `2`)))
    (alt
      _
      ((lit `"!"`)
        (ref `term`))
      (node
        `not`
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
      (node `null`))
    (alt
      _
      ((tok `UNREACHABLE`))
      (node `unreachable`))
    (alt
      _
      ((tok `UNDEFINED`))
      (node `undefined`))
    (alt
      _
      ((lit `"?"`)
        (ref `atom`))
      (node
        `?`
        (pos `2`)))
    (alt
      _
      ((lit `"@"`)
        (ref `name`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      (node
        `builtin`
        (pos `2`)
        (spread `4`)))
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
      (node
        `array`
        (spread `2`)))
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`))
    (alt
      _
      ((tok `DOT_LBRACE`)
        (list_req
          `L`
          (plain `dotpair`))
        (lit `"}"`))
      (node
        `anon_init`
        (spread `2`)))
    (alt
      _
      ((tok `DOT_LBRACE`)
        (ref `args`)
        (lit `"}"`))
      (node
        `anon_init`
        (spread `2`)))
    (alt
      _
      ((tok `DOT_LBRACE`)
        (lit `"}"`))
      (node `anon_init`)))
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
      (node
        `record`
        (pos `1`)
        (spread `3`))))
  (rule
    (name `pair`)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `expr`))
      (node
        `pair`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `dotpair`)
    (alt
      _
      ((lit `"."`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      (node
        `pair`
        (pos `2`)
        (pos `4`))))
  (rule
    (name `lambda`)
    (alt
      _
      ((tok `FN`)
        (ref `params`)
        (ref `block`))
      (node
        `lambda`
        (pos `2`)
        (named
          `returns`
          (null))
        (pos `3`)))
    (alt
      _
      ((tok `FN`)
        (ref `block`))
      (node
        `lambda`
        (named
          `params`
          (null))
        (named
          `returns`
          (null))
        (pos `2`))))
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
