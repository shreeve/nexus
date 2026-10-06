(grammar
  (lang `"rig"`)
  (section `lexer`)
  (tokens `tokens` `ident` `integer` `real` `string_sq` `string_dq` `true` `false` `and` `as` `break` `catch` `continue` `defer` `drop` `else` `enum` `errdefer` `error` `extern` `for` `fun` `if` `in` `match` `new` `not` `or` `pass` `pub` `raw` `return` `struct` `sub` `test` `try` `type` `use` `while` `zig` `async` `await` `const` `impl` `trait` `when` `where` `yield` `plus` `minus` `star` `slash` `percent` `plus_wrap` `minus_wrap` `star_wrap` `power` `eq` `ne` `lt` `gt` `le` `ge` `and_sym` `or_sym` `not_sym` `question` `nullish` `bar` `ampersand` `caret` `tilde` `lshift` `rshift` `at` `assign` `fixed_assign` `plus_assign` `minus_assign` `star_assign` `slash_assign` `percent_assign` `amp_assign` `bar_assign` `caret_assign` `lshift_assign` `rshift_assign` `plus_wrap_assign` `minus_wrap_assign` `star_wrap_assign` `lparen` `rparen` `lbracket` `rbracket` `comma` `colon` `arrow` `fat_arrow` `dot` `dotdot` `indent` `outdent` `newline` `post_if` `ternary_if` `bar_capture` `bar_empty` `kwarg_name` `drop_stmt` `of` `unique` `from` `static` `dotdot_open` `nullish_jump` `step_colon` `comment` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `"\\\\\\n"` _ `skip`)
  (lex_rule `"\\\\\\r\\n"` _ `skip`)
  (lex_rule `"\\r\\n"` _ `newline`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `'"' ([^"\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* '"'` _ `string_dq`)
  (lex_rule `"'" ([^'\\x00-\\x1f\\x7f] | "''")* "'"` _ `string_sq`)
  (lex_rule `"0x" [0-9a-fA-F] ('_'? [0-9a-fA-F])*` _ `integer`)
  (lex_rule `"0b" [01] ('_'? [01])*` _ `integer`)
  (lex_rule `"0o" [0-7] ('_'? [0-7])*` _ `integer`)
  (lex_rule `('0' | [1-9] ('_'? [0-9])*)? '.' [0-9] ('_'? [0-9])* ([eE] [+-]? [0-9] ('_'? [0-9])*)?` _ `real`)
  (lex_rule `('0' | [1-9] ('_'? [0-9])*) [eE] [+-]? [0-9] ('_'? [0-9])*` _ `real`)
  (lex_rule `'0' | [1-9] ('_'? [0-9])*` _ `integer`)
  (lex_rule `[0-9] [0-9a-zA-Z_]*` _ `err`)
  (lex_rule `"<<="` _ `lshift_assign`)
  (lex_rule `"+%="` _ `plus_wrap_assign`)
  (lex_rule `"-%="` _ `minus_wrap_assign`)
  (lex_rule `"*%="` _ `star_wrap_assign`)
  (lex_rule `"+%"` _ `plus_wrap`)
  (lex_rule `"-%"` _ `minus_wrap`)
  (lex_rule `"*%"` _ `star_wrap`)
  (lex_rule `">>="` _ `rshift_assign`)
  (lex_rule `"**"` _ `power`)
  (lex_rule `"=="` _ `eq`)
  (lex_rule `"!="` _ `ne`)
  (lex_rule `"<="` _ `le`)
  (lex_rule `">="` _ `ge`)
  (lex_rule `"&&"` _ `and_sym`)
  (lex_rule `"||"` _ `or_sym`)
  (lex_rule `"=!"` _ `fixed_assign`)
  (lex_rule `"+="` _ `plus_assign`)
  (lex_rule `"-="` _ `minus_assign`)
  (lex_rule `"*="` _ `star_assign`)
  (lex_rule `"/="` _ `slash_assign`)
  (lex_rule `"%="` _ `percent_assign`)
  (lex_rule `"&="` _ `amp_assign`)
  (lex_rule `"|="` _ `bar_assign`)
  (lex_rule `"^="` _ `caret_assign`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule `"=>"` _ `fat_arrow`)
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
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'['` _ `lbracket`)
  (lex_rule `']'` _ `rbracket`)
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (schema
    (kind_decl
      (kinds `module`)
      (roles
        (role rest `decls` _ _))
      _
      _)
    (kind_decl
      (kinds `use`)
      (roles
        (role _ `name` _ _)
        (role
          _
          `alias`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `fun`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `tparams`
          (type `group`)
          opt)
        (role
          _
          `params`
          (type `group`)
          opt)
        (role _ `returns` _ opt)
        (role
          _
          `origins`
          (type `group`)
          opt)
        (role
          _
          `body`
          (type `block`)
          opt))
      _
      _)
    (kind_decl
      (kinds `sub`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `tparams`
          (type `group`)
          opt)
        (role
          _
          `params`
          (type `group`)
          opt)
        (role
          _
          `fails`
          (type
            (tagset `tag` `fails`))
          opt)
        (role
          _
          `body`
          (type `block`)
          opt))
      _
      _)
    (kind_decl
      (kinds `lambda`)
      (roles
        (role
          _
          `captures`
          (type `captures`)
          opt)
        (role
          _
          `params`
          (type `group`)
          opt)
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `struct`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `unique`
          (type
            (tagset `tag` `unique`))
          opt)
        (role rest `members` _ _))
      _
      _)
    (kind_decl
      (kinds `enum` `errors`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role rest `members` _ _))
      _
      _)
    (kind_decl
      (kinds `generic_struct`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `tparams`
          (type `group`)
          _)
        (role
          _
          `unique`
          (type
            (tagset `tag` `unique`))
          opt)
        (role rest `members` _ _))
      _
      _)
    (kind_decl
      (kinds `generic_enum`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `tparams`
          (type `group`)
          _)
        (role rest `members` _ _))
      _
      _)
    (kind_decl
      (kinds `type`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `test`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `pub`)
      (roles
        (role _ `decl` _ _))
      _
      _)
    (kind_decl
      (kinds `extern`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `extern_fun`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `params`
          (type `group`)
          opt)
        (role _ `returns` _ opt)
        (role
          _
          `origins`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `extern_sub`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `params`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `zig_extern`)
      (roles
        (role
          _
          `file`
          (type `leaf`)
          _)
        (role rest `decls` _ _))
      _
      _)
    (kind_decl
      (kinds `drop_decl`)
      (roles
        (role
          _
          `params`
          (type `group`)
          _)
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `labeled`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          _)
        (role _ `stmt` _ _))
      _
      _)
    (kind_decl
      (kinds `":"`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `default`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `type` _ _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `valued`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `variant`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `params`
          (type `group`)
          _))
      _
      _)
    (kind_decl
      (kinds `set`)
      (roles
        (role
          _
          `op`
          (type
            (tagset `tag` `fixed` `shadow` `shadow_fixed` `"+="` `"-="` `"*="` `"/="` `"%="` `"+%="` `"-%="` `"*%="` `"&="` `"|="` `"^="` `"<<="` `">>="`))
          opt)
        (role _ `target` _ _)
        (role _ `type` _ opt)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `drop`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `pass`)
      (roles)
      _
      _)
    (kind_decl
      (kinds `if`)
      (roles
        (role _ `cond` _ _)
        (role _ `then` _ _)
        (role _ `else` _ opt))
      _
      _)
    (kind_decl
      (kinds `as`)
      (roles
        (role _ `value` _ _)
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `while`)
      (roles
        (role _ `cond` _ _)
        (role _ `step` _ opt)
        (role
          _
          `body`
          (type `block`)
          _)
        (role
          _
          `else`
          (type `block`)
          opt))
      _
      _)
    (kind_decl
      (kinds `for`)
      (roles
        (role
          _
          `mode`
          (type
            (tagset `tag` `iter` `read` `write` `move`))
          _)
        (role
          _
          `var`
          (type `leaf`)
          _)
        (role
          _
          `index`
          (type `leaf`)
          opt)
        (role _ `source` _ _)
        (role
          _
          `body`
          (type `block`)
          _)
        (role
          _
          `else`
          (type `block`)
          opt))
      _
      _)
    (kind_decl
      (kinds `match`)
      (roles
        (role _ `subject` _ _)
        (role
          rest
          `arms`
          (type `arm`)
          _))
      _
      _)
    (kind_decl
      (kinds `arm`)
      (roles
        (role _ `pattern` _ _)
        (role _ `guard` _ opt)
        (role _ `body` _ _))
      _
      _)
    (kind_decl
      (kinds `alt_pattern`)
      (roles
        (role rest `alts` _ _))
      _
      _)
    (kind_decl
      (kinds `range_pattern`)
      (roles
        (role _ `lo` _ _)
        (role _ `hi` _ _))
      _
      _)
    (kind_decl
      (kinds `variant_pattern`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role rest `bindings` _ _))
      _
      _)
    (kind_decl
      (kinds `enum_lit`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `return`)
      (roles
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `break`)
      (roles
        (role _ `value` _ opt)
        (role
          _
          `label`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `continue`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `defer` `errdefer`)
      (roles
        (role _ `body` _ _))
      _
      _)
    (kind_decl
      (kinds `raw_block`)
      (roles
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `propagate` `propagate_none`)
      (roles
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `catch`)
      (roles
        (role _ `value` _ _)
        (role
          _
          `name`
          (type `leaf`)
          opt)
        (role _ `handler` _ _))
      _
      _)
    (kind_decl
      (kinds `block`)
      (roles
        (role rest `stmts` _ _))
      _
      _)
    (kind_decl
      (kinds `captures`)
      (roles
        (role
          rest
          `caps`
          (type `cap_clone` `cap_move` `cap_weak` `cap_read` `cap_write`)
          _))
      _
      wrapper)
    (kind_decl
      (kinds `cap_clone` `cap_move` `cap_weak` `cap_read` `cap_write`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `call`)
      (roles
        (role _ `callee` _ _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `builtin`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `member`)
      (roles
        (role _ `object` _ _)
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `index`)
      (roles
        (role _ `object` _ _)
        (role _ `index` _ _))
      _
      _)
    (kind_decl
      (kinds `inst`)
      (roles
        (role _ `object` _ _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `array`)
      (roles
        (role rest `elems` _ _))
      _
      _)
    (kind_decl
      (kinds `array_fill`)
      (roles
        (role _ `size` _ _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `kwarg`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `"+"` `"-"` `"*"` `"/"` `"%"`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `"+%"` `"-%"` `"*%"`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `"=="` `"!="` `"<"` `">"` `"<="` `">="`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `"&"` `"|"` `"^"` `"<<"` `">>"`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `"??"` `and` `or`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `".."`)
      (roles
        (role _ `left` _ opt)
        (role _ `right` _ opt))
      _
      _)
    (kind_decl
      (kinds `neg` `not`)
      (roles
        (role _ `operand` _ _))
      _
      _)
    (kind_decl
      (kinds `move` `read` `write` `clone` `share` `weak`)
      (roles
        (role _ `operand` _ _))
      _
      _)
    (kind_decl
      (kinds `optional` `error_union` `read_view` `write_view` `shared` `slice`)
      (roles
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `generic_inst`)
      (roles
        (role _ `name` _ _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `array_type`)
      (roles
        (role _ `size` _ _)
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `fun_type`)
      (roles
        (role
          _
          `params`
          (type `group`)
          opt)
        (role _ `returns` _ opt)
        (role
          _
          `fails`
          (type
            (tagset `tag` `fails`))
          opt))
      _
      _))
  (display
    (name_pair `IDENT` `"a name"`)
    (name_pair `INTEGER` `"an integer"`)
    (name_pair `REAL` `"a number"`)
    (name_pair `STRING_SQ` `"a string"`)
    (name_pair `STRING_DQ` `"a string"`)
    (name_pair `NEWLINE` `"the end of the line"`)
    (name_pair `INDENT` `"an indented block"`)
    (name_pair `OUTDENT` `"the end of the block"`)
    (name_pair `POST_IF` `"\`if\`"`)
    (name_pair `TERNARY_IF` `"\`if\`"`)
    (name_pair `BAR_CAPTURE` `"\`|\`"`)
    (name_pair `BAR_EMPTY` `"\`||\`"`)
    (name_pair `KWARG_NAME` `"a keyword argument"`)
    (name_pair `DROP_STMT` `"\`-\`"`)
    (name_pair `OF` `"\`of\`"`)
    (name_pair `UNIQUE` `"\`unique\`"`)
    (name_pair `FROM` `"\`from\`"`)
    (name_pair `STATIC` `"\`static\`"`)
    (name_pair `DOTDOT_OPEN` `"\`..\`"`)
    (name_pair `NULLISH_JUMP` `"\`??\`"`)
    (name_pair `STEP_COLON` `"\`:\`"`)
    (name_pair `TRUE` `"\`true\`"`)
    (name_pair `FALSE` `"\`false\`"`)
    (name_pair `AND` `"\`and\`"`)
    (name_pair `AS` `"\`as\`"`)
    (name_pair `BREAK` `"\`break\`"`)
    (name_pair `CATCH` `"\`catch\`"`)
    (name_pair `CONTINUE` `"\`continue\`"`)
    (name_pair `DEFER` `"\`defer\`"`)
    (name_pair `DROP` `"\`drop\`"`)
    (name_pair `ELSE` `"\`else\`"`)
    (name_pair `ENUM` `"\`enum\`"`)
    (name_pair `ERRDEFER` `"\`errdefer\`"`)
    (name_pair `ERROR` `"\`error\`"`)
    (name_pair `EXTERN` `"\`extern\`"`)
    (name_pair `FOR` `"\`for\`"`)
    (name_pair `FUN` `"\`fun\`"`)
    (name_pair `IF` `"\`if\`"`)
    (name_pair `IN` `"\`in\`"`)
    (name_pair `MATCH` `"\`match\`"`)
    (name_pair `NEW` `"\`new\`"`)
    (name_pair `NOT` `"\`not\`"`)
    (name_pair `OR` `"\`or\`"`)
    (name_pair `PASS` `"\`pass\`"`)
    (name_pair `PUB` `"\`pub\`"`)
    (name_pair `RAW` `"\`raw\`"`)
    (name_pair `RETURN` `"\`return\`"`)
    (name_pair `STRUCT` `"\`struct\`"`)
    (name_pair `SUB` `"\`sub\`"`)
    (name_pair `TEST` `"\`test\`"`)
    (name_pair `TRY` `"\`try\`"`)
    (name_pair `TYPE` `"\`type\`"`)
    (name_pair `USE` `"\`use\`"`)
    (name_pair `WHILE` `"\`while\`"`)
    (name_pair `ZIG` `"\`zig\`"`)
    (name_pair `ASYNC` `"\`async\`"`)
    (name_pair `AWAIT` `"\`await\`"`)
    (name_pair `CONST` `"\`const\`"`)
    (name_pair `IMPL` `"\`impl\`"`)
    (name_pair `TRAIT` `"\`trait\`"`)
    (name_pair `WHEN` `"\`when\`"`)
    (name_pair `WHERE` `"\`where\`"`)
    (name_pair `YIELD` `"\`yield\`"`)
    (name_pair `"="` `"\`=\`"`)
    (name_pair `"+="` `"\`+=\`"`)
    (name_pair `"-="` `"\`-=\`"`)
    (name_pair `"*="` `"\`*=\`"`)
    (name_pair `"/="` `"\`/=\`"`)
    (name_pair `"%="` `"\`%=\`"`)
    (name_pair `"&="` `"\`&=\`"`)
    (name_pair `"|="` `"\`|=\`"`)
    (name_pair `"^="` `"\`^=\`"`)
    (name_pair `"<<="` `"\`<<=\`"`)
    (name_pair `">>="` `"\`>>=\`"`)
    (name_pair `"+%="` `"\`+%=\`"`)
    (name_pair `"-%="` `"\`-%=\`"`)
    (name_pair `"*%="` `"\`*%=\`"`)
    (name_pair `"+%"` `"\`+%\`"`)
    (name_pair `"-%"` `"\`-%\`"`)
    (name_pair `"*%"` `"\`*%\`"`)
    (name_pair `":"` `"\`:\`"`)
    (name_pair `"->"` `"\`->\`"`)
    (name_pair `"("` `"\`(\`"`)
    (name_pair `")"` `"\`)\`"`)
    (name_pair `"["` `"\`[\`"`)
    (name_pair `"]"` `"\`]\`"`)
    (name_pair `","` `"\`,\`"`)
    (name_pair `"."` `"\`.\`"`)
    (name_pair `".."` `"\`..\`"`)
    (name_pair `"=>"` `"\`=>\`"`)
    (name_pair `"~"` `"\`~\`"`)
    (name_pair `"@"` `"\`@\`"`)
    (name_pair `"=="` `"\`==\`"`)
    (name_pair `"!="` `"\`!=\`"`)
    (name_pair `"<"` `"\`<\`"`)
    (name_pair `">"` `"\`>\`"`)
    (name_pair `"<="` `"\`<=\`"`)
    (name_pair `">="` `"\`>=\`"`)
    (name_pair `"??"` `"\`??\`"`)
    (name_pair `"|"` `"\`|\`"`)
    (name_pair `"^"` `"\`^\`"`)
    (name_pair `"&"` `"\`&\`"`)
    (name_pair `"<<"` `"\`<<\`"`)
    (name_pair `">>"` `"\`>>\`"`)
    (name_pair `"+"` `"\`+\`"`)
    (name_pair `"-"` `"\`-\`"`)
    (name_pair `"*"` `"\`*\`"`)
    (name_pair `"/"` `"\`/\`"`)
    (name_pair `"%"` `"\`%\`"`)
    (name_pair `"!"` `"\`!\`"`)
    (name_pair `"?"` `"\`?\`"`))
  (errors
    (name_pair `stmt` `"a statement"`)
    (name_pair `block` `"an indented block"`)
    (name_pair `type` `"a type"`)
    (name_pair `expr` `"an expression"`)
    (name_pair `tail` `"an expression"`)
    (name_pair `value` `"a value"`)
    (name_pair `field` `"a parameter"`)
    (name_pair `member` `"a member"`)
    (name_pair `pattern` `"a pattern"`)
    (name_pair `arm` `"a match arm"`)
    (name_pair `params` `"a parameter list"`)
    (name_pair `unary` `"an operand"`)
    (name_pair `step` `"an assignment or a call"`))
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
      ((group
          opt
          ((label
              `decls`
              (ref `body`)))))
      (node `module`)
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
        (group
          opt
          ((label
              `stmts`
              (ref `body`))))
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
      ((ref `zig_ext`))
      _
      _)
    (alt
      _
      ((lit `":"`)
        (label
          `label`
          (ref `name`))
        (label
          `stmt`
          (ref `stmt`)))
      (node `labeled`)
      _)
    (alt
      _
      ((ref `simple`))
      _
      _)
    (alt
      _
      ((ref `simple`)
        (tok `POST_IF`)
        (label
          `cond`
          (ref `value`)))
      (node
        `if`
        (named
          `then`
          (node
            `block`
            (pos `1`))))
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
      ((ref `assign`))
      _
      _)
    (alt
      _
      ((label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node `set`)
      _)
    (alt
      _
      ((tok `CONST`)
        (label
          `target`
          (ref `name`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `fixed`)))
      _)
    (alt
      _
      ((tok `CONST`)
        (label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `fixed`)))
      _)
    (alt
      _
      ((tok `NEW`)
        (label
          `target`
          (ref `name`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `shadow`)))
      _)
    (alt
      _
      ((tok `NEW`)
        (label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `shadow`)))
      _)
    (alt
      _
      ((tok `NEW`)
        (tok `CONST`)
        (label
          `target`
          (ref `name`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `shadow_fixed`)))
      _)
    (alt
      _
      ((tok `NEW`)
        (tok `CONST`)
        (label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `shadow_fixed`)))
      _)
    (alt
      _
      ((tok `DROP_STMT`)
        (label
          `name`
          (ref `name`)))
      (node `drop`)
      _)
    (alt
      _
      ((tok `PASS`))
      (node `pass`)
      _)
    (alt
      _
      ((tok `RETURN`)
        (group
          opt
          ((label
              `value`
              (ref `tail`)))))
      (node `return`)
      _)
    (alt
      _
      ((tok `BREAK`)
        (group
          opt
          ((lit `":"`)
            (label
              `label`
              (ref `name`))))
        (group
          opt
          ((label
              `value`
              (ref `tail`)))))
      (node `break`)
      _)
    (alt
      _
      ((tok `CONTINUE`)
        (group
          opt
          ((lit `":"`)
            (label
              `label`
              (ref `name`)))))
      (node `continue`)
      _)
    (alt
      _
      ((tok `DEFER`)
        (label
          `body`
          (group
            _
            ((ref `block`))
            ((ref `simple`)))))
      (node `defer`)
      _)
    (alt
      _
      ((tok `ERRDEFER`)
        (label
          `body`
          (group
            _
            ((ref `block`))
            ((ref `simple`)))))
      (node `errdefer`)
      _)
    (alt
      _
      ((tok `RAW`)
        (label
          `body`
          (ref `block`)))
      (node `raw_block`)
      _))
  (rule
    (name `assign`)
    (alt
      _
      ((label
          `target`
          (ref `postfix`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node `set`)
      _)
    (alt
      _
      ((label
          `target`
          (ref `postfix`))
        (label
          `op`
          (group
            _
            ((lit `"+="`))
            ((lit `"-="`))
            ((lit `"*="`))
            ((lit `"/="`))
            ((lit `"%="`))
            ((lit `"+%="`))
            ((lit `"-%="`))
            ((lit `"*%="`))
            ((lit `"&="`))
            ((lit `"|="`))
            ((lit `"^="`))
            ((lit `"<<="`))
            ((lit `">>="`))))
        (label
          `value`
          (ref `tail`)))
      (node `set`)
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
        (label
          `decl`
          (ref `defn`)))
      (node `pub`)
      _)
    (alt
      _
      ((tok `PUB`)
        (label
          `decl`
          (ref `constant`)))
      (node `pub`)
      _))
  (rule
    (name `constant`)
    (alt
      _
      ((label
          `target`
          (ref `name`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node `set`)
      _)
    (alt
      _
      ((label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node `set`)
      _)
    (alt
      _
      ((tok `CONST`)
        (label
          `target`
          (ref `name`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `fixed`)))
      _)
    (alt
      _
      ((tok `CONST`)
        (label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `fixed`)))
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
        (label
          `name`
          (ref `mpath`)))
      (node `use`)
      _)
    (alt
      _
      ((tok `USE`)
        (label
          `name`
          (ref `mpath`))
        (tok `AS`)
        (label
          `alias`
          (ref `name`)))
      (node `use`)
      _))
  (rule
    (name `mpath`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((label
          `object`
          (ref `name`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _))
  (rule
    (name `fun`)
    (alt
      _
      ((tok `FUN`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `tparams`
              (ref `tparams`))))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (group
          opt
          ((label
              `returns`
              (ref `returns`))))
        (group
          opt
          ((label
              `origins`
              (ref `origins`))))
        (label
          `body`
          (ref `block`)))
      (node `fun`)
      _))
  (rule
    (name `sub`)
    (alt
      _
      ((tok `SUB`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `tparams`
              (ref `tparams`))))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (label
          `body`
          (ref `block`)))
      (node `sub`)
      _)
    (alt
      _
      ((tok `SUB`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `tparams`
              (ref `tparams`))))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (lit `"!"`)
        (label
          `body`
          (ref `block`)))
      (node
        `sub`
        (named
          `fails`
          (tag `fails`)))
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
    (name `origins`)
    (alt
      _
      ((tok `FROM`)
        (ref `onames`))
      (list
        (spread `2`))
      _)
    (alt
      _
      ((tok `FROM`)
        (tok `STATIC`))
      (list)
      _))
  (rule
    (name `onames`)
    (alt
      _
      ((ref `name`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `onames`)
        (lit `","`)
        (ref `name`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `params`)
    (alt
      _
      ((lit `"("`)
        (ref `fields`)
        (skip
          (group
            opt
            ((lit `","`))))
        (lit `")"`))
      (list
        (spread `2`))
      _)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      (list)
      _))
  (rule
    (name `tparams`)
    (alt
      _
      ((lit `"["`)
        (ref `tfields`)
        (skip
          (group
            opt
            ((lit `","`))))
        (lit `"]"`))
      (list
        (spread `2`))
      _))
  (rule
    (name `tfields`)
    (alt
      _
      ((ref `tfield`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `tfields`)
        (lit `","`)
        (ref `tfield`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `tfield`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((label
          `name`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`)))
      (node `:`)
      _))
  (rule
    (name `fields`)
    (alt
      _
      ((ref `field`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `fields`)
        (lit `","`)
        (ref `field`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `field`)
    (alt
      _
      ((ref `fname`))
      _
      _)
    (alt
      _
      ((label
          `name`
          (ref `fname`))
        (lit `":"`)
        (label
          `type`
          (ref `type`)))
      (node `:`)
      _)
    (alt
      _
      ((label
          `name`
          (ref `fname`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"="`)
        (label
          `value`
          (ref `expr`)))
      (node `default`)
      _)
    (alt
      _
      ((lit `"?"`)
        (label
          `operand`
          (ref `fname`)))
      (node `read`)
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `operand`
          (ref `fname`)))
      (node `write`)
      _)
    (alt
      _
      ((lit `"<"`)
        (label
          `operand`
          (ref `fname`)))
      (node `move`)
      _))
  (rule
    (name `fname`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((tok `KWARG_NAME`))
      _
      _))
  (rule
    (name `enum`)
    (alt
      _
      ((tok `ENUM`)
        (label
          `name`
          (ref `name`))
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node `enum`)
      _)
    (alt
      _
      ((tok `ENUM`)
        (label
          `name`
          (ref `name`))
        (label
          `tparams`
          (ref `tparams`))
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node `generic_enum`)
      _))
  (rule
    (name `errors`)
    (alt
      _
      ((tok `ERROR`)
        (label
          `name`
          (ref `name`))
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node `errors`)
      _))
  (rule
    (name `struct`)
    (alt
      _
      ((tok `STRUCT`)
        (label
          `name`
          (ref `name`))
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node `struct`)
      _)
    (alt
      _
      ((tok `STRUCT`)
        (label
          `name`
          (ref `name`))
        (tok `UNIQUE`)
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node
        `struct`
        (named
          `unique`
          (tag `unique`)))
      _)
    (alt
      _
      ((tok `STRUCT`)
        (label
          `name`
          (ref `name`))
        (label
          `tparams`
          (ref `tparams`))
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node `generic_struct`)
      _)
    (alt
      _
      ((tok `STRUCT`)
        (label
          `name`
          (ref `name`))
        (label
          `tparams`
          (ref `tparams`))
        (tok `UNIQUE`)
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node
        `generic_struct`
        (named
          `unique`
          (tag `unique`)))
      _))
  (rule
    (name `typedef`)
    (alt
      _
      ((tok `TYPE`)
        (label
          `name`
          (ref `name`))
        (lit `"="`)
        (label
          `type`
          (ref `type`)))
      (node `type`)
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
      ((label
          `name`
          (ref `name`))
        (lit `"="`)
        (label
          `value`
          (ref `expr`)))
      (node `valued`)
      _)
    (alt
      _
      ((label
          `name`
          (ref `name`))
        (label
          `params`
          (ref `params`)))
      (node `variant`)
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
        (label
          `params`
          (ref `params`))
        (label
          `body`
          (ref `block`)))
      (node `drop_decl`)
      _)
    (alt
      _
      ((tok `PUB`)
        (label
          `decl`
          (ref `member`)))
      (node `pub`)
      _))
  (rule
    (name `test`)
    (alt
      _
      ((tok `TEST`)
        (label
          `name`
          (group
            _
            ((tok `STRING_DQ`))
            ((tok `STRING_SQ`))))
        (label
          `body`
          (ref `block`)))
      (node `test`)
      _))
  (rule
    (name `extvar`)
    (alt
      _
      ((tok `EXTERN`)
        (label
          `name`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`)))
      (node `extern`)
      _))
  (rule
    (name `ext_fun`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `FUN`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (group
          opt
          ((label
              `returns`
              (ref `returns`))))
        (group
          opt
          ((label
              `origins`
              (ref `origins`)))))
      (node `extern_fun`)
      _))
  (rule
    (name `ext_sub`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `SUB`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `params`
              (ref `params`)))))
      (node `extern_sub`)
      _))
  (rule
    (name `zig_ext`)
    (alt
      _
      ((tok `EXTERN`)
        (tok `ZIG`)
        (label
          `file`
          (tok `STRING_DQ`))
        (tok `INDENT`)
        (label
          `decls`
          (ref `zdecls`))
        (tok `OUTDENT`))
      (node `zig_extern`)
      _))
  (rule
    (name `zdecls`)
    (alt
      _
      ((ref `zdecl`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `zdecls`)
        (tok `NEWLINE`)
        (ref `zdecl`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `zdecls`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `zdecl`)
    (alt
      _
      ((ref `zfun`))
      _
      _)
    (alt
      _
      ((tok `PUB`)
        (label
          `decl`
          (ref `zfun`)))
      (node `pub`)
      _))
  (rule
    (name `zfun`)
    (alt
      _
      ((tok `FUN`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `tparams`
              (ref `tparams`))))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (group
          opt
          ((label
              `returns`
              (ref `returns`))))
        (group
          opt
          ((label
              `origins`
              (ref `origins`)))))
      (node `fun`)
      _)
    (alt
      _
      ((tok `SUB`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `tparams`
              (ref `tparams`))))
        (group
          opt
          ((label
              `params`
              (ref `params`)))))
      (node `sub`)
      _)
    (alt
      _
      ((tok `SUB`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `tparams`
              (ref `tparams`))))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (lit `"!"`))
      (node
        `sub`
        (named
          `fails`
          (tag `fails`)))
      _))
  (rule
    (name `type`)
    (alt
      _
      ((lit `"?"`)
        (label
          `type`
          (ref `type`)))
      (node `read_view`)
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `type`
          (ref `type`)))
      (node `write_view`)
      _)
    (alt
      _
      ((ref `ptype`))
      _
      _)
    (alt
      _
      ((ref `tsuffix`))
      _
      _))
  (rule
    (name `ptype`)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (label
          `type`
          (ref `type`)))
      (node `slice`)
      _)
    (alt
      _
      ((lit `"["`)
        (label
          `size`
          (ref `dim`))
        (lit `"]"`)
        (label
          `type`
          (ref `type`)))
      (node `array_type`)
      _)
    (alt
      _
      ((tok `FUN`)
        (lit `"("`)
        (group
          opt
          ((label
              `params`
              (list_req
                `L`
                (plain `type`)))))
        (lit `")"`)
        (lit `"->"`)
        (label
          `returns`
          (ref `type`)))
      (node `fun_type`)
      _)
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (group
          opt
          ((label
              `params`
              (list_req
                `L`
                (plain `type`)))))
        (lit `")"`))
      (node `fun_type`)
      _)
    (alt
      _
      ((tok `SUB`)
        (lit `"("`)
        (group
          opt
          ((label
              `params`
              (list_req
                `L`
                (plain `type`)))))
        (lit `")"`)
        (lit `"!"`))
      (node
        `fun_type`
        (named
          `fails`
          (tag `fails`)))
      _)
    (alt
      _
      ((lit `"*"`)
        (label
          `type`
          (ref `ptype`)))
      (node `shared`)
      _)
    (alt
      _
      ((lit `"~"`)
        (label
          `operand`
          (ref `ptype`)))
      (node `weak`)
      _))
  (rule
    (name `tsuffix`)
    (alt
      _
      ((label
          `type`
          (ref `tsuffix`))
        (lit `"?"`))
      (node `optional`)
      _)
    (alt
      _
      ((label
          `type`
          (ref `tsuffix`))
        (lit `"!"`))
      (node `error_union`)
      _)
    (alt
      _
      ((ref `thandle`))
      _
      _))
  (rule
    (name `thandle`)
    (alt
      _
      ((lit `"*"`)
        (label
          `type`
          (ref `thandle`)))
      (node `shared`)
      _)
    (alt
      _
      ((lit `"~"`)
        (label
          `operand`
          (ref `thandle`)))
      (node `weak`)
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
      ((ref `tname`))
      _
      _)
    (alt
      _
      ((label
          `name`
          (ref `tname`))
        (lit `"["`)
        (label
          `args`
          (ref `types`))
        (skip
          (group
            opt
            ((lit `","`))))
        (lit `"]"`))
      (node `generic_inst`)
      _)
    (alt
      _
      ((lit `"("`)
        (ref `type`)
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `tname`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((label
          `object`
          (ref `name`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _))
  (rule
    (name `types`)
    (alt
      _
      ((ref `targ`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `types`)
        (lit `","`)
        (ref `targ`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `targ`)
    (alt
      _
      ((ref `type`))
      _
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((lit `"-"`)
        (label
          `operand`
          (tok `INTEGER`)))
      (node `neg`)
      _)
    (alt
      _
      ((lit `"("`)
        (tok `INTEGER`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `cexp`))
      _
      _))
  (rule
    (name `dim`)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((lit `"-"`)
        (label
          `operand`
          (tok `INTEGER`)))
      (node `neg`)
      _)
    (alt
      _
      ((lit `"("`)
        (tok `INTEGER`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((lit `"("`)
        (ref `name`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((label
          `object`
          (ref `name`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _)
    (alt
      _
      ((ref `cexp`))
      _
      _))
  (rule
    (name `cexp`)
    (alt
      _
      ((ref `cmulop`))
      _
      _)
    (alt
      _
      ((ref `caddop`))
      _
      _)
    (alt
      _
      ((lit `"("`)
        (ref `cexp`)
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `caddop`)
    (alt
      _
      ((label
          `left`
          (ref `cadd`))
        (lit `"+"`)
        (label
          `right`
          (ref `cmul`)))
      (node `+`)
      _)
    (alt
      _
      ((label
          `left`
          (ref `cadd`))
        (lit `"-"`)
        (label
          `right`
          (ref `cmul`)))
      (node `-`)
      _))
  (rule
    (name `cadd`)
    (alt
      _
      ((ref `caddop`))
      _
      _)
    (alt
      _
      ((ref `cmul`))
      _
      _))
  (rule
    (name `cmulop`)
    (alt
      _
      ((label
          `left`
          (ref `cmul`))
        (lit `"*"`)
        (label
          `right`
          (ref `cunit`)))
      (node `*`)
      _)
    (alt
      _
      ((label
          `left`
          (ref `cmul`))
        (lit `"/"`)
        (label
          `right`
          (ref `cunit`)))
      (node `/`)
      _)
    (alt
      _
      ((label
          `left`
          (ref `cmul`))
        (lit `"%"`)
        (label
          `right`
          (ref `cunit`)))
      (node `%`)
      _))
  (rule
    (name `cmul`)
    (alt
      _
      ((ref `cmulop`))
      _
      _)
    (alt
      _
      ((ref `cunit`))
      _
      _))
  (rule
    (name `cunit`)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((label
          `object`
          (ref `name`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _)
    (alt
      _
      ((lit `"("`)
        (ref `cexp`)
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
      ((label
          `value`
          (ref `logic`))
        (tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (label
          `name`
          (ref `name`))
        (tok `BAR_CAPTURE`)
        (label
          `handler`
          (ref `block`)))
      (node `catch`)
      _)
    (alt
      _
      ((ref `closure`))
      _
      _))
  (rule
    (name `value`)
    (alt
      _
      ((label
          `then`
          (ref `logic`))
        (tok `TERNARY_IF`)
        (label
          `cond`
          (ref `logic`))
        (tok `ELSE`)
        (label
          `else`
          (ref `value`)))
      (node `if`)
      _)
    (alt
      _
      ((label
          `value`
          (ref `logic`))
        (tok `CATCH`)
        (group
          opt
          ((tok `BAR_CAPTURE`)
            (label
              `name`
              (ref `name`))
            (tok `BAR_CAPTURE`)))
        (label
          `handler`
          (ref `value`)))
      (node `catch`)
      _)
    (alt
      _
      ((label
          `value`
          (ref `logic`))
        (tok `CATCH`)
        (group
          opt
          ((tok `BAR_CAPTURE`)
            (label
              `name`
              (ref `name`))
            (tok `BAR_CAPTURE`)))
        (label
          `handler`
          (ref `jump`)))
      (node `catch`)
      _)
    (alt
      _
      ((label
          `left`
          (ref `logic`))
        (tok `NULLISH_JUMP`)
        (label
          `right`
          (ref `jump`)))
      (node `??`)
      _)
    (alt
      _
      ((ref `logic`))
      _
      _))
  (rule
    (name `jump`)
    (alt
      _
      ((tok `RETURN`)
        (group
          opt
          ((label
              `value`
              (ref `value`)))))
      (node `return`)
      _)
    (alt
      _
      ((tok `BREAK`)
        (group
          opt
          ((lit `":"`)
            (label
              `label`
              (ref `name`))))
        (group
          opt
          ((label
              `value`
              (ref `value`)))))
      (node `break`)
      _)
    (alt
      _
      ((tok `CONTINUE`)
        (group
          opt
          ((lit `":"`)
            (label
              `label`
              (ref `name`)))))
      (node `continue`)
      _))
  (rule
    (name `logic`)
    (alt
      _
      ((label
          `left`
          (ref `logic`))
        (tok `OR`)
        (label
          `right`
          (ref `conj`)))
      (node `or`)
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
      ((label
          `left`
          (ref `conj`))
        (tok `AND`)
        (label
          `right`
          (ref `neg`)))
      (node `and`)
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
        (label
          `operand`
          (ref `neg`)))
      (node `not`)
      _)
    (alt
      _
      ((label
          `value`
          (at_ref `infix`))
        (tok `AS`)
        (label
          `name`
          (ref `name`)))
      (node `as`)
      _)
    (alt
      _
      ((at_ref `infix`))
      _
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
    (name `if`)
    (alt
      _
      ((tok `IF`)
        (label
          `cond`
          (ref `value`))
        (label
          `then`
          (ref `block`))
        (group
          opt
          ((tok `ELSE`)
            (label
              `else`
              (ref `block`)))))
      (node `if`)
      _)
    (alt
      _
      ((tok `IF`)
        (label
          `cond`
          (ref `value`))
        (label
          `then`
          (ref `block`))
        (tok `ELSE`)
        (label
          `else`
          (ref `if`)))
      (node `if`)
      _))
  (rule
    (name `while`)
    (alt
      _
      ((tok `WHILE`)
        (label
          `cond`
          (ref `value`))
        (group
          opt
          ((tok `STEP_COLON`)
            (label
              `step`
              (ref `step`))))
        (label
          `body`
          (ref `block`))
        (group
          opt
          ((tok `ELSE`)
            (label
              `else`
              (ref `block`)))))
      (node `while`)
      _))
  (rule
    (name `step`)
    (alt
      _
      ((ref `assign`))
      _
      _)
    (alt
      _
      ((ref `postfix`))
      _
      _)
    (alt
      _
      ((lit `"?"`)
        (label
          `operand`
          (ref `postfix`)))
      (node `read`)
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `operand`
          (ref `postfix`)))
      (node `write`)
      _)
    (alt
      _
      ((lit `"<"`)
        (label
          `operand`
          (ref `postfix`)))
      (node `move`)
      _))
  (rule
    (name `for`)
    (alt
      _
      ((tok `FOR`)
        (label
          `var`
          (ref `name`))
        (group
          opt
          ((lit `","`)
            (label
              `index`
              (ref `name`))))
        (tok `IN`)
        (label
          `source`
          (ref `value`))
        (label
          `body`
          (ref `block`))
        (group
          opt
          ((tok `ELSE`)
            (label
              `else`
              (ref `block`)))))
      (node
        `for`
        (named
          `mode`
          (tag `iter`)))
      _))
  (rule
    (name `match`)
    (alt
      _
      ((tok `MATCH`)
        (label
          `subject`
          (ref `value`))
        (tok `INDENT`)
        (label
          `arms`
          (ref `arms`))
        (tok `OUTDENT`))
      (node `match`)
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
      ((label
          `pattern`
          (ref `pats`))
        (lit `"=>"`)
        (label
          `body`
          (ref `simple`)))
      (node `arm`)
      _)
    (alt
      _
      ((label
          `pattern`
          (ref `pats`))
        (tok `POST_IF`)
        (label
          `guard`
          (ref `value`))
        (lit `"=>"`)
        (label
          `body`
          (ref `simple`)))
      (node `arm`)
      _)
    (alt
      _
      ((label
          `pattern`
          (ref `pats`))
        (label
          `body`
          (ref `block`)))
      (node `arm`)
      _)
    (alt
      _
      ((label
          `pattern`
          (ref `pats`))
        (tok `POST_IF`)
        (label
          `guard`
          (ref `value`))
        (label
          `body`
          (ref `block`)))
      (node `arm`)
      _))
  (rule
    (name `pats`)
    (alt
      _
      ((ref `pattern`))
      _
      _)
    (alt
      _
      ((label
          `alts`
          (ref `palts`)))
      (node `alt_pattern`)
      _))
  (rule
    (name `palts`)
    (alt
      _
      ((ref `pattern`)
        (lit `","`)
        (ref `pattern`))
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `palts`)
        (lit `","`)
        (ref `pattern`))
      (list
        (spread `1`)
        (pos `3`))
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
      ((label
          `lo`
          (ref `patatom`))
        (lit `".."`)
        (label
          `hi`
          (ref `patatom`)))
      (node `range_pattern`)
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
      ((label
          `object`
          (ref `name`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _)
    (alt
      _
      ((label
          `object`
          (ref `pqual`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((lit `"-"`)
        (label
          `operand`
          (tok `INTEGER`)))
      (node `neg`)
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
      ((lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `enum_lit`)
      _)
    (alt
      _
      ((lit `"."`)
        (label
          `name`
          (ref `name`))
        (lit `"("`)
        (lit `")"`))
      (node `variant_pattern`)
      _)
    (alt
      _
      ((lit `"."`)
        (label
          `name`
          (ref `name`))
        (lit `"("`)
        (label
          `bindings`
          (ref `pbinds`))
        (skip
          (group
            opt
            ((lit `","`))))
        (lit `")"`))
      (node `variant_pattern`)
      _))
  (rule
    (name `pqual`)
    (alt
      _
      ((label
          `object`
          (ref `name`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _))
  (rule
    (name `pbinds`)
    (alt
      _
      ((ref `pbind`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `pbinds`)
        (lit `","`)
        (ref `pbind`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `pbind`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((label
          `name`
          (tok `KWARG_NAME`))
        (lit `":"`)
        (label
          `value`
          (ref `name`)))
      (node `kwarg`)
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
      ((lit `"*"`)
        (label
          `operand`
          (ref `lambda`)))
      (node `share`)
      _))
  (rule
    (name `lambda`)
    (alt
      _
      ((label
          `params`
          (ref `bars`))
        (label
          `body`
          (ref `block`)))
      (node `lambda`)
      _)
    (alt
      _
      ((label
          `params`
          (ref `bars`))
        (ref `expr`))
      (node
        `lambda`
        (named
          `body`
          (node
            `block`
            (pos `2`))))
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
      ((lit `"*"`)
        (label
          `operand`
          (ref `clambda`)))
      (node `share`)
      _))
  (rule
    (name `clambda`)
    (alt
      _
      ((label
          `params`
          (ref `bars`))
        (ref `assign`))
      (node
        `lambda`
        (named
          `body`
          (node
            `block`
            (pos `2`))))
      _))
  (rule
    (name `bars`)
    (alt
      _
      ((tok `BAR_CAPTURE`)
        (ref `barents`)
        (skip
          (group
            opt
            ((lit `","`))))
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
    (name `barents`)
    (alt
      _
      ((ref `barent`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `barents`)
        (lit `","`)
        (ref `barent`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `barent`)
    (alt
      _
      ((ref `fname`))
      _
      _)
    (alt
      _
      ((label
          `name`
          (ref `fname`))
        (lit `":"`)
        (label
          `type`
          (ref `type`)))
      (node `:`)
      _)
    (alt
      _
      ((lit `"+"`)
        (label
          `name`
          (ref `name`)))
      (node `cap_clone`)
      _)
    (alt
      _
      ((lit `"<"`)
        (label
          `name`
          (ref `name`)))
      (node `cap_move`)
      _)
    (alt
      _
      ((lit `"~"`)
        (label
          `name`
          (ref `name`)))
      (node `cap_weak`)
      _)
    (alt
      _
      ((lit `"?"`)
        (label
          `name`
          (ref `name`)))
      (node `cap_read`)
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `name`
          (ref `name`)))
      (node `cap_write`)
      _))
  (rule
    (name `unary`)
    (alt
      _
      ((lit `"-"`)
        (label
          `operand`
          (ref `unary`)))
      (node `neg`)
      _)
    (alt
      _
      ((lit `"<"`)
        (label
          `operand`
          (ref `unary`)))
      (node `move`)
      _)
    (alt
      _
      ((lit `"+"`)
        (label
          `operand`
          (ref `unary`)))
      (node `clone`)
      _)
    (alt
      _
      ((lit `"?"`)
        (label
          `operand`
          (ref `unary`)))
      (node `read`)
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `operand`
          (ref `unary`)))
      (node `write`)
      _)
    (alt
      _
      ((lit `"*"`)
        (label
          `operand`
          (ref `unary`)))
      (node `share`)
      _)
    (alt
      _
      ((lit `"~"`)
        (label
          `operand`
          (ref `unary`)))
      (node `weak`)
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
      ((label
          `object`
          (ref `postfix`))
        (lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `member`)
      _)
    (alt
      _
      ((label
          `object`
          (ref `postfix`))
        (lit `"["`)
        (label
          `index`
          (ref `expr`))
        (lit `"]"`))
      (node `index`)
      _)
    (alt
      _
      ((label
          `object`
          (ref `postfix`))
        (lit `"["`)
        (label
          `index`
          (ref `open`))
        (lit `"]"`))
      (node `index`)
      _)
    (alt
      _
      ((label
          `object`
          (ref `postfix`))
        (lit `"["`)
        (label
          `args`
          (ref `targs`))
        (lit `"]"`))
      (node `inst`)
      _)
    (alt
      _
      ((label
          `callee`
          (ref `postfix`))
        (lit `"("`)
        (label
          `args`
          (ref `args`))
        (lit `")"`))
      (node `call`)
      _)
    (alt
      _
      ((label
          `value`
          (ref `postfix`))
        (lit `"!"`))
      (node `propagate`)
      _)
    (alt
      _
      ((label
          `value`
          (ref `postfix`))
        (lit `"?"`))
      (node `propagate_none`)
      _)
    (alt
      _
      ((ref `atom`))
      _
      _))
  (rule
    (name `open`)
    (alt
      _
      ((label
          `left`
          (ref `expr`))
        (tok `DOTDOT_OPEN`))
      (node `..`)
      _)
    (alt
      _
      ((lit `".."`)
        (label
          `right`
          (ref `expr`)))
      (node `..`)
      _)
    (alt
      _
      ((tok `DOTDOT_OPEN`))
      (node `..`)
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
        (lit `","`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `callargs`)
        (lit `","`)
        (ref `cclosure`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `cclosure`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `targs`)
    (alt
      _
      ((ref `expr`)
        (lit `","`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `","`)
        (ref `expr`))
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `","`)
        (ref `targs`))
      (list
        (pos `1`)
        (spread `3`))
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
      ((label
          `name`
          (tok `KWARG_NAME`))
        (lit `":"`)
        (label
          `value`
          (ref `expr`)))
      (node `kwarg`)
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
      ((lit `"."`)
        (label
          `name`
          (ref `name`)))
      (node `enum_lit`)
      _)
    (alt
      _
      ((lit `"@"`)
        (label
          `name`
          (ref `name`))
        (lit `"("`)
        (label
          `args`
          (ref `args`))
        (lit `")"`))
      (node `builtin`)
      _)
    (alt
      _
      ((lit `"["`)
        (group
          opt
          ((label
              `elems`
              (ref `exprs`))))
        (lit `"]"`))
      (node `array`)
      _)
    (alt
      _
      ((lit `"["`)
        (label
          `elems`
          (ref `exprs`))
        (lit `","`)
        (lit `"]"`))
      (node `array`)
      _)
    (alt
      _
      ((lit `"["`)
        (label
          `size`
          (ref `expr`))
        (tok `OF`)
        (label
          `value`
          (ref `expr`))
        (lit `"]"`))
      (node `array_fill`)
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
      ((lit `"("`)
        (ref `cclosure`)
        (lit `")"`))
      (pos `2`)
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
      (infix_op `"-"` `left`)
      (infix_op `"+%"` `left`)
      (infix_op `"-%"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`)
      (infix_op `"%"` `left`)
      (infix_op `"*%"` `left`))))
