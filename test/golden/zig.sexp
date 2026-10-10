(grammar
  (lang `"zig"`)
  (section `lexer`)
  (tokens `tokens` `invalid` `identifier` `string_literal` `multiline_string_literal_line` `char_literal` `builtin` `number_literal` `doc_comment` `container_doc_comment` `bang` `pipe` `pipe_pipe` `pipe_equal` `equal` `equal_equal` `equal_angle_bracket_right` `bang_equal` `l_paren` `r_paren` `semicolon` `percent` `percent_equal` `l_brace` `r_brace` `l_bracket` `r_bracket` `period` `period_asterisk` `ellipsis2` `ellipsis3` `caret` `caret_equal` `plus` `plus_plus` `plus_equal` `plus_percent` `plus_percent_equal` `plus_pipe` `plus_pipe_equal` `minus` `minus_equal` `minus_percent` `minus_percent_equal` `minus_pipe` `minus_pipe_equal` `asterisk` `asterisk_equal` `asterisk_percent` `asterisk_percent_equal` `asterisk_pipe` `asterisk_pipe_equal` `arrow` `colon` `slash` `slash_equal` `comma` `ampersand` `ampersand_equal` `question_mark` `angle_bracket_left` `angle_bracket_left_equal` `angle_bracket_angle_bracket_left` `angle_bracket_angle_bracket_left_equal` `angle_bracket_angle_bracket_left_pipe` `angle_bracket_angle_bracket_left_pipe_equal` `angle_bracket_right` `angle_bracket_right_equal` `angle_bracket_angle_bracket_right` `angle_bracket_angle_bracket_right_equal` `tilde` `keyword_addrspace` `keyword_align` `keyword_allowzero` `keyword_and` `keyword_anyframe` `keyword_anytype` `keyword_asm` `keyword_break` `keyword_callconv` `keyword_catch` `keyword_comptime` `keyword_const` `keyword_continue` `keyword_defer` `keyword_else` `keyword_enum` `keyword_errdefer` `keyword_error` `keyword_export` `keyword_extern` `keyword_fn` `keyword_for` `keyword_if` `keyword_inline` `keyword_noalias` `keyword_noinline` `keyword_nosuspend` `keyword_opaque` `keyword_or` `keyword_orelse` `keyword_packed` `keyword_pub` `keyword_resume` `keyword_return` `keyword_linksection` `keyword_struct` `keyword_suspend` `keyword_switch` `keyword_test` `keyword_threadlocal` `keyword_try` `keyword_union` `keyword_unreachable` `keyword_var` `keyword_volatile` `keyword_while` `label` `break_colon` `ptr_star` `c_ptr` `enum_tag` `bad_doc_comment` `minus_prefix` `minus_percent_prefix` `ampersand_prefix` `asterisk_prefix` `pipe_payload` `bad_operator` `eof` `err`)
  (lex_rule
    `[\\r\\n]+`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule
    `'//' ([^!/\\x00-\\x1f\\x7f] [^\\x00-\\x1f\\x7f]* | '//' [^\\x00-\\x1f\\x7f]*)?`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule
    `'//' ([^!/\\x00-\\x1f\\x7f] [^\\x00-\\x1f\\x7f]* | '//' [^\\x00-\\x1f\\x7f]*)? "\\r\\n"`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule `'//' ([^!/\\x00-\\x1f\\x7f] [^\\x00-\\x1f\\x7f]* | '//' [^\\x00-\\x1f\\x7f]*)? ([\\x00-\\x09\\x0b\\x0c\\x0e-\\x1f\\x7f] | '\\r') [^\\n]*` _ `invalid`)
  (lex_rule `'///' ([^/\\x00-\\x1f\\x7f] [^\\x00-\\x1f\\x7f]*)? / "\\r\\n"` _ `doc_comment`)
  (lex_rule `'///' ([^/\\x00-\\x1f\\x7f] [^\\x00-\\x1f\\x7f]*)?` _ `doc_comment`)
  (lex_rule `'///' ([^/\\x00-\\x1f\\x7f] [^\\x00-\\x1f\\x7f]*)? ([\\x01-\\x09\\x0b\\x0c\\x0e-\\x1f\\x7f] | '\\r') [^\\n]*` _ `invalid`)
  (lex_rule `'//!' [^\\x00-\\x1f\\x7f]* / "\\r\\n"` _ `container_doc_comment`)
  (lex_rule `'//!' [^\\x00-\\x1f\\x7f]*` _ `container_doc_comment`)
  (lex_rule `'//!' [^\\x00-\\x1f\\x7f]* ([\\x01-\\x09\\x0b\\x0c\\x0e-\\x1f\\x7f] | '\\r') [^\\n]*` _ `invalid`)
  (lex_rule `'"' ([^"\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* '"'` _ `string_literal`)
  (lex_rule `'"' ([^"\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* ('\\\\'? | [\\x00-\\x09\\x0b-\\x1f\\x7f] [^\\n]* | '\\\\' [\\x01-\\x09\\x0b-\\x1f\\x7f] [^\\n]*)` _ `invalid`)
  (lex_rule `"'" ([^'\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* "'"` _ `char_literal`)
  (lex_rule `"'" ([^'\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* ('\\\\'? | [\\x00-\\x09\\x0b-\\x1f\\x7f] [^\\n]* | '\\\\' [\\x00-\\x09\\x0b-\\x1f\\x7f] [^\\n]*)` _ `invalid`)
  (lex_rule `'@' [A-Za-z_] [A-Za-z0-9_]*` _ `builtin`)
  (lex_rule `'@"' ([^"\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* '"'` _ `identifier`)
  (lex_rule `'@"' ([^"\\\\\\x00-\\x1f\\x7f] | '\\\\' [^\\x00-\\x1f\\x7f])* ('\\\\'? | [\\x00-\\x09\\x0b-\\x1f\\x7f] [^\\n]* | '\\\\' [\\x01-\\x09\\x0b-\\x1f\\x7f] [^\\n]*)` _ `invalid`)
  (lex_rule `'@' ([^"A-Za-z_\\n\\x00] [^\\n]*)?` _ `invalid`)
  (lex_rule `'\\\\\\\\' [^\\x00-\\x1f\\x7f]* / "\\r\\n"` _ `multiline_string_literal_line`)
  (lex_rule `'\\\\\\\\' [^\\x00-\\x1f\\x7f]*` _ `multiline_string_literal_line`)
  (lex_rule `'\\\\\\\\' [^\\x00-\\x1f\\x7f]* ([\\x00-\\x09\\x0b\\x0c\\x0e-\\x1f\\x7f] | '\\r') [^\\n]*` _ `invalid`)
  (lex_rule `'\\\\' ([^\\\\\\n\\x00] [^\\n]*)?` _ `invalid`)
  (lex_rule `[0-9] [_0-9a-zA-Z]* ([eEpP] [-+] ([_0-9a-zA-Z] | [eEpP] [-+])* | '.' ([_0-9a-zA-Z] | [eEpP] [-+]) ([_0-9a-zA-Z] | [eEpP] [-+])*)?` _ `number_literal`)
  (lex_rule `"addrspace"` _ `keyword_addrspace`)
  (lex_rule `"align"` _ `keyword_align`)
  (lex_rule `"allowzero"` _ `keyword_allowzero`)
  (lex_rule `"and"` _ `keyword_and`)
  (lex_rule `"anyframe"` _ `keyword_anyframe`)
  (lex_rule `"anytype"` _ `keyword_anytype`)
  (lex_rule `"asm"` _ `keyword_asm`)
  (lex_rule `"break"` _ `keyword_break`)
  (lex_rule `"callconv"` _ `keyword_callconv`)
  (lex_rule `"catch"` _ `keyword_catch`)
  (lex_rule `"comptime"` _ `keyword_comptime`)
  (lex_rule `"const"` _ `keyword_const`)
  (lex_rule `"continue"` _ `keyword_continue`)
  (lex_rule `"defer"` _ `keyword_defer`)
  (lex_rule `"else"` _ `keyword_else`)
  (lex_rule `"enum"` _ `keyword_enum`)
  (lex_rule `"errdefer"` _ `keyword_errdefer`)
  (lex_rule `"error"` _ `keyword_error`)
  (lex_rule `"export"` _ `keyword_export`)
  (lex_rule `"extern"` _ `keyword_extern`)
  (lex_rule `"fn"` _ `keyword_fn`)
  (lex_rule `"for"` _ `keyword_for`)
  (lex_rule `"if"` _ `keyword_if`)
  (lex_rule `"inline"` _ `keyword_inline`)
  (lex_rule `"noalias"` _ `keyword_noalias`)
  (lex_rule `"noinline"` _ `keyword_noinline`)
  (lex_rule `"nosuspend"` _ `keyword_nosuspend`)
  (lex_rule `"opaque"` _ `keyword_opaque`)
  (lex_rule `"or"` _ `keyword_or`)
  (lex_rule `"orelse"` _ `keyword_orelse`)
  (lex_rule `"packed"` _ `keyword_packed`)
  (lex_rule `"pub"` _ `keyword_pub`)
  (lex_rule `"resume"` _ `keyword_resume`)
  (lex_rule `"return"` _ `keyword_return`)
  (lex_rule `"linksection"` _ `keyword_linksection`)
  (lex_rule `"struct"` _ `keyword_struct`)
  (lex_rule `"suspend"` _ `keyword_suspend`)
  (lex_rule `"switch"` _ `keyword_switch`)
  (lex_rule `"test"` _ `keyword_test`)
  (lex_rule `"threadlocal"` _ `keyword_threadlocal`)
  (lex_rule `"try"` _ `keyword_try`)
  (lex_rule `"union"` _ `keyword_union`)
  (lex_rule `"unreachable"` _ `keyword_unreachable`)
  (lex_rule `"var"` _ `keyword_var`)
  (lex_rule `"volatile"` _ `keyword_volatile`)
  (lex_rule `"while"` _ `keyword_while`)
  (lex_rule `[A-Za-z_] [A-Za-z0-9_]*` _ `identifier`)
  (lex_rule `"!"` _ `bang`)
  (lex_rule `"!="` _ `bang_equal`)
  (lex_rule `"|"` _ `pipe`)
  (lex_rule `"||"` _ `pipe_pipe`)
  (lex_rule `"|="` _ `pipe_equal`)
  (lex_rule `"="` _ `equal`)
  (lex_rule `"=="` _ `equal_equal`)
  (lex_rule `"=>"` _ `equal_angle_bracket_right`)
  (lex_rule `"("` _ `l_paren`)
  (lex_rule `")"` _ `r_paren`)
  (lex_rule `";"` _ `semicolon`)
  (lex_rule `"%"` _ `percent`)
  (lex_rule `"%="` _ `percent_equal`)
  (lex_rule `"{"` _ `l_brace`)
  (lex_rule `"}"` _ `r_brace`)
  (lex_rule `"["` _ `l_bracket`)
  (lex_rule `"]"` _ `r_bracket`)
  (lex_rule `"."` _ `period`)
  (lex_rule `".*"` _ `period_asterisk`)
  (lex_rule `".."` _ `ellipsis2`)
  (lex_rule `"..."` _ `ellipsis3`)
  (lex_rule `"^"` _ `caret`)
  (lex_rule `"^="` _ `caret_equal`)
  (lex_rule `"+"` _ `plus`)
  (lex_rule `"++"` _ `plus_plus`)
  (lex_rule `"+="` _ `plus_equal`)
  (lex_rule `"+%"` _ `plus_percent`)
  (lex_rule `"+%="` _ `plus_percent_equal`)
  (lex_rule `"+|"` _ `plus_pipe`)
  (lex_rule `"+|="` _ `plus_pipe_equal`)
  (lex_rule `"-"` _ `minus`)
  (lex_rule `"-="` _ `minus_equal`)
  (lex_rule `"-%"` _ `minus_percent`)
  (lex_rule `"-%="` _ `minus_percent_equal`)
  (lex_rule `"-|"` _ `minus_pipe`)
  (lex_rule `"-|="` _ `minus_pipe_equal`)
  (lex_rule `"*"` _ `asterisk`)
  (lex_rule `"*="` _ `asterisk_equal`)
  (lex_rule `"*%"` _ `asterisk_percent`)
  (lex_rule `"*%="` _ `asterisk_percent_equal`)
  (lex_rule `"*|"` _ `asterisk_pipe`)
  (lex_rule `"*|="` _ `asterisk_pipe_equal`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule `":"` _ `colon`)
  (lex_rule `"/"` _ `slash`)
  (lex_rule `"/="` _ `slash_equal`)
  (lex_rule `","` _ `comma`)
  (lex_rule `"&"` _ `ampersand`)
  (lex_rule `"&="` _ `ampersand_equal`)
  (lex_rule `"?"` _ `question_mark`)
  (lex_rule `"<"` _ `angle_bracket_left`)
  (lex_rule `"<="` _ `angle_bracket_left_equal`)
  (lex_rule `"<<"` _ `angle_bracket_angle_bracket_left`)
  (lex_rule `"<<="` _ `angle_bracket_angle_bracket_left_equal`)
  (lex_rule `"<<|"` _ `angle_bracket_angle_bracket_left_pipe`)
  (lex_rule `"<<|="` _ `angle_bracket_angle_bracket_left_pipe_equal`)
  (lex_rule `">"` _ `angle_bracket_right`)
  (lex_rule `">="` _ `angle_bracket_right_equal`)
  (lex_rule `">>"` _ `angle_bracket_angle_bracket_right`)
  (lex_rule `">>="` _ `angle_bracket_angle_bracket_right_equal`)
  (lex_rule `"~"` _ `tilde`)
  (lex_rule `[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x23\\x24\\x60\\x7f-\\xff] [^\\n]*` _ `invalid`)
  (section `parser`)
  (schema
    (kind_decl
      (kinds `root`)
      (roles
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role rest `members` _ _))
      _
      _)
    (kind_decl
      (kinds `tokens`)
      (roles
        (role rest `tokens` _ _))
      _
      _)
    (kind_decl
      (kinds `container_decl`)
      (roles
        (role
          _
          `layout`
          (type `leaf`)
          opt)
        (role
          _
          `kind`
          (type `leaf`)
          _)
        (role
          _
          `enum`
          (type `leaf`)
          opt)
        (role _ `arg` _ opt)
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role rest `members` _ _))
      _
      _)
    (kind_decl
      (kinds `container_field`)
      (roles
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role
          _
          `comptime`
          (type `leaf`)
          opt)
        (role
          _
          `name`
          (type `leaf`)
          opt)
        (role _ `type` _ _)
        (role _ `align` _ opt)
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `test_decl`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          opt)
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `fn_decl`)
      (roles
        (role
          _
          `proto`
          (type `fn_proto`)
          _)
        (role
          _
          `body`
          (type `block`)
          _))
      _
      _)
    (kind_decl
      (kinds `fn_proto`)
      (roles
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role
          _
          `visib`
          (type `leaf`)
          opt)
        (role
          _
          `modifier`
          (type `leaf`)
          opt)
        (role
          _
          `lib_name`
          (type `leaf`)
          opt)
        (role
          _
          `name`
          (type `leaf`)
          opt)
        (role
          _
          `params`
          (type `group`)
          _)
        (role _ `align` _ opt)
        (role _ `addrspace` _ opt)
        (role _ `section` _ opt)
        (role _ `callconv` _ opt)
        (role
          _
          `bang`
          (type `leaf`)
          opt)
        (role _ `return_type` _ _))
      _
      _)
    (kind_decl
      (kinds `param`)
      (roles
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role
          _
          `modifier`
          (type `leaf`)
          opt)
        (role
          _
          `name`
          (type `leaf`)
          opt)
        (role _ `type` _ _))
      _
      _)
    (kind_decl
      (kinds `var_decl`)
      (roles
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role
          _
          `visib`
          (type `leaf`)
          opt)
        (role
          _
          `modifier`
          (type `leaf`)
          opt)
        (role
          _
          `lib_name`
          (type `leaf`)
          opt)
        (role
          _
          `threadlocal`
          (type `leaf`)
          opt)
        (role
          _
          `comptime`
          (type `leaf`)
          opt)
        (role
          _
          `mut`
          (type `leaf`)
          _)
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `type` _ opt)
        (role _ `align` _ opt)
        (role _ `addrspace` _ opt)
        (role _ `section` _ opt)
        (role _ `init` _ opt))
      _
      _)
    (kind_decl
      (kinds `block`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role rest `statements` _ _))
      _
      _)
    (kind_decl
      (kinds `comptime` `nosuspend` `resume`)
      (roles
        (role _ `operand` _ _))
      _
      _)
    (kind_decl
      (kinds `defer` `errdefer` `suspend`)
      (roles
        (role _ `body` _ _))
      _
      _)
    (kind_decl
      (kinds `assign`)
      (roles
        (role
          _
          `op`
          (type `leaf`)
          _)
        (role _ `target` _ _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `assign_destructure`)
      (roles
        (role
          _
          `comptime`
          (type `leaf`)
          opt)
        (role
          _
          `targets`
          (type `group`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `if`)
      (roles
        (role _ `cond` _ _)
        (role
          _
          `capture`
          (type `capture`)
          opt)
        (role _ `then` _ _)
        (role
          _
          `else_capture`
          (type `leaf`)
          opt)
        (role _ `else` _ opt))
      _
      _)
    (kind_decl
      (kinds `while`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role
          _
          `inline`
          (type `leaf`)
          opt)
        (role _ `cond` _ _)
        (role
          _
          `capture`
          (type `capture`)
          opt)
        (role _ `cont` _ opt)
        (role _ `then` _ _)
        (role
          _
          `else_capture`
          (type `leaf`)
          opt)
        (role _ `else` _ opt))
      _
      _)
    (kind_decl
      (kinds `for`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role
          _
          `inline`
          (type `leaf`)
          opt)
        (role
          _
          `inputs`
          (type `group`)
          _)
        (role
          _
          `captures`
          (type `group`)
          _)
        (role _ `then` _ _)
        (role _ `else` _ opt))
      _
      _)
    (kind_decl
      (kinds `for_range`)
      (roles
        (role _ `start` _ _)
        (role _ `end` _ opt))
      _
      _)
    (kind_decl
      (kinds `capture`)
      (roles
        (role
          _
          `ptr`
          (type `leaf`)
          opt)
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `switch`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role _ `cond` _ _)
        (role
          rest
          `cases`
          (type `switch_case`)
          _))
      _
      _)
    (kind_decl
      (kinds `switch_case`)
      (roles
        (role
          _
          `inline`
          (type `leaf`)
          opt)
        (role
          _
          `values`
          (type `group`)
          _)
        (role
          _
          `capture`
          (type `capture`)
          opt)
        (role
          _
          `index`
          (type `leaf`)
          opt)
        (role _ `body` _ _))
      _
      _)
    (kind_decl
      (kinds `switch_range`)
      (roles
        (role _ `start` _ _)
        (role _ `end` _ _))
      _
      _)
    (kind_decl
      (kinds `return`)
      (roles
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `break` `continue`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `binary`)
      (roles
        (role
          _
          `op`
          (type `leaf`)
          _)
        (role _ `lhs` _ _)
        (role _ `rhs` _ _))
      _
      _)
    (kind_decl
      (kinds `catch`)
      (roles
        (role _ `lhs` _ _)
        (role
          _
          `payload`
          (type `leaf`)
          opt)
        (role _ `rhs` _ _))
      _
      _)
    (kind_decl
      (kinds `bool_not` `negation` `bit_not` `negation_wrap` `address_of` `try`)
      (roles
        (role _ `operand` _ _))
      _
      _)
    (kind_decl
      (kinds `deref` `unwrap_optional` `grouped_expression`)
      (roles
        (role _ `operand` _ _))
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
      (kinds `builtin_call`)
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
      (kinds `field_access`)
      (roles
        (role _ `operand` _ _)
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `array_access`)
      (roles
        (role _ `operand` _ _)
        (role _ `index` _ _))
      _
      _)
    (kind_decl
      (kinds `slice`)
      (roles
        (role _ `operand` _ _)
        (role _ `start` _ _)
        (role _ `end` _ opt)
        (role _ `sentinel` _ opt))
      _
      _)
    (kind_decl
      (kinds `struct_init`)
      (roles
        (role _ `type` _ opt)
        (role
          rest
          `fields`
          (type `field_init`)
          _))
      _
      _)
    (kind_decl
      (kinds `field_init`)
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
      (kinds `array_init`)
      (roles
        (role _ `type` _ opt)
        (role rest `elements` _ _))
      _
      _)
    (kind_decl
      (kinds `enum_literal` `error_value`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `multiline_string_literal`)
      (roles
        (role
          rest
          `lines`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `asm`)
      (roles
        (role
          _
          `volatile`
          (type `leaf`)
          opt)
        (role _ `template` _ _)
        (role _ `clobbers` _ opt)
        (role
          rest
          `items`
          (type `asm_output` `asm_input`)
          _))
      _
      _)
    (kind_decl
      (kinds `asm_output`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `constraint`
          (type `leaf`)
          _)
        (role
          _
          `variable`
          (type `leaf`)
          opt)
        (role _ `type` _ opt))
      _
      _)
    (kind_decl
      (kinds `asm_input`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `constraint`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `error_union`)
      (roles
        (role _ `error_set` _ _)
        (role _ `payload` _ _))
      _
      _)
    (kind_decl
      (kinds `optional_type`)
      (roles
        (role _ `child` _ _))
      _
      _)
    (kind_decl
      (kinds `anyframe_type`)
      (roles
        (role _ `result` _ _))
      _
      _)
    (kind_decl
      (kinds `array_type`)
      (roles
        (role _ `len` _ _)
        (role _ `sentinel` _ opt)
        (role _ `elem` _ _))
      _
      _)
    (kind_decl
      (kinds `ptr_type`)
      (roles
        (role
          _
          `size`
          (type
            (tagset `tag` `one` `many` `slice` `c`))
          _)
        (role _ `sentinel` _ opt)
        (role _ `align` _ opt)
        (role _ `bit_start` _ opt)
        (role _ `bit_end` _ opt)
        (role _ `addrspace` _ opt)
        (role _ `child` _ _)
        (role
          rest
          `quals`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `error_set_decl`)
      (roles
        (role
          rest
          `members`
          (type `error_name`)
          _))
      _
      _)
    (kind_decl
      (kinds `error_name`)
      (roles
        (role
          _
          `doc`
          (type `group`)
          opt)
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `invalid` `identifier` `string_literal` `multiline_string_literal_line` `char_literal` `builtin`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `number_literal` `doc_comment` `container_doc_comment` `bang` `pipe` `pipe_pipe` `pipe_equal`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `equal` `equal_equal` `equal_angle_bracket_right` `bang_equal` `l_paren` `r_paren` `semicolon`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `percent` `percent_equal` `l_brace` `r_brace` `l_bracket` `r_bracket` `period` `period_asterisk`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `ellipsis2` `ellipsis3` `caret` `caret_equal` `plus` `plus_plus` `plus_equal` `plus_percent`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `plus_percent_equal` `plus_pipe` `plus_pipe_equal` `minus` `minus_equal` `minus_percent`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `minus_percent_equal` `minus_pipe` `minus_pipe_equal` `asterisk` `asterisk_equal`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `asterisk_percent` `asterisk_percent_equal` `asterisk_pipe` `asterisk_pipe_equal` `arrow` `colon`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `slash` `slash_equal` `comma` `ampersand` `ampersand_equal` `question_mark` `angle_bracket_left`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `angle_bracket_left_equal` `angle_bracket_angle_bracket_left`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `angle_bracket_angle_bracket_left_equal` `angle_bracket_angle_bracket_left_pipe`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `angle_bracket_angle_bracket_left_pipe_equal` `angle_bracket_right` `angle_bracket_right_equal`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `angle_bracket_angle_bracket_right` `angle_bracket_angle_bracket_right_equal` `tilde`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_addrspace` `keyword_align` `keyword_allowzero` `keyword_and` `keyword_anyframe`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_anytype` `keyword_asm` `keyword_break` `keyword_callconv` `keyword_catch`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_comptime` `keyword_const` `keyword_continue` `keyword_defer` `keyword_else` `keyword_enum`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_errdefer` `keyword_error` `keyword_export` `keyword_extern` `keyword_fn` `keyword_for`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_if` `keyword_inline` `keyword_noalias` `keyword_noinline` `keyword_nosuspend`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_opaque` `keyword_or` `keyword_orelse` `keyword_packed` `keyword_pub` `keyword_resume`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_return` `keyword_linksection` `keyword_struct` `keyword_suspend` `keyword_switch`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_test` `keyword_threadlocal` `keyword_try` `keyword_union` `keyword_unreachable`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `keyword_var` `keyword_volatile` `keyword_while` `err` `label` `break_colon` `ptr_star` `c_ptr`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `enum_tag` `bad_doc_comment` `minus_prefix` `minus_percent_prefix` `ampersand_prefix`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `asterisk_prefix` `pipe_payload` `bad_operator`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _))
  (manifest
    (conflict `shift` `jump → "return"` _ `4` `# \`return - x\`, \`return & x\`, \`return * T\`: the operand of return is parseExpr, which a prefix operator starts`)
    (conflict `shift` `jump → "break"` _ `4` `# \`break - x\`: the operand of break is parseExpr, which a prefix operator starts`)
    (conflict `shift` `jump → "break" break_label` _ `4` `# \`break :blk - x\`: the operand of a labeled break is parseExpr, which a prefix operator starts`)
    (conflict `shift` `jump → "continue"` _ `4` `# \`continue - x\`: the operand of continue is parseExpr, which a prefix operator starts`)
    (conflict `shift` `jump → "continue" break_label` _ `4` `# \`continue :blk - x\`: the operand of a labeled continue is parseExpr, which a prefix operator starts`)
    (conflict `reduce` `for_expr → "for" "(" L(for_item) ","? ")" ptr_list_payload bool_or_expr` `for_expr → "inline" "for" "(" L(for_item) ","? ")" ptr_list_payload bool_or_expr` `3` `# \`inline for\`/\`inline while\` as a prong body: \`inline\` is the prong's flag (parseSwitchProng)`)
    (conflict `reduce` `for_expr → "for" "(" L(for_item) ","? ")" ptr_list_payload bool_or_expr "else" bool_or_expr` `for_expr → "inline" "for" "(" L(for_item) ","? ")" ptr_list_payload bool_or_expr "else" bool_or_expr` `3` `# \`inline for\`/\`inline while\` as a prong body: \`inline\` is the prong's flag (parseSwitchProng)`)
    (conflict `reduce` `while_expr → "while" "(" bool_or_expr ")" ptr_payload while_continue_expr bool_or_expr` `while_expr → "inline" "while" "(" bool_or_expr ")" ptr_payload while_continue_expr bool_or_expr` `3` `# \`inline for\`/\`inline while\` as a prong body: \`inline\` is the prong's flag (parseSwitchProng)`)
    (conflict `reduce` `while_expr → "while" "(" bool_or_expr ")" ptr_payload while_continue_expr bool_or_expr "else" else_payload bool_or_expr` `while_expr → "inline" "while" "(" bool_or_expr ")" ptr_payload while_continue_expr bool_or_expr "else" else_payload bool_or_expr` `3` `# \`inline for\`/\`inline while\` as a prong body: \`inline\` is the prong's flag (parseSwitchProng)`))
  (rule
    (start `root`)
    (alt
      _
      ((ref `container_docs`)
        (ref `members`))
      (node
        `root`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (start `tokens`)
    (alt
      _
      ((quantified
          (ref `token`)
          (zero_plus)))
      (node
        `tokens`
        (spread `1`))
      _))
  (rule
    (name `container_docs`)
    (alt _ () _ _)
    (alt
      _
      ((quantified
          (tok `CONTAINER_DOC_COMMENT`)
          (one_plus)))
      _
      _))
  (rule
    (name `members`)
    (alt _ () _ _)
    (alt
      _
      ((ref `container_members`))
      _
      _))
  (rule
    (name `container_members`)
    (alt
      _
      ((ref `decls`))
      _
      _)
    (alt
      _
      ((ref `fields`))
      _
      _)
    (alt
      _
      ((ref `rest`))
      _
      _)
    (alt
      _
      ((ref `container_field`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `decls`)
        (ref `container_field`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `fields`)
        (ref `container_field`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `decls`)
    (alt
      _
      ((ref `container_decl`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `decls`)
        (ref `container_decl`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `fields`)
    (alt
      _
      ((ref `container_field`)
        (lit `","`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `decls`)
        (ref `container_field`)
        (lit `","`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `fields`)
        (ref `container_field`)
        (lit `","`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `rest`)
    (alt
      _
      ((ref `fields`)
        (ref `container_decl`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `rest`)
        (ref `container_decl`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `docs`)
    (alt
      _
      ((quantified
          (tok `DOC_COMMENT`)
          (one_plus)))
      _
      _))
  (rule
    (name `container_decl`)
    (alt
      _
      ((lit `"test"`)
        (group
          opt
          ((ref `test_name`)))
        (ref `block`))
      (node
        `test_decl`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `block`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((ref `fn_decl_proto`)
        (lit `";"`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `fn_decl_proto`)
        (ref `block`))
      (node
        `fn_decl`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `fn_extern_proto`)
        (lit `";"`))
      (pos `1`)
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (group
          opt
          ((lit `"threadlocal"`)))
        (ref `var_mut`)
        (ref `var_name`)
        (ref `var_type`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (ref `var_init`)
        (lit `";"`))
      (node
        `var_decl`
        (pos `1`)
        (pos `2`)
        (null)
        (null)
        (pos `3`)
        (null)
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (lit `"export"`)
        (group
          opt
          ((lit `"threadlocal"`)))
        (ref `var_mut`)
        (ref `var_name`)
        (ref `var_type`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (ref `var_init`)
        (lit `";"`))
      (node
        `var_decl`
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (null)
        (pos `4`)
        (null)
        (pos `5`)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `11`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (lit `"extern"`)
        (group
          opt
          ((tok `STRING_LITERAL`)))
        (group
          opt
          ((lit `"threadlocal"`)))
        (ref `var_mut`)
        (ref `var_name`)
        (ref `var_type`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (ref `var_init`)
        (lit `";"`))
      (node
        `var_decl`
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (null)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `11`)
        (pos `12`))
      _))
  (rule
    (name `test_name`)
    (alt
      _
      ((tok `STRING_LITERAL`))
      _
      _)
    (alt
      _
      ((tok `IDENTIFIER`))
      _
      _))
  (rule
    (name `fn_prefix`)
    (alt
      _
      ((lit `"export"`))
      _
      _)
    (alt
      _
      ((lit `"inline"`))
      _
      _)
    (alt
      _
      ((lit `"noinline"`))
      _
      _))
  (rule
    (name `fn_decl_proto`)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (group
          opt
          ((ref `fn_prefix`)))
        (lit `"fn"`)
        (group
          opt
          ((tok `IDENTIFIER`)))
        (ref `param_decl_list`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (ref `fn_callconv`)
        (group
          opt
          ((lit `"!"`)))
        (ref `type_expr`))
      (node
        `fn_proto`
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (null)
        (pos `5`)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `11`)
        (pos `12`))
      _))
  (rule
    (name `fn_extern_proto`)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (lit `"extern"`)
        (group
          opt
          ((tok `STRING_LITERAL`)))
        (lit `"fn"`)
        (group
          opt
          ((tok `IDENTIFIER`)))
        (ref `param_decl_list`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (ref `fn_callconv`)
        (group
          opt
          ((lit `"!"`)))
        (ref `type_expr`))
      (node
        `fn_proto`
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `11`)
        (pos `12`)
        (pos `13`))
      _))
  (rule
    (name `fn_proto`)
    (alt
      _
      ((lit `"fn"`)
        (group
          opt
          ((tok `IDENTIFIER`)))
        (ref `param_decl_list`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (ref `fn_callconv`)
        (group
          opt
          ((lit `"!"`)))
        (ref `type_expr`))
      (node
        `fn_proto`
        (null)
        (null)
        (null)
        (null)
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `9`))
      _))
  (rule
    (name `var_mut`)
    (alt
      _
      ((lit `"const"`))
      _
      _)
    (alt
      _
      ((lit `"var"`))
      _
      _))
  (rule
    (name `var_name`)
    (alt
      _
      ((tok `IDENTIFIER`))
      _
      _)
    (alt
      _
      ((tok `LABEL`))
      _
      _))
  (rule
    (name `var_type`)
    (alt _ () _ _)
    (alt
      _
      ((lit `":"`)
        (ref `type_expr`))
      (pos `2`)
      _))
  (rule
    (name `var_align`)
    (alt _ () _ _)
    (alt
      _
      ((ref `byte_align`))
      _
      _))
  (rule
    (name `var_addrspace`)
    (alt _ () _ _)
    (alt
      _
      ((ref `addr_space`))
      _
      _))
  (rule
    (name `var_section`)
    (alt _ () _ _)
    (alt
      _
      ((ref `link_section`))
      _
      _))
  (rule
    (name `var_init`)
    (alt _ () _ _)
    (alt
      _
      ((lit `"="`)
        (ref `expr`))
      (pos `2`)
      _))
  (rule
    (name `fn_callconv`)
    (alt _ () _ _)
    (alt
      _
      ((ref `call_conv`))
      _
      _))
  (rule
    (name `container_field`)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"comptime"`)))
        (ref `field_name`)
        (lit `":"`)
        (ref `type_expr`)
        (group
          opt
          ((ref `byte_align`)))
        (group
          opt
          ((lit `"="`)
            (ref `expr`))))
      (node
        `container_field`
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `5`)
        (pos `6`)
        (pos `8`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (ref `type_expr_f`)
        (group
          opt
          ((ref `byte_align`)))
        (group
          opt
          ((lit `"="`)
            (ref `expr`))))
      (node
        `container_field`
        (pos `1`)
        (null)
        (null)
        (pos `2`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (lit `"comptime"`)
        (ref `type_expr_n`)
        (group
          opt
          ((ref `byte_align`)))
        (group
          opt
          ((lit `"="`)
            (ref `expr`))))
      (node
        `container_field`
        (pos `1`)
        (pos `2`)
        (null)
        (pos `3`)
        (pos `4`)
        (pos `6`))
      _))
  (rule
    (name `field_name`)
    (alt
      _
      ((tok `IDENTIFIER`))
      _
      _)
    (alt
      _
      ((tok `LABEL`))
      _
      _))
  (rule
    (name `block_statement`)
    (alt
      _
      ((lit `"comptime"`)
        (ref `block_expr`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"nosuspend"`)
        (ref `block_expr_statement`))
      (node
        `nosuspend`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"suspend"`)
        (ref `block_expr_statement`))
      (node
        `suspend`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"defer"`)
        (ref `block_expr_statement`))
      (node
        `defer`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"errdefer"`)
        (ref `block_expr_statement`))
      (node
        `errdefer`
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_statement`))
      _
      _)
    (alt
      _
      ((ref `labeled_statement`))
      _
      _)
    (alt
      _
      ((ref `var_mut`)
        (ref `var_name`)
        (ref `var_type`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `var_decl`
        (null)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `8`))
      _)
    (alt
      _
      ((ref `expr_s`)
        (lit `";"`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `expr_s`)
        (ref `assign_op`)
        (ref `expr`)
        (lit `";"`))
      (node
        `assign`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_s`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `assign_destructure`
        (null)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `var_mut`)
        (ref `var_name`)
        (ref `var_type`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `var_decl`
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `7`)
        (pos `9`))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `expr_c`)
        (lit `";"`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `expr_c`)
        (ref `assign_op`)
        (ref `expr`)
        (lit `";"`))
      (node
        `comptime`
        (node
          `assign`
          (pos `3`)
          (pos `2`)
          (pos `4`)))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `destructure_c`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `assign_destructure`
        (pos `1`)
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `statement`)
    (alt
      _
      ((lit `"comptime"`)
        (ref `block_expr`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `expr_c`)
        (lit `";"`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `expr_c`)
        (ref `assign_op`)
        (ref `expr`)
        (lit `";"`))
      (node
        `comptime`
        (node
          `assign`
          (pos `3`)
          (pos `2`)
          (pos `4`)))
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `destructure_ec`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `assign_destructure`
        (pos `1`)
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"nosuspend"`)
        (ref `block_expr_statement`))
      (node
        `nosuspend`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"suspend"`)
        (ref `block_expr_statement`))
      (node
        `suspend`
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_statement`))
      _
      _)
    (alt
      _
      ((ref `labeled_statement`))
      _
      _)
    (alt
      _
      ((ref `assign_s`)
        (lit `";"`))
      (pos `1`)
      _))
  (rule
    (name `if_statement`)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `block_expr`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `block_expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `statement`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`)
        (pos `8`)
        (pos `9`))
      _)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `assign_c`)
        (lit `";"`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `assign_c`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `statement`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`)
        (pos `8`)
        (pos `9`))
      _))
  (rule
    (name `labeled_statement`)
    (alt
      _
      ((ref `block_expr`))
      _
      _)
    (alt
      _
      ((ref `for_statement`))
      _
      _)
    (alt
      _
      ((ref `while_statement`))
      _
      _)
    (alt
      _
      ((ref `switch_expr`))
      _
      _)
    (alt
      _
      ((ref `labeled_switch`))
      _
      _))
  (rule
    (name `for_statement`)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `block_expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `block_expr`)
        (lit `"else"`)
        (ref `statement`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`)
        (pos `12`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `assign_c`)
        (lit `";"`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `assign_c`)
        (lit `"else"`)
        (ref `statement`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`)
        (pos `12`))
      _))
  (rule
    (name `while_statement`)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `block_expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `block_expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `statement`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `12`)
        (pos `13`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `assign_c`)
        (lit `";"`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `assign_c`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `statement`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `12`)
        (pos `13`))
      _))
  (rule
    (name `block_expr_statement`)
    (alt
      _
      ((ref `block_expr`))
      _
      _)
    (alt
      _
      ((ref `assign_c`)
        (lit `";"`))
      (pos `1`)
      _))
  (rule
    (name `block_expr`)
    (alt
      _
      ((ref `block`))
      _
      _)
    (alt
      _
      ((ref `labeled_block`))
      _
      _))
  (rule
    (name `block`)
    (alt
      _
      ((lit `"{"`)
        (quantified
          (ref `block_statement`)
          (zero_plus))
        (lit `"}"`))
      (node
        `block`
        (null)
        (spread `2`))
      _))
  (rule
    (name `labeled_block`)
    (alt
      _
      ((tok `LABEL`)
        (lit `":"`)
        (lit `"{"`)
        (quantified
          (ref `block_statement`)
          (zero_plus))
        (lit `"}"`))
      (node
        `block`
        (pos `1`)
        (spread `4`))
      _))
  (rule
    (name `destructure_s`)
    (alt
      _
      ((ref `destructure_head_s`)
        (lit `","`)
        (ref `destructure_item`))
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_s`)
        (lit `","`)
        (ref `destructure_item`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `destructure_c`)
    (alt
      _
      ((ref `destructure_head_c`)
        (lit `","`)
        (ref `destructure_item`))
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_c`)
        (lit `","`)
        (ref `destructure_item`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `destructure_head_s`)
    (alt
      _
      ((ref `destructure_var`))
      _
      _)
    (alt
      _
      ((ref `expr_s`))
      _
      _))
  (rule
    (name `destructure_head_c`)
    (alt
      _
      ((ref `destructure_var`))
      _
      _)
    (alt
      _
      ((ref `expr_c`))
      _
      _))
  (rule
    (name `destructure_item`)
    (alt
      _
      ((ref `destructure_var`))
      _
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `destructure_var`)
    (alt
      _
      ((ref `var_mut`)
        (ref `var_name`)
        (ref `var_type`)
        (ref `var_align`)
        (ref `var_addrspace`)
        (ref `var_section`))
      (node
        `var_decl`
        (null)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (null))
      _))
  (rule
    (name `assign_expr`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `expr`)
        (ref `assign_op`)
        (ref `expr`))
      (node
        `assign`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure`)
        (lit `"="`)
        (ref `expr`))
      (node
        `assign_destructure`
        (null)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `assign_s`)
    (alt
      _
      ((ref `expr_s`))
      _
      _)
    (alt
      _
      ((ref `expr_s`)
        (ref `assign_op`)
        (ref `expr`))
      (node
        `assign`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_es`)
        (lit `"="`)
        (ref `expr`))
      (node
        `assign_destructure`
        (null)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `assign_c`)
    (alt
      _
      ((ref `expr_c`))
      _
      _)
    (alt
      _
      ((ref `expr_c`)
        (ref `assign_op`)
        (ref `expr`))
      (node
        `assign`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_ec`)
        (lit `"="`)
        (ref `expr`))
      (node
        `assign_destructure`
        (null)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `single_assign_expr`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `expr`)
        (ref `assign_op`)
        (ref `expr`))
      (node
        `assign`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `destructure`)
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
      ((ref `destructure`)
        (lit `","`)
        (ref `expr`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `destructure_es`)
    (alt
      _
      ((ref `expr_s`)
        (lit `","`)
        (ref `expr`))
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_es`)
        (lit `","`)
        (ref `expr`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `destructure_ec`)
    (alt
      _
      ((ref `expr_c`)
        (lit `","`)
        (ref `expr`))
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `destructure_ec`)
        (lit `","`)
        (ref `expr`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `bool_or_expr`))
      _
      _))
  (rule
    (name `expr_s`)
    (alt
      _
      ((ref `bool_or_expr_s`))
      _
      _))
  (rule
    (name `expr_c`)
    (alt
      _
      ((ref `bool_or_expr_c`))
      _
      _))
  (rule
    (name `expr_p`)
    (alt
      _
      ((ref `bool_or_expr_p`))
      _
      _))
  (rule
    (name `index_expr`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `expr_p`))
      _
      _))
  (rule
    (name `bool_or_expr`)
    (alt
      _
      ((ref `bool_and_expr`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_k`)
        (lit `"or"`)
        (ref `bool_and_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_k`)
    (alt
      _
      ((ref `bool_and_expr_k`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_k`)
        (lit `"or"`)
        (ref `bool_and_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_s`)
    (alt
      _
      ((ref `bool_and_expr_s`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_sk`)
        (lit `"or"`)
        (ref `bool_and_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_sk`)
    (alt
      _
      ((ref `bool_and_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_sk`)
        (lit `"or"`)
        (ref `bool_and_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_c`)
    (alt
      _
      ((ref `bool_and_expr_c`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_ck`)
        (lit `"or"`)
        (ref `bool_and_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_ck`)
    (alt
      _
      ((ref `bool_and_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_ck`)
        (lit `"or"`)
        (ref `bool_and_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_p`)
    (alt
      _
      ((ref `bool_and_expr_p`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_pk`)
        (lit `"or"`)
        (ref `bool_and_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_expr_pk`)
    (alt
      _
      ((ref `bool_and_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `bool_or_expr_pk`)
        (lit `"or"`)
        (ref `bool_and_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr`)
    (alt
      _
      ((ref `compare_expr`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_k`)
        (lit `"and"`)
        (ref `compare_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_k`)
    (alt
      _
      ((ref `compare_expr_k`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_k`)
        (lit `"and"`)
        (ref `compare_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_s`)
    (alt
      _
      ((ref `compare_expr_s`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_sk`)
        (lit `"and"`)
        (ref `compare_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_sk`)
    (alt
      _
      ((ref `compare_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_sk`)
        (lit `"and"`)
        (ref `compare_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_c`)
    (alt
      _
      ((ref `compare_expr_c`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_ck`)
        (lit `"and"`)
        (ref `compare_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_ck`)
    (alt
      _
      ((ref `compare_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_ck`)
        (lit `"and"`)
        (ref `compare_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_p`)
    (alt
      _
      ((ref `compare_expr_p`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_pk`)
        (lit `"and"`)
        (ref `compare_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_expr_pk`)
    (alt
      _
      ((ref `compare_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `bool_and_expr_pk`)
        (lit `"and"`)
        (ref `compare_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr`)
    (alt
      _
      ((ref `bitwise_expr`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_k`)
        (ref `compare_op`)
        (ref `bitwise_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_k`)
    (alt
      _
      ((ref `bitwise_expr_k`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_k`)
        (ref `compare_op`)
        (ref `bitwise_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_s`)
    (alt
      _
      ((ref `bitwise_expr_s`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_sk`)
        (ref `compare_op`)
        (ref `bitwise_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_sk`)
    (alt
      _
      ((ref `bitwise_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_sk`)
        (ref `compare_op`)
        (ref `bitwise_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_c`)
    (alt
      _
      ((ref `bitwise_expr_c`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_ck`)
        (ref `compare_op`)
        (ref `bitwise_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_ck`)
    (alt
      _
      ((ref `bitwise_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_ck`)
        (ref `compare_op`)
        (ref `bitwise_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_p`)
    (alt
      _
      ((ref `bitwise_expr_p`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_pk`)
        (ref `compare_op`)
        (ref `bitwise_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_expr_pk`)
    (alt
      _
      ((ref `bitwise_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_pk`)
        (ref `compare_op`)
        (ref `bitwise_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bitwise_expr`)
    (alt
      _
      ((ref `bit_shift_expr`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_k`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_k`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_k`)
    (alt
      _
      ((ref `bit_shift_expr_k`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_k`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_k`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_s`)
    (alt
      _
      ((ref `bit_shift_expr_s`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_sk`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_sk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_sk`)
    (alt
      _
      ((ref `bit_shift_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_sk`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_sk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_c`)
    (alt
      _
      ((ref `bit_shift_expr_c`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_ck`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_ck`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_ck`)
    (alt
      _
      ((ref `bit_shift_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_ck`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_ck`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_p`)
    (alt
      _
      ((ref `bit_shift_expr_p`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_pk`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_pk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_expr_pk`)
    (alt
      _
      ((ref `bit_shift_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_expr_pk`)
        (ref `bitwise_op`)
        (ref `bit_shift_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_expr_pk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_expr_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bit_shift_expr`)
    (alt
      _
      ((ref `addition_expr`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_k`)
        (ref `bit_shift_op`)
        (ref `addition_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_k`)
    (alt
      _
      ((ref `addition_expr_k`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_k`)
        (ref `bit_shift_op`)
        (ref `addition_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_s`)
    (alt
      _
      ((ref `addition_expr_s`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_sk`)
        (ref `bit_shift_op`)
        (ref `addition_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_sk`)
    (alt
      _
      ((ref `addition_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_sk`)
        (ref `bit_shift_op`)
        (ref `addition_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_c`)
    (alt
      _
      ((ref `addition_expr_c`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_ck`)
        (ref `bit_shift_op`)
        (ref `addition_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_ck`)
    (alt
      _
      ((ref `addition_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_ck`)
        (ref `bit_shift_op`)
        (ref `addition_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_p`)
    (alt
      _
      ((ref `addition_expr_p`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_pk`)
        (ref `bit_shift_op`)
        (ref `addition_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_expr_pk`)
    (alt
      _
      ((ref `addition_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_expr_pk`)
        (ref `bit_shift_op`)
        (ref `addition_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr`)
    (alt
      _
      ((ref `multiply_expr`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_k`)
        (ref `addition_op`)
        (ref `multiply_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_k`)
    (alt
      _
      ((ref `multiply_expr_k`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_k`)
        (ref `addition_op`)
        (ref `multiply_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_s`)
    (alt
      _
      ((ref `multiply_expr_s`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_sk`)
        (ref `addition_op`)
        (ref `multiply_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_sk`)
    (alt
      _
      ((ref `multiply_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_sk`)
        (ref `addition_op`)
        (ref `multiply_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_c`)
    (alt
      _
      ((ref `multiply_expr_c`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_ck`)
        (ref `addition_op`)
        (ref `multiply_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_ck`)
    (alt
      _
      ((ref `multiply_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_ck`)
        (ref `addition_op`)
        (ref `multiply_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_p`)
    (alt
      _
      ((ref `multiply_expr_p`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_pk`)
        (ref `addition_op`)
        (ref `multiply_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_expr_pk`)
    (alt
      _
      ((ref `multiply_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `addition_expr_pk`)
        (ref `addition_op`)
        (ref `multiply_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr`)
    (alt
      _
      ((ref `prefix_expr`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_k`)
        (ref `multiply_op`)
        (ref `prefix_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_k`)
    (alt
      _
      ((ref `prefix_expr_k`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_k`)
        (ref `multiply_op`)
        (ref `prefix_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_s`)
    (alt
      _
      ((ref `prefix_expr_s`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_sk`)
        (ref `multiply_op`)
        (ref `prefix_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_sk`)
    (alt
      _
      ((ref `prefix_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_sk`)
        (ref `multiply_op`)
        (ref `prefix_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_c`)
    (alt
      _
      ((ref `prefix_expr_c`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_ck`)
        (ref `multiply_op`)
        (ref `prefix_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_ck`)
    (alt
      _
      ((ref `prefix_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_ck`)
        (ref `multiply_op`)
        (ref `prefix_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_p`)
    (alt
      _
      ((ref `prefix_expr_p`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_pk`)
        (ref `multiply_op`)
        (ref `prefix_expr`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_expr_pk`)
    (alt
      _
      ((ref `prefix_expr_pk`))
      _
      _)
    (alt
      _
      ((ref `multiply_expr_pk`)
        (ref `multiply_op`)
        (ref `prefix_expr_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `prefix_expr`)
    (alt
      _
      ((ref `primary_expr`))
      _
      _)
    (alt
      _
      ((ref `prefixed`))
      _
      _))
  (rule
    (name `prefix_expr_k`)
    (alt
      _
      ((ref `primary_expr_k`))
      _
      _)
    (alt
      _
      ((ref `prefixed_k`))
      _
      _))
  (rule
    (name `prefix_expr_s`)
    (alt
      _
      ((ref `primary_expr_s`))
      _
      _)
    (alt
      _
      ((ref `prefixed`))
      _
      _))
  (rule
    (name `prefix_expr_sk`)
    (alt
      _
      ((ref `primary_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `prefixed_k`))
      _
      _))
  (rule
    (name `prefix_expr_c`)
    (alt
      _
      ((ref `primary_expr_c`))
      _
      _)
    (alt
      _
      ((ref `prefixed`))
      _
      _))
  (rule
    (name `prefix_expr_ck`)
    (alt
      _
      ((ref `primary_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `prefixed_k`))
      _
      _))
  (rule
    (name `prefix_expr_p`)
    (alt
      _
      ((ref `ptr_curly_suffix_expr`))
      _
      _))
  (rule
    (name `prefix_expr_pk`)
    (alt
      _
      ((ref `ptr_curly_suffix_expr`))
      _
      _))
  (rule
    (name `prefixed`)
    (alt
      _
      ((lit `"!"`)
        (ref `prefix_expr`))
      (node
        `bool_not`
        (pos `2`))
      _)
    (alt
      _
      ((skip
          (ref `minus`))
        (ref `prefix_expr`))
      (node
        `negation`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `prefix_expr`))
      (node
        `bit_not`
        (pos `2`))
      _)
    (alt
      _
      ((skip
          (ref `minus_wrap`))
        (ref `prefix_expr`))
      (node
        `negation_wrap`
        (pos `2`))
      _)
    (alt
      _
      ((skip
          (ref `amp`))
        (ref `prefix_expr`))
      (node
        `address_of`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"try"`)
        (ref `prefix_expr`))
      (node
        `try`
        (pos `2`))
      _))
  (rule
    (name `prefixed_k`)
    (alt
      _
      ((lit `"!"`)
        (ref `prefix_expr_k`))
      (node
        `bool_not`
        (pos `2`))
      _)
    (alt
      _
      ((skip
          (ref `minus`))
        (ref `prefix_expr_k`))
      (node
        `negation`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `prefix_expr_k`))
      (node
        `bit_not`
        (pos `2`))
      _)
    (alt
      _
      ((skip
          (ref `minus_wrap`))
        (ref `prefix_expr_k`))
      (node
        `negation_wrap`
        (pos `2`))
      _)
    (alt
      _
      ((skip
          (ref `amp`))
        (ref `prefix_expr_k`))
      (node
        `address_of`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"try"`)
        (ref `prefix_expr_k`))
      (node
        `try`
        (pos `2`))
      _))
  (rule
    (name `primary_expr`)
    (alt
      _
      ((ref `primary_expr_k`))
      _
      _)
    (alt
      _
      ((ref `open_expr`))
      _
      _))
  (rule
    (name `primary_expr_k`)
    (alt
      _
      ((ref `curly_suffix_expr`))
      _
      _)
    (alt
      _
      ((ref `asm_expr`))
      _
      _)
    (alt
      _
      ((ref `block`))
      _
      _)
    (alt
      _
      ((ref `jump`))
      _
      _))
  (rule
    (name `primary_expr_s`)
    (alt
      _
      ((ref `primary_expr_sk`))
      _
      _)
    (alt
      _
      ((ref `jump_open`))
      _
      _))
  (rule
    (name `primary_expr_sk`)
    (alt
      _
      ((ref `curly_suffix_expr_s`))
      _
      _)
    (alt
      _
      ((ref `asm_expr`))
      _
      _)
    (alt
      _
      ((ref `jump`))
      _
      _))
  (rule
    (name `primary_expr_c`)
    (alt
      _
      ((ref `primary_expr_ck`))
      _
      _)
    (alt
      _
      ((ref `open_expr`))
      _
      _))
  (rule
    (name `primary_expr_ck`)
    (alt
      _
      ((ref `curly_suffix_expr_c`))
      _
      _)
    (alt
      _
      ((ref `asm_expr`))
      _
      _)
    (alt
      _
      ((ref `jump`))
      _
      _))
  (rule
    (name `jump`)
    (alt
      _
      ((lit `"return"`))
      (node `return`)
      _)
    (alt
      _
      ((lit `"break"`)
        (group
          opt
          ((ref `break_label`))))
      (node
        `break`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"continue"`)
        (group
          opt
          ((ref `break_label`))))
      (node
        `continue`
        (pos `2`))
      _))
  (rule
    (name `jump_open`)
    (alt
      _
      ((lit `"return"`)
        (ref `expr`))
      (node
        `return`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"break"`)
        (group
          opt
          ((ref `break_label`)))
        (ref `expr`))
      (node
        `break`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"continue"`)
        (group
          opt
          ((ref `break_label`)))
        (ref `expr`))
      (node
        `continue`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"resume"`)
        (ref `expr`))
      (node
        `resume`
        (pos `2`))
      _))
  (rule
    (name `open_expr`)
    (alt
      _
      ((ref `jump_open`))
      _
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `expr`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"nosuspend"`)
        (ref `expr`))
      (node
        `nosuspend`
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_expr`))
      _
      _)
    (alt
      _
      ((ref `for_expr`))
      _
      _)
    (alt
      _
      ((ref `while_expr`))
      _
      _))
  (rule
    (name `if_expr`)
    (alt
      `>`
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`)
        (pos `8`)
        (pos `9`))
      _))
  (rule
    (name `for_expr`)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (null)
        (pos `5`)
        (pos `8`)
        (pos `9`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `expr`)
        (lit `"else"`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (null)
        (pos `5`)
        (pos `8`)
        (pos `9`)
        (pos `11`))
      _)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `expr`)
        (lit `"else"`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`)
        (pos `12`))
      _))
  (rule
    (name `while_expr`)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (null)
        (pos `5`)
        (pos `7`)
        (pos `8`)
        (pos `9`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (null)
        (pos `5`)
        (pos `7`)
        (pos `8`)
        (pos `9`)
        (pos `11`)
        (pos `12`))
      _)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `12`)
        (pos `13`))
      _))
  (rule
    (name `curly_suffix_expr`)
    (alt
      _
      ((ref `type_e`))
      _
      _)
    (alt
      _
      ((ref `type_e`)
        (lit `"{"`)
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`))
      _)
    (alt
      _
      ((ref `type_e`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `field_init`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `type_e`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `curly_suffix_expr_s`)
    (alt
      _
      ((ref `type_s`))
      _
      _)
    (alt
      _
      ((ref `type_s`)
        (lit `"{"`)
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`))
      _)
    (alt
      _
      ((ref `type_s`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `field_init`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `type_s`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `curly_suffix_expr_c`)
    (alt
      _
      ((ref `type_c`))
      _
      _)
    (alt
      _
      ((ref `type_c`)
        (lit `"{"`)
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`))
      _)
    (alt
      _
      ((ref `type_c`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `field_init`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `type_c`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `ptr_curly_suffix_expr`)
    (alt
      _
      ((ref `ptr_led`))
      _
      _)
    (alt
      _
      ((ref `ptr_led`)
        (lit `"{"`)
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`))
      _)
    (alt
      _
      ((ref `ptr_led`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `field_init`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `struct_init`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `ptr_led`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `type_expr`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr`))
      _
      _)
    (alt
      _
      ((ref `if_type_expr`))
      _
      _)
    (alt
      _
      ((ref `for_type_expr`))
      _
      _)
    (alt
      _
      ((ref `labeled_for_type_expr`))
      _
      _)
    (alt
      _
      ((ref `while_type_expr`))
      _
      _)
    (alt
      _
      ((ref `labeled_while_type_expr`))
      _
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `type_expr`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((ref `fn_proto`))
      _
      _))
  (rule
    (name `type_expr_f`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr_n`))
      _
      _)
    (alt
      _
      ((ref `if_type_expr`))
      _
      _)
    (alt
      _
      ((ref `for_type_expr`))
      _
      _)
    (alt
      _
      ((ref `while_type_expr`))
      _
      _))
  (rule
    (name `type_expr_p`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr_n`))
      _
      _)
    (alt
      _
      ((ref `if_type_expr`))
      _
      _)
    (alt
      _
      ((ref `for_type_expr`))
      _
      _)
    (alt
      _
      ((ref `while_type_expr`))
      _
      _)
    (alt
      _
      ((ref `fn_proto`))
      _
      _))
  (rule
    (name `type_expr_n`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr_n`))
      _
      _)
    (alt
      _
      ((ref `if_type_expr`))
      _
      _)
    (alt
      _
      ((ref `for_type_expr`))
      _
      _)
    (alt
      _
      ((ref `while_type_expr`))
      _
      _)
    (alt
      _
      ((lit `"comptime"`)
        (ref `type_expr`))
      (node
        `comptime`
        (pos `2`))
      _)
    (alt
      _
      ((ref `fn_proto`))
      _
      _))
  (rule
    (name `type_e`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr`))
      _
      _)
    (alt
      _
      ((ref `fn_proto`))
      _
      _))
  (rule
    (name `type_s`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr_s`))
      _
      _)
    (alt
      _
      ((ref `fn_proto`))
      _
      _))
  (rule
    (name `type_c`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union_expr_c`))
      _
      _)
    (alt
      _
      ((ref `fn_proto`))
      _
      _))
  (rule
    (name `prefix_type`)
    (alt
      _
      ((lit `"?"`)
        (ref `type_expr`))
      (node
        `optional_type`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"anyframe"`)
        (lit `"->"`)
        (ref `type_expr`))
      (node
        `anyframe_type`
        (pos `3`))
      _)
    (alt
      _
      ((ref `single_ptr`))
      _
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `5`)
        (spread `4`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (null)
        (pos `5`)
        (null)
        (null)
        (null)
        (pos `7`)
        (spread `4`)
        (spread `6`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (null)
        (pos `5`)
        (null)
        (null)
        (pos `7`)
        (pos `9`)
        (spread `4`)
        (spread `6`)
        (spread `8`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (null)
        (null)
        (null)
        (null)
        (pos `5`)
        (pos `7`)
        (spread `4`)
        (spread `6`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (null)
        (pos `7`)
        (null)
        (null)
        (pos `5`)
        (pos `9`)
        (spread `4`)
        (spread `6`)
        (spread `8`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `c`)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `6`)
        (spread `5`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `c`)
        (null)
        (pos `6`)
        (null)
        (null)
        (null)
        (pos `8`)
        (spread `5`)
        (spread `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `c`)
        (null)
        (pos `6`)
        (null)
        (null)
        (pos `8`)
        (pos `10`)
        (spread `5`)
        (spread `7`)
        (spread `9`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `c`)
        (null)
        (null)
        (null)
        (null)
        (pos `6`)
        (pos `8`)
        (spread `5`)
        (spread `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `c`)
        (null)
        (pos `8`)
        (null)
        (null)
        (pos `6`)
        (pos `10`)
        (spread `5`)
        (spread `7`)
        (spread `9`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (pos `4`)
        (null)
        (null)
        (null)
        (null)
        (pos `7`)
        (spread `6`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (pos `4`)
        (pos `7`)
        (null)
        (null)
        (null)
        (pos `9`)
        (spread `6`)
        (spread `8`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (pos `4`)
        (pos `7`)
        (null)
        (null)
        (pos `9`)
        (pos `11`)
        (spread `6`)
        (spread `8`)
        (spread `10`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (pos `4`)
        (null)
        (null)
        (null)
        (pos `7`)
        (pos `9`)
        (spread `6`)
        (spread `8`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (pos `4`)
        (pos `9`)
        (null)
        (null)
        (pos `7`)
        (pos `11`)
        (spread `6`)
        (spread `8`)
        (spread `10`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `4`)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (null)
        (pos `4`)
        (null)
        (null)
        (null)
        (pos `6`)
        (spread `3`)
        (spread `5`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (null)
        (pos `4`)
        (null)
        (null)
        (pos `6`)
        (pos `8`)
        (spread `3`)
        (spread `5`)
        (spread `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (null)
        (null)
        (null)
        (null)
        (pos `4`)
        (pos `6`)
        (spread `3`)
        (spread `5`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (null)
        (pos `6`)
        (null)
        (null)
        (pos `4`)
        (pos `8`)
        (spread `3`)
        (spread `5`)
        (spread `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (pos `3`)
        (null)
        (null)
        (null)
        (null)
        (pos `6`)
        (spread `5`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (pos `3`)
        (pos `6`)
        (null)
        (null)
        (null)
        (pos `8`)
        (spread `5`)
        (spread `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (pos `3`)
        (pos `6`)
        (null)
        (null)
        (pos `8`)
        (pos `10`)
        (spread `5`)
        (spread `7`)
        (spread `9`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (pos `3`)
        (null)
        (null)
        (null)
        (pos `6`)
        (pos `8`)
        (spread `5`)
        (spread `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (pos `3`)
        (pos `8`)
        (null)
        (null)
        (pos `6`)
        (pos `10`)
        (spread `5`)
        (spread `7`)
        (spread `9`))
      _)
    (alt
      _
      ((lit `"["`)
        (ref `expr`)
        (lit `"]"`)
        (ref `type_expr`))
      (node
        `array_type`
        (pos `2`)
        (null)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"["`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `type_expr`))
      (node
        `array_type`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _))
  (rule
    (name `single_ptr`)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `3`)
        (spread `2`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `3`)
        (null)
        (null)
        (null)
        (pos `5`)
        (spread `2`)
        (spread `4`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `3`)
        (null)
        (null)
        (pos `5`)
        (pos `7`)
        (spread `2`)
        (spread `4`)
        (spread `6`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (null)
        (null)
        (null)
        (pos `3`)
        (pos `5`)
        (spread `2`)
        (spread `4`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `5`)
        (null)
        (null)
        (pos `3`)
        (pos `7`)
        (spread `2`)
        (spread `4`)
        (spread `6`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `5`)
        (pos `7`)
        (pos `9`)
        (null)
        (pos `12`)
        (spread `2`)
        (spread `11`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `5`)
        (pos `7`)
        (pos `9`)
        (pos `12`)
        (pos `14`)
        (spread `2`)
        (spread `11`)
        (spread `13`))
      _)
    (alt
      _
      ((skip
          (ref `star`))
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `7`)
        (pos `9`)
        (pos `11`)
        (pos `3`)
        (pos `14`)
        (spread `2`)
        (spread `4`)
        (spread `13`))
      _))
  (rule
    (name `ptr_led`)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `3`)
        (spread `2`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `3`)
        (null)
        (null)
        (null)
        (pos `5`)
        (spread `2`)
        (spread `4`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `3`)
        (null)
        (null)
        (pos `5`)
        (pos `7`)
        (spread `2`)
        (spread `4`)
        (spread `6`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (null)
        (null)
        (null)
        (pos `3`)
        (pos `5`)
        (spread `2`)
        (spread `4`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `5`)
        (null)
        (null)
        (pos `3`)
        (pos `7`)
        (spread `2`)
        (spread `4`)
        (spread `6`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `5`)
        (pos `7`)
        (pos `9`)
        (null)
        (pos `12`)
        (spread `2`)
        (spread `11`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `5`)
        (pos `7`)
        (pos `9`)
        (pos `12`)
        (pos `14`)
        (spread `2`)
        (spread `11`)
        (spread `13`))
      _)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_quals`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `7`)
        (pos `9`)
        (pos `11`)
        (pos `3`)
        (pos `14`)
        (spread `2`)
        (spread `4`)
        (spread `13`))
      _))
  (rule
    (name `ptr_quals`)
    (alt
      _
      ((quantified
          (ref `ptr_qual`)
          (zero_plus)))
      _
      _))
  (rule
    (name `ptr_qual`)
    (alt
      _
      ((lit `"const"`))
      _
      _)
    (alt
      _
      ((lit `"volatile"`))
      _
      _)
    (alt
      _
      ((lit `"allowzero"`))
      _
      _))
  (rule
    (name `error_union_expr`)
    (alt
      _
      ((ref `suffix_expr`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `error_union_expr_s`)
    (alt
      _
      ((ref `suffix_expr_s`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `error_union_expr_c`)
    (alt
      _
      ((ref `suffix_expr_c`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `error_union_expr_n`)
    (alt
      _
      ((ref `suffix_expr_n`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `suffix_expr`)
    (alt
      _
      ((ref `primary_type_expr`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"["`)
        (ref `c_ptr_index`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `".."`)
        (group
          opt
          ((ref `expr`)))
        (group
          opt
          ((lit `":"`)
            (ref `expr`)))
        (lit `"]"`))
      (node
        `slice`
        (pos `1`)
        (pos `3`)
        (pos `5`)
        (pos `7`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `suffix_expr_s`)
    (alt
      _
      ((ref `primary_type_expr_s`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"["`)
        (ref `c_ptr_index`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `".."`)
        (group
          opt
          ((ref `expr`)))
        (group
          opt
          ((lit `":"`)
            (ref `expr`)))
        (lit `"]"`))
      (node
        `slice`
        (pos `1`)
        (pos `3`)
        (pos `5`)
        (pos `7`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr_s`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `suffix_expr_c`)
    (alt
      _
      ((ref `primary_type_expr_c`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"["`)
        (ref `c_ptr_index`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `".."`)
        (group
          opt
          ((ref `expr`)))
        (group
          opt
          ((lit `":"`)
            (ref `expr`)))
        (lit `"]"`))
      (node
        `slice`
        (pos `1`)
        (pos `3`)
        (pos `5`)
        (pos `7`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr_c`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `suffix_expr_n`)
    (alt
      _
      ((ref `primary_type_expr_n`))
      _
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"["`)
        (ref `c_ptr_index`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"["`)
        (ref `index_expr`)
        (lit `".."`)
        (group
          opt
          ((ref `expr`)))
        (group
          opt
          ((lit `":"`)
            (ref `expr`)))
        (lit `"]"`))
      (node
        `slice`
        (pos `1`)
        (pos `3`)
        (pos `5`)
        (pos `7`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_expr_n`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `c_ptr_index`)
    (alt
      _
      ((tok `PTR_STAR`)
        (tok `C_PTR`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (null)
        (null)
        (null)
        (null)
        (pos `2`))
      _))
  (rule
    (name `primary_type_expr`)
    (alt
      _
      ((ref `atom`))
      _
      _)
    (alt
      _
      ((ref `switch_expr`))
      _
      _)
    (alt
      _
      ((ref `labeled_switch`))
      _
      _)
    (alt
      _
      ((ref `labeled_block`))
      _
      _))
  (rule
    (name `primary_type_expr_s`)
    (alt
      _
      ((ref `atom`))
      _
      _))
  (rule
    (name `primary_type_expr_c`)
    (alt
      _
      ((ref `atom`))
      _
      _)
    (alt
      _
      ((ref `switch_expr`))
      _
      _)
    (alt
      _
      ((ref `labeled_switch`))
      _
      _))
  (rule
    (name `primary_type_expr_n`)
    (alt
      _
      ((ref `atom`))
      _
      _)
    (alt
      _
      ((ref `switch_expr`))
      _
      _))
  (rule
    (name `atom`)
    (alt
      _
      ((tok `IDENTIFIER`))
      _
      _)
    (alt
      _
      ((tok `NUMBER_LITERAL`))
      _
      _)
    (alt
      _
      ((tok `CHAR_LITERAL`))
      _
      _)
    (alt
      _
      ((tok `STRING_LITERAL`))
      _
      _)
    (alt
      _
      ((quantified
          (tok `MULTILINE_STRING_LITERAL_LINE`)
          (one_plus)))
      (node
        `multiline_string_literal`
        (spread `1`))
      _)
    (alt
      _
      ((tok `BUILTIN`)
        (lit `"("`)
        (lit `")"`))
      (node
        `builtin_call`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BUILTIN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (node
        `builtin_call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `grouped_expression`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `enum_literal`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"."`)
        (lit `"{"`)
        (lit `"}"`))
      (node
        `struct_init`
        (null))
      _)
    (alt
      _
      ((lit `"."`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `field_init`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `struct_init`
        (null)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"."`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `expr`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `array_init`
        (null)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"error"`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `error_value`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"error"`)
        (lit `"{"`)
        (lit `"}"`))
      (node `error_set_decl`)
      _)
    (alt
      _
      ((lit `"error"`)
        (lit `"{"`)
        (list_req
          `L`
          (plain `error_name`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `"}"`))
      (node
        `error_set_decl`
        (spread `3`))
      _)
    (alt
      _
      ((lit `"unreachable"`))
      (pos `1`)
      _)
    (alt
      _
      ((lit `"anyframe"`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `container_type`))
      _
      _))
  (rule
    (name `error_name`)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (tok `IDENTIFIER`))
      (node
        `error_name`
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `container_type`)
    (alt
      _
      ((group
          opt
          ((ref `container_layout`)))
        (ref `container_kind`)
        (lit `"{"`)
        (ref `container_docs`)
        (ref `members`)
        (lit `"}"`))
      (node
        `container_decl`
        (pos `1`)
        (pos `2`)
        (null)
        (null)
        (pos `4`)
        (spread `5`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `container_layout`)))
        (ref `container_arg_kind`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (lit `"{"`)
        (ref `container_docs`)
        (ref `members`)
        (lit `"}"`))
      (node
        `container_decl`
        (pos `1`)
        (pos `2`)
        (null)
        (pos `4`)
        (pos `7`)
        (spread `8`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `container_layout`)))
        (lit `"union"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (lit `"{"`)
        (ref `container_docs`)
        (ref `members`)
        (lit `"}"`))
      (node
        `container_decl`
        (pos `1`)
        (pos `2`)
        (null)
        (pos `4`)
        (pos `7`)
        (spread `8`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `container_layout`)))
        (lit `"union"`)
        (lit `"("`)
        (tok `ENUM_TAG`)
        (lit `")"`)
        (lit `"{"`)
        (ref `container_docs`)
        (ref `members`)
        (lit `"}"`))
      (node
        `container_decl`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (null)
        (pos `7`)
        (spread `8`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `container_layout`)))
        (lit `"union"`)
        (lit `"("`)
        (tok `ENUM_TAG`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (lit `")"`)
        (lit `"{"`)
        (ref `container_docs`)
        (ref `members`)
        (lit `"}"`))
      (node
        `container_decl`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (pos `10`)
        (spread `11`))
      _))
  (rule
    (name `container_layout`)
    (alt
      _
      ((lit `"extern"`))
      _
      _)
    (alt
      _
      ((lit `"packed"`))
      _
      _))
  (rule
    (name `container_kind`)
    (alt
      _
      ((lit `"struct"`))
      _
      _)
    (alt
      _
      ((lit `"opaque"`))
      _
      _)
    (alt
      _
      ((lit `"enum"`))
      _
      _)
    (alt
      _
      ((lit `"union"`))
      _
      _))
  (rule
    (name `container_arg_kind`)
    (alt
      _
      ((lit `"struct"`))
      _
      _)
    (alt
      _
      ((lit `"enum"`))
      _
      _))
  (rule
    (name `if_type_expr`)
    (alt
      `>`
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `type_expr`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `type_expr`))
      (node
        `if`
        (pos `3`)
        (pos `5`)
        (pos `6`)
        (pos `8`)
        (pos `9`))
      _))
  (rule
    (name `for_type_expr`)
    (alt
      `>`
      ((group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `type_expr`))
      (node
        `for`
        (null)
        (pos `1`)
        (pos `4`)
        (pos `7`)
        (pos `8`))
      _)
    (alt
      _
      ((group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `type_expr`))
      (node
        `for`
        (null)
        (pos `1`)
        (pos `4`)
        (pos `7`)
        (pos `8`)
        (pos `10`))
      _))
  (rule
    (name `labeled_for_type_expr`)
    (alt
      `>`
      ((tok `LABEL`)
        (lit `":"`)
        (group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `type_expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((tok `LABEL`)
        (lit `":"`)
        (group
          opt
          ((lit `"inline"`)))
        (lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`)
        (ref `ptr_list_payload`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `type_expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `9`)
        (pos `10`)
        (pos `12`))
      _))
  (rule
    (name `while_type_expr`)
    (alt
      `>`
      ((group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `type_expr`))
      (node
        `while`
        (null)
        (pos `1`)
        (pos `4`)
        (pos `6`)
        (pos `7`)
        (pos `8`))
      _)
    (alt
      _
      ((group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `type_expr`))
      (node
        `while`
        (null)
        (pos `1`)
        (pos `4`)
        (pos `6`)
        (pos `7`)
        (pos `8`)
        (pos `10`)
        (pos `11`))
      _))
  (rule
    (name `labeled_while_type_expr`)
    (alt
      `>`
      ((tok `LABEL`)
        (lit `":"`)
        (group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `type_expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`))
      _)
    (alt
      _
      ((tok `LABEL`)
        (lit `":"`)
        (group
          opt
          ((lit `"inline"`)))
        (lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (ref `ptr_payload`)
        (ref `while_continue_expr`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `else_payload`)
        (ref `type_expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `6`)
        (pos `8`)
        (pos `9`)
        (pos `10`)
        (pos `12`)
        (pos `13`))
      _))
  (rule
    (name `switch_expr`)
    (alt
      _
      ((lit `"switch"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (lit `"{"`)
        (group
          opt
          ((ref `switch_prong_list`)))
        (lit `"}"`))
      (node
        `switch`
        (null)
        (pos `3`)
        (spread `6`))
      _))
  (rule
    (name `labeled_switch`)
    (alt
      _
      ((tok `LABEL`)
        (lit `":"`)
        (lit `"switch"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (lit `"{"`)
        (group
          opt
          ((ref `switch_prong_list`)))
        (lit `"}"`))
      (node
        `switch`
        (pos `1`)
        (pos `5`)
        (spread `8`))
      _))
  (rule
    (name `asm_expr`)
    (alt
      _
      ((lit `"asm"`)
        (group
          opt
          ((lit `"volatile"`)))
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"asm"`)
        (group
          opt
          ((lit `"volatile"`)))
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `asm_output_list`)
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`)
        (null)
        (spread `6`))
      _)
    (alt
      _
      ((lit `"asm"`)
        (group
          opt
          ((lit `"volatile"`)))
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `asm_output_list`)
        (lit `":"`)
        (ref `asm_input_list`)
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`)
        (null)
        (spread `6`)
        (spread `8`))
      _)
    (alt
      _
      ((lit `"asm"`)
        (group
          opt
          ((lit `"volatile"`)))
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `asm_output_list`)
        (lit `":"`)
        (ref `asm_input_list`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`)
        (pos `10`)
        (spread `6`)
        (spread `8`))
      _))
  (rule
    (name `asm_output_list`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((list_req
          `L`
          (plain `asm_output_item`))
        (skip_q
          (lit `","`)
          (opt)))
      (pos `1`)
      _))
  (rule
    (name `asm_input_list`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((list_req
          `L`
          (plain `asm_input_item`))
        (skip_q
          (lit `","`)
          (opt)))
      (pos `1`)
      _))
  (rule
    (name `asm_output_item`)
    (alt
      _
      ((lit `"["`)
        (tok `IDENTIFIER`)
        (lit `"]"`)
        (tok `STRING_LITERAL`)
        (lit `"("`)
        (lit `"->"`)
        (ref `type_expr`)
        (lit `")"`))
      (node
        `asm_output`
        (pos `2`)
        (pos `4`)
        (null)
        (pos `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `IDENTIFIER`)
        (lit `"]"`)
        (tok `STRING_LITERAL`)
        (lit `"("`)
        (tok `IDENTIFIER`)
        (lit `")"`))
      (node
        `asm_output`
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (null))
      _))
  (rule
    (name `asm_input_item`)
    (alt
      _
      ((lit `"["`)
        (tok `IDENTIFIER`)
        (lit `"]"`)
        (tok `STRING_LITERAL`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `asm_input`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _))
  (rule
    (name `break_label`)
    (alt
      _
      ((tok `BREAK_COLON`)
        (tok `IDENTIFIER`))
      (pos `2`)
      _))
  (rule
    (name `field_init`)
    (alt
      _
      ((lit `"."`)
        (tok `IDENTIFIER`)
        (lit `"="`)
        (ref `expr`))
      (node
        `field_init`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `while_continue_expr`)
    (alt _ () _ _)
    (alt
      _
      ((lit `":"`)
        (lit `"("`)
        (ref `assign_expr`)
        (lit `")"`))
      (pos `3`)
      _))
  (rule
    (name `link_section`)
    (alt
      _
      ((lit `"linksection"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `3`)
      _))
  (rule
    (name `addr_space`)
    (alt
      _
      ((lit `"addrspace"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `3`)
      _))
  (rule
    (name `call_conv`)
    (alt
      _
      ((lit `"callconv"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `3`)
      _))
  (rule
    (name `param_decl_list`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      (list)
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `param_decl`))
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `param_decl`))
        (lit `","`)
        (ref `var_args`)
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (list
        (spread `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `var_args`)
        (skip_q
          (lit `","`)
          (opt))
        (lit `")"`))
      (list
        (pos `2`))
      _))
  (rule
    (name `var_args`)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (lit `"..."`))
      (node
        `param`
        (pos `1`)
        (null)
        (null)
        (pos `2`))
      _))
  (rule
    (name `param_decl`)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((ref `param_flag`)))
        (ref `param_name`)
        (lit `":"`)
        (ref `param_type`))
      (node
        `param`
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (ref `param_type_p`))
      (node
        `param`
        (pos `1`)
        (null)
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (ref `param_flag`)
        (ref `param_type_n`))
      (node
        `param`
        (pos `1`)
        (pos `2`)
        (null)
        (pos `3`))
      _))
  (rule
    (name `param_flag`)
    (alt
      _
      ((lit `"comptime"`))
      _
      _)
    (alt
      _
      ((lit `"noalias"`))
      _
      _))
  (rule
    (name `param_name`)
    (alt
      _
      ((tok `IDENTIFIER`))
      _
      _)
    (alt
      _
      ((tok `LABEL`))
      _
      _))
  (rule
    (name `param_type`)
    (alt
      _
      ((lit `"anytype"`))
      _
      _)
    (alt
      _
      ((ref `type_expr`))
      _
      _))
  (rule
    (name `param_type_p`)
    (alt
      _
      ((lit `"anytype"`))
      _
      _)
    (alt
      _
      ((ref `type_expr_p`))
      _
      _))
  (rule
    (name `param_type_n`)
    (alt
      _
      ((lit `"anytype"`))
      _
      _)
    (alt
      _
      ((ref `type_expr_n`))
      _
      _))
  (rule
    (name `payload`)
    (alt
      _
      ((skip
          (ref `pipe`))
        (tok `IDENTIFIER`)
        (skip
          (ref `pipe`)))
      (pos `2`)
      _))
  (rule
    (name `ptr_payload`)
    (alt _ () _ _)
    (alt
      _
      ((skip
          (ref `pipe`))
        (ref `capture`)
        (skip
          (ref `pipe`)))
      (pos `2`)
      _))
  (rule
    (name `else_payload`)
    (alt _ () _ _)
    (alt
      _
      ((ref `payload`))
      _
      _))
  (rule
    (name `ptr_list_payload`)
    (alt
      _
      ((skip
          (ref `pipe`))
        (list_req
          `L`
          (plain `capture`))
        (skip_q
          (lit `","`)
          (opt))
        (skip
          (ref `pipe`)))
      (pos `2`)
      _))
  (rule
    (name `capture`)
    (alt
      _
      ((group
          opt
          ((ref `star`)))
        (tok `IDENTIFIER`))
      (node
        `capture`
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `switch_prong_list`)
    (alt
      _
      ((list_req
          `L`
          (plain `switch_prong`))
        (skip_q
          (lit `","`)
          (opt)))
      (pos `1`)
      _))
  (rule
    (name `switch_prong`)
    (alt
      _
      ((ref `switch_values`)
        (lit `"=>"`)
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (null)
        (pos `1`)
        (null)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((ref `switch_values`)
        (lit `"=>"`)
        (skip
          (ref `pipe`))
        (ref `capture`)
        (skip
          (ref `pipe`))
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (null)
        (pos `1`)
        (pos `4`)
        (null)
        (pos `6`))
      _)
    (alt
      _
      ((ref `switch_values`)
        (lit `"=>"`)
        (skip
          (ref `pipe`))
        (ref `capture`)
        (lit `","`)
        (tok `IDENTIFIER`)
        (skip
          (ref `pipe`))
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (null)
        (pos `1`)
        (pos `4`)
        (pos `6`)
        (pos `8`))
      _)
    (alt
      _
      ((lit `"inline"`)
        (ref `switch_values`)
        (lit `"=>"`)
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (pos `1`)
        (pos `2`)
        (null)
        (null)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"inline"`)
        (ref `switch_values`)
        (lit `"=>"`)
        (skip
          (ref `pipe`))
        (ref `capture`)
        (skip
          (ref `pipe`))
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (pos `1`)
        (pos `2`)
        (pos `5`)
        (null)
        (pos `7`))
      _)
    (alt
      _
      ((lit `"inline"`)
        (ref `switch_values`)
        (lit `"=>"`)
        (skip
          (ref `pipe`))
        (ref `capture`)
        (lit `","`)
        (tok `IDENTIFIER`)
        (skip
          (ref `pipe`))
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (pos `1`)
        (pos `2`)
        (pos `5`)
        (pos `7`)
        (pos `9`))
      _))
  (rule
    (name `switch_values`)
    (alt
      _
      ((lit `"else"`))
      (list)
      _)
    (alt
      _
      ((list_req
          `L`
          (plain `switch_item`))
        (skip_q
          (lit `","`)
          (opt)))
      (pos `1`)
      _))
  (rule
    (name `switch_item`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `expr`)
        (lit `"..."`)
        (ref `expr`))
      (node
        `switch_range`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `for_item`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((ref `expr`)
        (lit `".."`))
      (node
        `for_range`
        (pos `1`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `".."`)
        (ref `expr`))
      (node
        `for_range`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `assign_op`)
    (alt
      _
      ((lit `"="`))
      _
      _)
    (alt
      _
      ((lit `"*="`))
      _
      _)
    (alt
      _
      ((lit `"*|="`))
      _
      _)
    (alt
      _
      ((lit `"/="`))
      _
      _)
    (alt
      _
      ((lit `"%="`))
      _
      _)
    (alt
      _
      ((lit `"+="`))
      _
      _)
    (alt
      _
      ((lit `"+|="`))
      _
      _)
    (alt
      _
      ((lit `"-="`))
      _
      _)
    (alt
      _
      ((lit `"-|="`))
      _
      _)
    (alt
      _
      ((lit `"<<="`))
      _
      _)
    (alt
      _
      ((lit `"<<|="`))
      _
      _)
    (alt
      _
      ((lit `">>="`))
      _
      _)
    (alt
      _
      ((lit `"&="`))
      _
      _)
    (alt
      _
      ((lit `"^="`))
      _
      _)
    (alt
      _
      ((lit `"|="`))
      _
      _)
    (alt
      _
      ((lit `"*%="`))
      _
      _)
    (alt
      _
      ((lit `"+%="`))
      _
      _)
    (alt
      _
      ((lit `"-%="`))
      _
      _))
  (rule
    (name `compare_op`)
    (alt
      _
      ((lit `"=="`))
      _
      _)
    (alt
      _
      ((lit `"!="`))
      _
      _)
    (alt
      _
      ((lit `"<"`))
      _
      _)
    (alt
      _
      ((lit `">"`))
      _
      _)
    (alt
      _
      ((lit `"<="`))
      _
      _)
    (alt
      _
      ((lit `">="`))
      _
      _))
  (rule
    (name `bitwise_op`)
    (alt
      _
      ((lit `"&"`))
      _
      _)
    (alt
      _
      ((lit `"^"`))
      _
      _)
    (alt
      _
      ((lit `"|"`))
      _
      _)
    (alt
      _
      ((lit `"orelse"`))
      _
      _))
  (rule
    (name `bit_shift_op`)
    (alt
      _
      ((lit `"<<"`))
      _
      _)
    (alt
      _
      ((lit `">>"`))
      _
      _)
    (alt
      _
      ((lit `"<<|"`))
      _
      _))
  (rule
    (name `addition_op`)
    (alt
      _
      ((lit `"+"`))
      _
      _)
    (alt
      _
      ((lit `"-"`))
      _
      _)
    (alt
      _
      ((lit `"++"`))
      _
      _)
    (alt
      _
      ((lit `"+%"`))
      _
      _)
    (alt
      _
      ((lit `"-%"`))
      _
      _)
    (alt
      _
      ((lit `"+|"`))
      _
      _)
    (alt
      _
      ((lit `"-|"`))
      _
      _))
  (rule
    (name `multiply_op`)
    (alt
      _
      ((lit `"||"`))
      _
      _)
    (alt
      _
      ((lit `"*"`))
      _
      _)
    (alt
      _
      ((lit `"/"`))
      _
      _)
    (alt
      _
      ((lit `"%"`))
      _
      _)
    (alt
      _
      ((lit `"*%"`))
      _
      _)
    (alt
      _
      ((lit `"*|"`))
      _
      _))
  (rule
    (name `minus`)
    (alt
      _
      ((lit `"-"`))
      _
      _)
    (alt
      _
      ((tok `MINUS_PREFIX`))
      _
      _))
  (rule
    (name `minus_wrap`)
    (alt
      _
      ((lit `"-%"`))
      _
      _)
    (alt
      _
      ((tok `MINUS_PERCENT_PREFIX`))
      _
      _))
  (rule
    (name `amp`)
    (alt
      _
      ((lit `"&"`))
      _
      _)
    (alt
      _
      ((tok `AMPERSAND_PREFIX`))
      _
      _))
  (rule
    (name `star`)
    (alt
      _
      ((lit `"*"`))
      _
      _)
    (alt
      _
      ((tok `ASTERISK_PREFIX`))
      _
      _))
  (rule
    (name `pipe`)
    (alt
      _
      ((lit `"|"`))
      _
      _)
    (alt
      _
      ((tok `PIPE_PAYLOAD`))
      _
      _))
  (rule
    (name `byte_align`)
    (alt
      _
      ((lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `3`)
      _))
  (rule
    (name `token`)
    (alt
      _
      ((tok `INVALID`))
      (node
        `invalid`
        (pos `1`))
      _)
    (alt
      _
      ((tok `IDENTIFIER`))
      (node
        `identifier`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STRING_LITERAL`))
      (node
        `string_literal`
        (pos `1`))
      _)
    (alt
      _
      ((tok `MULTILINE_STRING_LITERAL_LINE`))
      (node
        `multiline_string_literal_line`
        (pos `1`))
      _)
    (alt
      _
      ((tok `CHAR_LITERAL`))
      (node
        `char_literal`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BUILTIN`))
      (node
        `builtin`
        (pos `1`))
      _)
    (alt
      _
      ((tok `NUMBER_LITERAL`))
      (node
        `number_literal`
        (pos `1`))
      _)
    (alt
      _
      ((tok `DOC_COMMENT`))
      (node
        `doc_comment`
        (pos `1`))
      _)
    (alt
      _
      ((tok `CONTAINER_DOC_COMMENT`))
      (node
        `container_doc_comment`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"!"`))
      (node
        `bang`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"|"`))
      (node
        `pipe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"||"`))
      (node
        `pipe_pipe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"|="`))
      (node
        `pipe_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"="`))
      (node
        `equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"=="`))
      (node
        `equal_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"=>"`))
      (node
        `equal_angle_bracket_right`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"!="`))
      (node
        `bang_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"("`))
      (node
        `l_paren`
        (pos `1`))
      _)
    (alt
      _
      ((lit `")"`))
      (node
        `r_paren`
        (pos `1`))
      _)
    (alt
      _
      ((lit `";"`))
      (node
        `semicolon`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"%"`))
      (node
        `percent`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"%="`))
      (node
        `percent_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"{"`))
      (node
        `l_brace`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"}"`))
      (node
        `r_brace`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"["`))
      (node
        `l_bracket`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"]"`))
      (node
        `r_bracket`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"."`))
      (node
        `period`
        (pos `1`))
      _)
    (alt
      _
      ((lit `".*"`))
      (node
        `period_asterisk`
        (pos `1`))
      _)
    (alt
      _
      ((lit `".."`))
      (node
        `ellipsis2`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"..."`))
      (node
        `ellipsis3`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"^"`))
      (node
        `caret`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"^="`))
      (node
        `caret_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"+"`))
      (node
        `plus`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"++"`))
      (node
        `plus_plus`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"+="`))
      (node
        `plus_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"+%"`))
      (node
        `plus_percent`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"+%="`))
      (node
        `plus_percent_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"+|"`))
      (node
        `plus_pipe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"+|="`))
      (node
        `plus_pipe_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-"`))
      (node
        `minus`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-="`))
      (node
        `minus_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-%"`))
      (node
        `minus_percent`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-%="`))
      (node
        `minus_percent_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-|"`))
      (node
        `minus_pipe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-|="`))
      (node
        `minus_pipe_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*"`))
      (node
        `asterisk`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*="`))
      (node
        `asterisk_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*%"`))
      (node
        `asterisk_percent`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*%="`))
      (node
        `asterisk_percent_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*|"`))
      (node
        `asterisk_pipe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*|="`))
      (node
        `asterisk_pipe_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"->"`))
      (node
        `arrow`
        (pos `1`))
      _)
    (alt
      _
      ((lit `":"`))
      (node
        `colon`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"/"`))
      (node
        `slash`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"/="`))
      (node
        `slash_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `","`))
      (node
        `comma`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"&"`))
      (node
        `ampersand`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"&="`))
      (node
        `ampersand_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"?"`))
      (node
        `question_mark`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"<"`))
      (node
        `angle_bracket_left`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"<="`))
      (node
        `angle_bracket_left_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"<<"`))
      (node
        `angle_bracket_angle_bracket_left`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"<<="`))
      (node
        `angle_bracket_angle_bracket_left_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"<<|"`))
      (node
        `angle_bracket_angle_bracket_left_pipe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"<<|="`))
      (node
        `angle_bracket_angle_bracket_left_pipe_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `">"`))
      (node
        `angle_bracket_right`
        (pos `1`))
      _)
    (alt
      _
      ((lit `">="`))
      (node
        `angle_bracket_right_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `">>"`))
      (node
        `angle_bracket_angle_bracket_right`
        (pos `1`))
      _)
    (alt
      _
      ((lit `">>="`))
      (node
        `angle_bracket_angle_bracket_right_equal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"~"`))
      (node
        `tilde`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"addrspace"`))
      (node
        `keyword_addrspace`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"align"`))
      (node
        `keyword_align`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"allowzero"`))
      (node
        `keyword_allowzero`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"and"`))
      (node
        `keyword_and`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"anyframe"`))
      (node
        `keyword_anyframe`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"anytype"`))
      (node
        `keyword_anytype`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"asm"`))
      (node
        `keyword_asm`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"break"`))
      (node
        `keyword_break`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"callconv"`))
      (node
        `keyword_callconv`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"catch"`))
      (node
        `keyword_catch`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"comptime"`))
      (node
        `keyword_comptime`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"const"`))
      (node
        `keyword_const`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"continue"`))
      (node
        `keyword_continue`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"defer"`))
      (node
        `keyword_defer`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"else"`))
      (node
        `keyword_else`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"enum"`))
      (node
        `keyword_enum`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"errdefer"`))
      (node
        `keyword_errdefer`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"error"`))
      (node
        `keyword_error`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"export"`))
      (node
        `keyword_export`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"extern"`))
      (node
        `keyword_extern`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"fn"`))
      (node
        `keyword_fn`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"for"`))
      (node
        `keyword_for`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"if"`))
      (node
        `keyword_if`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"inline"`))
      (node
        `keyword_inline`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"noalias"`))
      (node
        `keyword_noalias`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"noinline"`))
      (node
        `keyword_noinline`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"nosuspend"`))
      (node
        `keyword_nosuspend`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"opaque"`))
      (node
        `keyword_opaque`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"or"`))
      (node
        `keyword_or`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"orelse"`))
      (node
        `keyword_orelse`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"packed"`))
      (node
        `keyword_packed`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"pub"`))
      (node
        `keyword_pub`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"resume"`))
      (node
        `keyword_resume`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"return"`))
      (node
        `keyword_return`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"linksection"`))
      (node
        `keyword_linksection`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"struct"`))
      (node
        `keyword_struct`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"suspend"`))
      (node
        `keyword_suspend`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"switch"`))
      (node
        `keyword_switch`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"test"`))
      (node
        `keyword_test`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"threadlocal"`))
      (node
        `keyword_threadlocal`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"try"`))
      (node
        `keyword_try`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"union"`))
      (node
        `keyword_union`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"unreachable"`))
      (node
        `keyword_unreachable`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"var"`))
      (node
        `keyword_var`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"volatile"`))
      (node
        `keyword_volatile`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"while"`))
      (node
        `keyword_while`
        (pos `1`))
      _)
    (alt
      _
      ((tok `ERR`))
      (node
        `err`
        (pos `1`))
      _)
    (alt
      _
      ((tok `LABEL`))
      (node
        `label`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BREAK_COLON`))
      (node
        `break_colon`
        (pos `1`))
      _)
    (alt
      _
      ((tok `PTR_STAR`))
      (node
        `ptr_star`
        (pos `1`))
      _)
    (alt
      _
      ((tok `C_PTR`))
      (node
        `c_ptr`
        (pos `1`))
      _)
    (alt
      _
      ((tok `ENUM_TAG`))
      (node
        `enum_tag`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BAD_DOC_COMMENT`))
      (node
        `bad_doc_comment`
        (pos `1`))
      _)
    (alt
      _
      ((tok `MINUS_PREFIX`))
      (node
        `minus_prefix`
        (pos `1`))
      _)
    (alt
      _
      ((tok `MINUS_PERCENT_PREFIX`))
      (node
        `minus_percent_prefix`
        (pos `1`))
      _)
    (alt
      _
      ((tok `AMPERSAND_PREFIX`))
      (node
        `ampersand_prefix`
        (pos `1`))
      _)
    (alt
      _
      ((tok `ASTERISK_PREFIX`))
      (node
        `asterisk_prefix`
        (pos `1`))
      _)
    (alt
      _
      ((tok `PIPE_PAYLOAD`))
      (node
        `pipe_payload`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BAD_OPERATOR`))
      (node
        `bad_operator`
        (pos `1`))
      _)))
