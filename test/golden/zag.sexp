(grammar
  (lang `"zag"`)
  (section `lexer`)
  (state
    `state`
    (assign `beg` `1`)
    (assign `paren` `0`)
    (assign `brace` `0`))
  (after
    `after`
    (assign `beg` `0`))
  (tokens `tokens` `ident` `integer` `real` `string_sq` `string_dq` `true` `false` `plus` `minus` `minus_prefix` `star` `slash` `percent` `power` `eq` `ne` `lt` `gt` `le` `ge` `and_sym` `or_sym` `not_sym` `question` `nullish` `bar` `ampersand` `caret` `tilde` `lshift` `rshift` `at` `assign` `const_assign` `plus_assign` `minus_assign` `star_assign` `slash_assign` `lparen` `rparen` `lbrace` `rbrace` `lbracket` `rbracket` `comma` `colon` `arrow` `fat_arrow` `dot` `dotdot` `pipe` `indent` `outdent` `newline` `post_if` `ternary_if` `dot_lbrace` `bar_capture` `comment` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `"\\\\\\n"` _ `skip`)
  (lex_rule
    `"\\r\\n"`
    _
    `newline`
    (set_action `beg` `1`))
  (lex_rule
    `'\\n'`
    _
    `newline`
    (set_action `beg` `1`))
  (lex_rule
    `'\\r'`
    _
    `newline`
    (set_action `beg` `1`))
  (lex_rule `'"' ([^"\\\\$\\n] | '\\\\' . | '$')* '"'` _ `string_dq`)
  (lex_rule `"'" ([^'\\n] | "''")* "'"` _ `string_sq`)
  (lex_rule `'0' [xX] [0-9a-fA-F]+` _ `integer`)
  (lex_rule `'0' [bB] [01]+` _ `integer`)
  (lex_rule `'0' [oO] [0-7]+` _ `integer`)
  (lex_rule `[0-9]* '.' [0-9]+` _ `real`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `"**"` _ `power`)
  (lex_rule `"=="` _ `eq`)
  (lex_rule `"!="` _ `ne`)
  (lex_rule `"<="` _ `le`)
  (lex_rule `">="` _ `ge`)
  (lex_rule `"&&"` _ `and_sym`)
  (lex_rule `"||"` _ `or_sym`)
  (lex_rule `"=!"` _ `const_assign`)
  (lex_rule `"+="` _ `plus_assign`)
  (lex_rule `"-="` _ `minus_assign`)
  (lex_rule `"*="` _ `star_assign`)
  (lex_rule `"/="` _ `slash_assign`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule `"=>"` _ `fat_arrow`)
  (lex_rule `"|>"` _ `pipe`)
  (lex_rule `"??"` _ `nullish`)
  (lex_rule `".."` _ `dotdot`)
  (lex_rule `"<<"` _ `lshift`)
  (lex_rule `">>"` _ `rshift`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'/'` _ `slash`)
  (lex_rule `'%'` _ `percent`)
  (lex_rule `'<'` _ `lt`)
  (lex_rule `'>'` _ `gt`)
  (lex_rule `'!'` _ `not_sym`)
  (lex_rule `'?'` _ `question`)
  (lex_rule `'|'` _ `bar`)
  (lex_rule `'&'` _ `ampersand`)
  (lex_rule `'^'` _ `caret`)
  (lex_rule `'~'` _ `tilde`)
  (lex_rule `'@'` _ `at`)
  (lex_rule `'='` _ `assign`)
  (lex_rule
    `'('`
    _
    `lparen`
    (step_action `paren` `++`))
  (lex_rule
    `')'`
    _
    `rparen`
    (step_action `paren` `--`))
  (lex_rule
    `'{'`
    _
    `lbrace`
    (step_action `brace` `++`))
  (lex_rule
    `'}'`
    _
    `rbrace`
    (step_action `brace` `--`))
  (lex_rule `'['` _ `lbracket`)
  (lex_rule `']'` _ `rbracket`)
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]* '?'?` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (manifest
    (conflict `shift` `if → IF cond block` _ `1` `# dangling else: ELSE binds to the nearest if`)
    (conflict `shift` `while → WHILE cond block` _ `1` `# ELSE binds to the nearest while`)
    (conflict `shift` `while → WHILE cond ":" expr block` _ `1` `# ELSE binds to the nearest while`)
    (conflict `shift` `for → FOR "*" IDENT IN expr block` _ `1` `# ELSE binds to the nearest for`)
    (conflict `shift` `for → FOR "*" IDENT "," IDENT IN expr block` _ `1` `# ELSE binds to the nearest for`)
    (conflict `shift` `for → FOR IDENT IN expr block` _ `1` `# ELSE binds to the nearest for`)
    (conflict `shift` `for → FOR IDENT "," IDENT IN expr block` _ `1` `# ELSE binds to the nearest for`)
    (conflict `shift` `postif → infix IF expr` _ `1` `# ELSE binds to the nearest postfix if`)
    (conflict `shift` `return → RETURN expr` _ `1` `# a postfix guard binds to the return statement`)
    (conflict `shift` `return → RETURN` _ `1` `# a postfix guard binds to the return statement`)
    (conflict `shift` `break → BREAK ":" IDENT` _ `1` `# a postfix guard binds to the break statement`)
    (conflict `shift` `break → BREAK` _ `2` `# break :label names the loop to break`)
    (conflict `shift` `continue → CONTINUE ":" IDENT` _ `1` `# a postfix guard binds to the continue statement`)
    (conflict `shift` `continue → CONTINUE` _ `2` `# continue :label names the loop to continue`)
    (conflict `shift` `unary → call` _ `1` `# call: starts a typed assignment or constant`)
    (conflict `shift` `args → ε` _ `1` `# .{} is an empty struct literal, not empty call arguments`)
    (conflict `shift` `arg → term` _ `1` `# a ternary if binds to the term before it`))
  (as
    `ident`
    _
    (as_entry _ `keyword` _))
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
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)
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
      ((ref `zig`))
      _
      _)
    (alt
      _
      ((ref `extvar`))
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
      ((ref `expr`))
      _
      _))
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
        (pos `5`))
      _)
    (alt
      _
      ((tok `EXTERN`)
        (ref `name`)
        (lit `":"`)
        (ref `type`))
      (node
        `extern_var`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_SQ`))
      (node
        `zig`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ZIG`)
        (tok `STRING_DQ`))
      (node
        `zig`
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
        (ref `decl`))
      (node
        `pub`
        (pos `2`))
      _)
    (alt
      _
      ((tok `EXTERN`)
        (ref `decl`))
      (node
        `extern`
        (pos `2`))
      _)
    (alt
      _
      ((tok `EXPORT`)
        (ref `decl`))
      (node
        `export`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PACKED`)
        (ref `decl`))
      (node
        `packed`
        (pos `2`))
      _)
    (alt
      _
      ((tok `CALLCONV`)
        (ref `name`)
        (ref `decl`))
      (node
        `callconv`
        (pos `2`)
        (pos `3`))
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
      _)
    (alt
      _
      ((ref `opaq`))
      _
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
    (name `opaq`)
    (alt
      _
      ((tok `OPAQUE`)
        (ref `name`))
      (node
        `opaque`
        (pos `2`))
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
      ((ref `fun`))
      _
      _)
    (alt
      _
      ((ref `sub`))
      _
      _))
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
        (pos `4`))
      _)
    (alt
      _
      ((ref `name`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `name`)
        (lit `":"`)
        (ref `type`))
      (node
        `:`
        (pos `1`)
        (pos `3`))
      _)
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
        (pos `5`))
      _)
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
        (pos `5`))
      _))
  (rule
    (name `params`)
    (alt
      _
      ((list_req
          `L`
          (plain `field`)))
      (list
        (spread `1`))
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
    (name `type`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((lit `"!"`)
        (ref `type`))
      (node
        `error_union`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"?"`)
        (ref `type`))
      (node
        `?`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"*"`)
        (ref `type`))
      (node
        `ptr`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"*"`)
        (tok `CONST`)
        (ref `type`))
      (node
        `const_ptr`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"*"`)
        (tok `VOLATILE`)
        (ref `type`))
      (node
        `volatile_ptr`
        (pos `3`))
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
        (lit `":"`)
        (ref `atom`)
        (lit `"]"`)
        (ref `type`))
      (node
        `sentinel_slice`
        (pos `3`)
        (pos `5`))
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
      ((lit `"["`)
        (lit `"*"`)
        (lit `"]"`)
        (ref `type`))
      (node
        `many_ptr`
        (pos `4`))
      _)
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
        (pos `6`))
      _)
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
        (pos `5`))
      _)
    (alt
      _
      ((tok `FN`)
        (lit `"("`)
        (lit `")"`)
        (ref `type`))
      (node
        `fn_type`
        (null)
        (pos `4`))
      _))
  (rule
    (name `expr`)
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
      ((ref `postif`))
      _
      _)
    (alt
      _
      ((ref `coalesce`))
      _
      _)
    (alt
      _
      ((ref `catch`))
      _
      _)
    (alt
      _
      ((ref `return`))
      _
      _)
    (alt
      _
      ((ref `break`))
      _
      _)
    (alt
      _
      ((ref `continue`))
      _
      _)
    (alt
      _
      ((ref `defer`))
      _
      _)
    (alt
      _
      ((ref `errdefer`))
      _
      _)
    (alt
      _
      ((ref `comptime`))
      _
      _)
    (alt
      _
      ((ref `inline`))
      _
      _)
    (alt
      _
      ((ref `assign`))
      _
      _)
    (alt
      _
      ((ref `const`))
      _
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
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `expr`)
        (tok `AS`)
        (ref `name`))
      (node
        `as`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`)
        (tok `BAR_CAPTURE`)
        (ref `name`)
        (tok `BAR_CAPTURE`))
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
        (pos `7`))
      _)
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
        (pos `7`))
      _)
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
        (pos `5`))
      _)
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
        (pos `5`))
      _)
    (alt
      _
      ((tok `IF`)
        (ref `cond`)
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
          (pos `5`)))
      _)
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
          (pos `7`)))
      _)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond`)
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
        (ref `cond`)
        (lit `":"`)
        (ref `expr`)
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
          (pos `8`)))
      _)
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
          (pos `10`)))
      _)
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
          (pos `7`)))
      _)
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
          (pos `9`)))
      _)
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
        (pos `6`))
      _)
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
        (pos `8`))
      _)
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
        (pos `5`))
      _)
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
        (pos `7`))
      _))
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
    (name `patatom`)
    (alt
      _
      ((ref `atom`))
      _
      _)
    (alt
      _
      ((lit `"."`)
        (ref `name`))
      (node
        `enum_pattern`
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
        (pos `5`))
      _)
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
        (pos `4`))
      _)
    (alt
      _
      ((ref `pattern`)
        (lit `"=>"`)
        (ref `expr`))
      (node
        `arm`
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((ref `pattern`)
        (ref `block`))
      (node
        `arm`
        (pos `1`)
        (null)
        (pos `2`))
      _))
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
        (pos `5`))
      _)
    (alt
      _
      ((at_ref `infix`)
        (tok `IF`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `1`))
      _)
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
        (pos `5`))
      _))
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
        (pos `3`))
      _))
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
        (pos `5`))
      _)
    (alt
      _
      ((at_ref `infix`)
        (tok `CATCH`)
        (ref `expr`))
      (node
        `catch`
        (pos `1`)
        (pos `3`))
      _))
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
          (pos `4`)))
      _)
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
          (pos `3`)))
      _)
    (alt
      _
      ((tok `RETURN`)
        (ref `expr`))
      (node
        `return`
        (named
          `value`
          (pos `2`)))
      _)
    (alt
      _
      ((tok `RETURN`))
      (node `return`)
      _))
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
          (pos `5`)))
      _)
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
          (pos `3`)))
      _)
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
          (pos `3`)))
      _)
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
          (pos `3`)))
      _)
    (alt
      _
      ((tok `BREAK`)
        (ref `expr`))
      (node
        `break`
        (named
          `value`
          (pos `2`)))
      _)
    (alt
      _
      ((tok `BREAK`))
      (node `break`)
      _))
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
          (pos `5`)))
      _)
    (alt
      _
      ((tok `CONTINUE`)
        (lit `":"`)
        (ref `name`))
      (node
        `continue`
        (named
          `to`
          (pos `3`)))
      _)
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
          (pos `3`)))
      _)
    (alt
      _
      ((tok `CONTINUE`))
      (node `continue`)
      _))
  (rule
    (name `defer`)
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
        (ref `expr`))
      (node
        `defer`
        (pos `2`))
      _))
  (rule
    (name `errdefer`)
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
        (ref `expr`))
      (node
        `errdefer`
        (pos `2`))
      _))
  (rule
    (name `comptime`)
    (alt
      _
      ((tok `COMPTIME`)
        (ref `expr`))
      (node
        `comptime`
        (pos `2`))
      _))
  (rule
    (name `inline`)
    (alt
      _
      ((tok `INLINE`)
        (ref `expr`))
      (node
        `inline`
        (pos `2`))
      _))
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
        (pos `5`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"="`)
        (ref `expr`))
      (node
        `=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"+="`)
        (ref `expr`))
      (node
        `+=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"-="`)
        (ref `expr`))
      (node
        `-=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"*="`)
        (ref `expr`))
      (node
        `*=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"/="`)
        (ref `expr`))
      (node
        `/=`
        (pos `1`)
        (pos `3`))
      _))
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
        (pos `5`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"=!"`)
        (ref `expr`))
      (node
        `const`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"!"`)
        (ref `unary`))
      (node
        `not`
        (pos `2`))
      _)
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
      ((tok `TRY`)
        (ref `unary`))
      (node
        `try`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"&"`)
        (ref `unary`))
      (node
        `addr_of`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `unary`))
      (node
        `bit_not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `call`))
      _
      _))
  (rule
    (name `call`)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (lit `"*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (ref `name`))
      (node
        `.`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (ref `expr`)
        (lit `"]"`))
      (node
        `index`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (list_req
          `L`
          (plain `arg`)))
      (node
        `call`
        (pos `1`)
        (spread `2`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"("`)
        (ref `args`)
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
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
        (pos `5`))
      _)
    (alt
      _
      ((ref `term`))
      _
      _))
  (rule
    (name `term`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (ref `term`))
      (node
        `neg`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"!"`)
        (ref `term`))
      (node
        `not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `atom`))
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
      ((tok `NULL`))
      (node `null`)
      _)
    (alt
      _
      ((tok `UNREACHABLE`))
      (node `unreachable`)
      _)
    (alt
      _
      ((tok `UNDEFINED`))
      (node `undefined`)
      _)
    (alt
      _
      ((lit `"?"`)
        (ref `atom`))
      (node
        `?`
        (pos `2`))
      _)
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
        (spread `4`))
      _)
    (alt
      _
      ((ref `record`))
      _
      _)
    (alt
      _
      ((ref `lambda`))
      _
      _)
    (alt
      _
      ((lit `"["`)
        (ref `args`)
        (lit `"]"`))
      (node
        `array`
        (spread `2`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((tok `DOT_LBRACE`)
        (list_req
          `L`
          (plain `dotpair`))
        (lit `"}"`))
      (node
        `anon_init`
        (spread `2`))
      _)
    (alt
      _
      ((tok `DOT_LBRACE`)
        (ref `args`)
        (lit `"}"`))
      (node
        `anon_init`
        (spread `2`))
      _)
    (alt
      _
      ((tok `DOT_LBRACE`)
        (lit `"}"`))
      (node `anon_init`)
      _))
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
        (spread `3`))
      _))
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
        (pos `3`))
      _))
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
        (pos `4`))
      _))
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
        (pos `3`))
      _)
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
        (pos `2`))
      _))
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
