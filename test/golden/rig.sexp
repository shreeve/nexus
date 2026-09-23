(grammar
  (lang `"rig"`)
  (section `lexer`)
  (tokens `tokens` `ident` `integer` `real` `string_sq` `string_dq` `true` `false` `and` `as` `break` `catch` `continue` `defer` `drop` `else` `enum` `errdefer` `error` `extern` `for` `fun` `if` `in` `match` `new` `not` `or` `pre` `pub` `raw` `return` `struct` `sub` `test` `try` `type` `use` `while` `zig` `plus` `minus` `minus_prefix` `star` `slash` `percent` `power` `eq` `ne` `lt` `gt` `le` `ge` `and_sym` `or_sym` `not_sym` `question` `nullish` `bar` `ampersand` `caret` `tilde` `lshift` `rshift` `at` `assign` `fixed_assign` `move_assign` `plus_assign` `minus_assign` `star_assign` `slash_assign` `percent_assign` `amp_assign` `bar_assign` `caret_assign` `lshift_assign` `rshift_assign` `lparen` `rparen` `lbrace` `rbrace` `lbracket` `rbracket` `comma` `colon` `arrow` `fat_arrow` `dot` `dotdot` `indent` `outdent` `newline` `lparen_call` `lbracket_index` `post_if` `ternary_if` `bar_capture` `bar_empty` `dot_lit` `kwarg_name` `move_pfx` `clone_pfx` `pin_pfx` `read_pfx` `write_pfx` `share_pfx` `drop_stmt` `suffix_q` `suffix_bang` `comment` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `"\\\\\\n"` _ `skip`)
  (lex_rule `"\\r\\n"` _ `newline`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `'\\r'` _ `newline`)
  (lex_rule `'"' ([^"\\\\$\\n] | '\\\\' . | '$')* '"'` _ `string_dq`)
  (lex_rule `"'" ([^'\\n] | "''")* "'"` _ `string_sq`)
  (lex_rule `'0' [xX] [0-9a-fA-F]+` _ `integer`)
  (lex_rule `'0' [bB] [01]+` _ `integer`)
  (lex_rule `'0' [oO] [0-7]+` _ `integer`)
  (lex_rule `[0-9]* '.' [0-9]+ ([Ee] [+-]? [0-9]+)?` _ `real`)
  (lex_rule `[0-9]+ [Ee] [+-]? [0-9]+` _ `real`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `"<<="` _ `lshift_assign`)
  (lex_rule `">>="` _ `rshift_assign`)
  (lex_rule `"**"` _ `power`)
  (lex_rule `"=="` _ `eq`)
  (lex_rule `"!="` _ `ne`)
  (lex_rule `"<="` _ `le`)
  (lex_rule `">="` _ `ge`)
  (lex_rule `"&&"` _ `and_sym`)
  (lex_rule `"||"` _ `or_sym`)
  (lex_rule `"=!"` _ `fixed_assign`)
  (lex_rule `"<-"` _ `move_assign`)
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
  (lex_rule `'{'` _ `lbrace`)
  (lex_rule `'}'` _ `rbrace`)
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
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `zig`)
      (roles
        (role
          _
          `code`
          (type `leaf`)
          _))
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
          `params`
          (type `group`)
          opt)
        (role _ `returns` _ opt)
        (role
          _
          `body`
          (type `block`)
          _))
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
      (kinds `struct` `enum` `errors`)
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
      (kinds `generic_type` `generic_enum`)
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
        (role
          _
          `decl`
          (type `fun` `sub` `struct` `enum` `errors` `type` `generic_type` `generic_enum` `test`)
          _))
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
        (role _ `returns` _ opt))
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
      (kinds `":"` `pre_param`)
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
            (tagset `tag` `fixed` `shadow` `move` `"+="` `"-="` `"*="` `"/="` `"%="` `"&="` `"|="` `"^="` `"<<="` `">>="`))
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
            (tagset `tag` `iter` `ptr` `read` `write` `move`))
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
        (role _ `body` _ _))
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
        (role
          rest
          `bindings`
          (type `leaf`)
          _))
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
      (kinds `raw_block` `pre_block`)
      (roles
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `pre` `propagate`)
      (roles
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `try_block`)
      (roles
        (role
          _
          `body`
          (type `block`)
          _)
        (role
          _
          `catch`
          (type `catch_block`)
          opt))
      _
      _)
    (kind_decl
      (kinds `catch_block`)
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
          (type `cap_clone` `cap_move` `cap_weak`)
          _))
      _
      wrapper)
    (kind_decl
      (kinds `cap_clone` `cap_move` `cap_weak`)
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
      (kinds `array`)
      (roles
        (role rest `elems` _ _))
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
      (kinds `"??"` `".."` `and` `or`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `neg` `not`)
      (roles
        (role _ `operand` _ _))
      _
      _)
    (kind_decl
      (kinds `move` `read` `write` `clone` `share` `weak` `pin`)
      (roles
        (role _ `operand` _ _))
      _
      _)
    (kind_decl
      (kinds `optional` `error_union` `borrow_read` `borrow_write` `shared` `slice`)
      (roles
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `generic_inst`)
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
      (kinds `array_type`)
      (roles
        (role
          _
          `size`
          (type `leaf`)
          _)
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
        (role _ `returns` _ opt))
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
    (name_pair `LPAREN_CALL` `"\`(\`"`)
    (name_pair `LBRACKET_INDEX` `"\`[\`"`)
    (name_pair `POST_IF` `"\`if\`"`)
    (name_pair `TERNARY_IF` `"\`if\`"`)
    (name_pair `BAR_CAPTURE` `"\`|\`"`)
    (name_pair `BAR_EMPTY` `"\`||\`"`)
    (name_pair `DOT_LIT` `"\`.\`"`)
    (name_pair `KWARG_NAME` `"a keyword argument"`)
    (name_pair `MOVE_PFX` `"\`<\`"`)
    (name_pair `CLONE_PFX` `"\`+\`"`)
    (name_pair `PIN_PFX` `"\`@\`"`)
    (name_pair `READ_PFX` `"\`?\`"`)
    (name_pair `WRITE_PFX` `"\`!\`"`)
    (name_pair `SHARE_PFX` `"\`*\`"`)
    (name_pair `DROP_STMT` `"\`-\`"`)
    (name_pair `MINUS_PREFIX` `"\`-\`"`)
    (name_pair `SUFFIX_Q` `"\`?\`"`)
    (name_pair `SUFFIX_BANG` `"\`!\`"`)
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
    (name_pair `PRE` `"\`pre\`"`)
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
    (name_pair `"=!"` `"\`=!\`"`)
    (name_pair `"<-"` `"\`<-\`"`)
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
    (name_pair `"%"` `"\`%\`"`))
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
    (name_pair `unary` `"an operand"`))
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
      ((ref `zig`))
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
            ((lit `"&="`))
            ((lit `"|="`))
            ((lit `"^="`))
            ((lit `"<<="`))
            ((lit `">>="`))))
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
        (lit `"=!"`)
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
      ((label
          `target`
          (ref `postfix`))
        (lit `"<-"`)
        (label
          `value`
          (ref `tail`)))
      (node
        `set`
        (named
          `op`
          (tag `move`)))
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
      ((label
          `target`
          (ref `name`))
        (lit `":"`)
        (label
          `type`
          (ref `type`))
        (lit `"=!"`)
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
      ((tok `DROP_STMT`)
        (label
          `name`
          (ref `name`)))
      (node `drop`)
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
      ((tok `PRE`)
        (label
          `body`
          (ref `block`)))
      (node `pre_block`)
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
          (ref `name`)))
      (node `use`)
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
              `params`
              (ref `params`))))
        (group
          opt
          ((label
              `returns`
              (ref `returns`))))
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
              `params`
              (ref `params`))))
        (label
          `body`
          (ref `block`)))
      (node `sub`)
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
      ((skip
          (ref `lparen`))
        (list_req
          `L`
          (plain `field`))
        (lit `")"`))
      (list
        (spread `2`))
      _)
    (alt
      _
      ((skip
          (ref `lparen`))
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
      ((tok `PRE`)
        (label
          `name`
          (ref `fname`))
        (lit `":"`)
        (label
          `type`
          (ref `type`)))
      (node `pre_param`)
      _)
    (alt
      _
      ((tok `READ_PFX`)
        (label
          `operand`
          (ref `fname`)))
      (node `read`)
      _)
    (alt
      _
      ((tok `WRITE_PFX`)
        (label
          `operand`
          (ref `fname`)))
      (node `write`)
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
          `params`
          (ref `params`))
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
      _)
    (alt
      _
      ((tok `TYPE`)
        (label
          `name`
          (ref `name`))
        (group
          opt
          ((label
              `params`
              (ref `params`))))
        (tok `INDENT`)
        (label
          `members`
          (ref `members`))
        (tok `OUTDENT`))
      (node `generic_type`)
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
          (ref `dparams`))
        (label
          `body`
          (ref `block`)))
      (node `drop_decl`)
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
        (label
          `name`
          (tok `STRING_DQ`))
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
              (ref `returns`)))))
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
    (name `zig`)
    (alt
      _
      ((tok `ZIG`)
        (label
          `code`
          (group
            _
            ((tok `STRING_DQ`))
            ((tok `STRING_SQ`)))))
      (node `zig`)
      _))
  (rule
    (name `type`)
    (alt
      _
      ((tok `READ_PFX`)
        (label
          `type`
          (ref `type`)))
      (node `borrow_read`)
      _)
    (alt
      _
      ((tok `WRITE_PFX`)
        (label
          `type`
          (ref `type`)))
      (node `borrow_write`)
      _)
    (alt
      _
      ((tok `SHARE_PFX`)
        (label
          `type`
          (ref `type`)))
      (node `shared`)
      _)
    (alt
      _
      ((lit `"~"`)
        (label
          `operand`
          (ref `type`)))
      (node `weak`)
      _)
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
          (tok `INTEGER`))
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
      ((ref `tsuffix`))
      _
      _))
  (rule
    (name `tsuffix`)
    (alt
      _
      ((label
          `type`
          (ref `tsuffix`))
        (tok `SUFFIX_Q`))
      (node `optional`)
      _)
    (alt
      _
      ((label
          `type`
          (ref `tsuffix`))
        (tok `SUFFIX_BANG`))
      (node `error_union`)
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
      ((tok `TYPE`))
      _
      _)
    (alt
      _
      ((label
          `name`
          (ref `name`))
        (tok `LPAREN_CALL`)
        (group
          opt
          ((label
              `args`
              (list_req
                `L`
                (plain `type`)))))
        (lit `")"`))
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
      _)
    (alt
      _
      ((tok `PRE`)
        (label
          `value`
          (ref `value`)))
      (node `pre`)
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
      ((ref `logic`))
      _
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
      ((label
          `callee`
          (ref `postfix`))
        (label
          `args`
          (ref `cmdargs`)))
      (node `call`)
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
      ((label
          `value`
          (ref `value`))
        (tok `AS`)
        (label
          `name`
          (ref `name`)))
      (node `as`)
      _))
  (rule
    (name `if`)
    (alt
      _
      ((tok `IF`)
        (label
          `cond`
          (ref `ifcond`))
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
          (ref `ifcond`))
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
          (ref `ifcond`))
        (group
          opt
          ((lit `":"`)
            (label
              `step`
              (ref `simple`))))
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
    (name `for`)
    (alt
      _
      ((tok `FOR`)
        (tok `SHARE_PFX`)
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
          (ref `cond`))
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
          (tag `ptr`)))
      _)
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
          (ref `cond`))
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
          (ref `cond`))
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
          (ref `pattern`))
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
          (ref `pattern`))
        (label
          `body`
          (ref `block`)))
      (node `arm`)
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
      ((tok `ELSE`))
      _
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (label
          `operand`
          (tok `INTEGER`)))
      (node `neg`)
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
        (label
          `name`
          (ref `name`)))
      (node `enum_lit`)
      _)
    (alt
      _
      ((tok `DOT_LIT`)
        (label
          `name`
          (ref `name`))
        (tok `LPAREN_CALL`)
        (group
          opt
          ((label
              `bindings`
              (list_req
                `L`
                (plain `name`)))))
        (lit `")"`))
      (node `variant_pattern`)
      _))
  (rule
    (name `try_block`)
    (alt
      _
      ((tok `TRY`)
        (label
          `body`
          (ref `block`))
        (group
          opt
          ((label
              `catch`
              (ref `catch_part`)))))
      (node `try_block`)
      _))
  (rule
    (name `catch_part`)
    (alt
      _
      ((tok `CATCH`)
        (tok `BAR_CAPTURE`)
        (label
          `name`
          (ref `name`))
        (tok `BAR_CAPTURE`)
        (label
          `body`
          (ref `block`)))
      (node `catch_block`)
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
      ((tok `SHARE_PFX`)
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
        (ref `cmd`))
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
      ((tok `CLONE_PFX`)
        (label
          `name`
          (ref `name`)))
      (node `cap_clone`)
      _)
    (alt
      _
      ((tok `MOVE_PFX`)
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
      _))
  (rule
    (name `unary`)
    (alt
      _
      ((tok `MINUS_PREFIX`)
        (label
          `operand`
          (ref `unary`)))
      (node `neg`)
      _)
    (alt
      _
      ((tok `MOVE_PFX`)
        (label
          `operand`
          (ref `unary`)))
      (node `move`)
      _)
    (alt
      _
      ((tok `CLONE_PFX`)
        (label
          `operand`
          (ref `unary`)))
      (node `clone`)
      _)
    (alt
      _
      ((tok `READ_PFX`)
        (label
          `operand`
          (ref `unary`)))
      (node `read`)
      _)
    (alt
      _
      ((tok `WRITE_PFX`)
        (label
          `operand`
          (ref `unary`)))
      (node `write`)
      _)
    (alt
      _
      ((tok `SHARE_PFX`)
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
      ((tok `PIN_PFX`)
        (label
          `operand`
          (ref `unary`)))
      (node `pin`)
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
        (tok `LBRACKET_INDEX`)
        (label
          `index`
          (ref `expr`))
        (lit `"]"`))
      (node `index`)
      _)
    (alt
      _
      ((label
          `callee`
          (ref `postfix`))
        (tok `LPAREN_CALL`)
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
        (tok `SUFFIX_BANG`))
      (node `propagate`)
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
      ((tok `DOT_LIT`)
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
        (tok `LPAREN_CALL`)
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
              (list_req
                `L`
                (plain `expr`)))))
        (lit `"]"`))
      (node `array`)
      _)
    (alt
      _
      ((lit `"("`)
        (ref `tail`)
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
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`)
      (infix_op `"%"` `left`))))
