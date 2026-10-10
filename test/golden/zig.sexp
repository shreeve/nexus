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
  (manifest
    (conflict `shift` `jump → "return"` _ `4` `# the operand of \`return\` is parseExpr: a prefix operator starts it`)
    (conflict `shift` `jump → "break"` _ `4` `# the operand of \`break\` is parseExpr: a prefix operator starts it`)
    (conflict `shift` `jump → "break" break_label` _ `4` `# the operand of \`break :l\` is parseExpr: a prefix operator starts it`)
    (conflict `shift` `jump → "continue"` _ `4` `# the operand of \`continue\` is parseExpr: a prefix operator starts it`)
    (conflict `shift` `jump → "continue" break_label` _ `4` `# the operand of \`continue :l\` is parseExpr: a prefix operator starts it`)
    (conflict `reduce` `for_expr → for_prefix bool_or` `for_expr → "inline" for_prefix bool_or` `3` `# a prong's leading \`inline\` is its flag`)
    (conflict `reduce` `for_expr → for_prefix bool_or "else" bool_or` `for_expr → "inline" for_prefix bool_or "else" bool_or` `3` `# a prong's leading \`inline\` is its flag`)
    (conflict `reduce` `while_expr → while_prefix bool_or` `while_expr → "inline" while_prefix bool_or` `3` `# a prong's leading \`inline\` is its flag`)
    (conflict `reduce` `while_expr → while_prefix bool_or "else" bool_or` `while_expr → "inline" while_prefix bool_or "else" bool_or` `3` `# a prong's leading \`inline\` is its flag`)
    (conflict `reduce` `while_expr → while_prefix bool_or "else" payload bool_or` `while_expr → "inline" while_prefix bool_or "else" payload bool_or` `3` `# a prong's leading \`inline\` is its flag`))
  (rule
    (start `root`)
    (alt
      _
      ((ref `container_body`))
      (node
        `root`
        (spread `1`))
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
    (name `container_body`)
    (alt
      _
      ((group
          opt
          ((quantified
              (tok `CONTAINER_DOC_COMMENT`)
              (one_plus))))
        (group
          opt
          ((ref `container_members`))))
      (pos `2`)
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
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (group
          opt
          ((ref `fn_prefix`)))
        (ref `fn_proto`)
        (lit `";"`))
      (node
        `fn_decl`
        (pos `2`)
        (pos `3`)
        (pos `4`))
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
          ((ref `fn_prefix`)))
        (ref `fn_proto`)
        (ref `block`))
      (node
        `fn_decl`
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((group
          opt
          ((ref `docs`)))
        (group
          opt
          ((lit `"pub"`)))
        (ref `extern_prefix`)
        (ref `fn_proto`)
        (lit `";"`))
      (node
        `fn_decl`
        (pos `2`)
        (pos `3`)
        (pos `4`))
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
          ((ref `var_prefix`)))
        (group
          opt
          ((lit `"threadlocal"`)))
        (ref `var_decl_proto`)
        (group
          opt
          ((lit `"="`)
            (ref `expr`)))
        (lit `";"`))
      (node
        `var_decl`
        (pos `2`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`))
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
    (name `var_prefix`)
    (alt
      _
      ((lit `"export"`))
      _
      _)
    (alt
      _
      ((ref `extern_prefix`))
      _
      _))
  (rule
    (name `extern_prefix`)
    (alt
      _
      ((lit `"extern"`)
        (group
          opt
          ((tok `STRING_LITERAL`))))
      (node
        `extern`
        (pos `2`))
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
    (name `fn_proto`)
    (alt
      _
      ((lit `"fn"`)
        (group
          opt
          ((tok `IDENTIFIER`)))
        (ref `param_decl_list`)
        (group
          opt
          ((ref `byte_align`)))
        (group
          opt
          ((ref `addr_space`)))
        (group
          opt
          ((ref `link_section`)))
        (group
          opt
          ((ref `call_conv`)))
        (group
          opt
          ((lit `"!"`)))
        (ref `type_expr`))
      (node
        `fn_proto`
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
    (name `var_decl_proto`)
    (alt
      _
      ((ref `var_mut`)
        (ref `var_name`)
        (group
          opt
          ((lit `":"`)
            (ref `type_expr`)))
        (group
          opt
          ((ref `byte_align`)))
        (group
          opt
          ((ref `addr_space`)))
        (group
          opt
          ((ref `link_section`))))
      (node
        `var_decl_proto`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `7`))
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
    (name `param_decl_list`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      (node `params`)
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `param_decl`))
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `params`
        (spread `2`))
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `param_decl`))
        (lit `","`)
        (ref `var_args`)
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `params`
        (spread `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `var_args`)
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `params`
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
      (node `var_args`)
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
    (name `byte_align`)
    (alt
      _
      ((lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `align`
        (pos `3`))
      _))
  (rule
    (name `addr_space`)
    (alt
      _
      ((lit `"addrspace"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `addrspace`
        (pos `3`))
      _))
  (rule
    (name `link_section`)
    (alt
      _
      ((lit `"linksection"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `linksection`
        (pos `3`))
      _))
  (rule
    (name `call_conv`)
    (alt
      _
      ((lit `"callconv"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `callconv`
        (pos `3`))
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
      ((ref `var_decl_proto`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `var_decl`
        (null)
        (null)
        (null)
        (pos `1`)
        (pos `3`))
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
        (ref `var_decl_proto`)
        (lit `"="`)
        (ref `expr`)
        (lit `";"`))
      (node
        `var_decl`
        (null)
        (pos `1`)
        (null)
        (pos `2`)
        (pos `4`))
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
      ((ref `var_decl_proto`))
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
      ((ref `var_decl_proto`))
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
      ((ref `var_decl_proto`))
      _
      _)
    (alt
      _
      ((ref `expr`))
      _
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
        (ref `assign_c`)
        (lit `";"`))
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
    (name `if_statement`)
    (alt
      _
      ((ref `if_prefix`)
        (ref `block_expr`))
      (node
        `if`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_prefix`)
        (ref `block_expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `statement`))
      (node
        `if`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `if_prefix`)
        (ref `assign_c`)
        (lit `";"`))
      (node
        `if`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_prefix`)
        (ref `assign_c`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `statement`))
      (node
        `if`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`))
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
        (ref `for_prefix`)
        (ref `block_expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
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
        (ref `for_prefix`)
        (ref `block_expr`)
        (lit `"else"`)
        (ref `statement`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`))
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
        (ref `for_prefix`)
        (ref `assign_c`)
        (lit `";"`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
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
        (ref `for_prefix`)
        (ref `assign_c`)
        (lit `"else"`)
        (ref `statement`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`))
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
        (ref `while_prefix`)
        (ref `block_expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
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
        (ref `while_prefix`)
        (ref `block_expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `statement`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`)
        (pos `8`))
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
        (ref `while_prefix`)
        (ref `assign_c`)
        (lit `";"`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
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
        (ref `while_prefix`)
        (ref `assign_c`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `statement`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`)
        (pos `8`))
      _))
  (rule
    (name `if_prefix`)
    (alt
      _
      ((lit `"if"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (group
          opt
          ((ref `ptr_payload`))))
      (list
        (pos `3`)
        (pos `5`))
      _))
  (rule
    (name `while_prefix`)
    (alt
      _
      ((lit `"while"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (group
          opt
          ((ref `ptr_payload`)))
        (group
          opt
          ((ref `while_continue_expr`))))
      (list
        (pos `3`)
        (pos `5`)
        (pos `6`))
      _))
  (rule
    (name `for_prefix`)
    (alt
      _
      ((lit `"for"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `for_item`))
        (group
          opt
          ((lit `","`)))
        (lit `")"`)
        (ref `ptr_list_payload`))
      (list
        (pos `3`)
        (pos `6`))
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
    (name `while_continue_expr`)
    (alt
      _
      ((lit `":"`)
        (lit `"("`)
        (ref `assign_expr`)
        (lit `")"`))
      (pos `3`)
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
    (name `expr`)
    (alt
      _
      ((ref `bool_or`))
      _
      _))
  (rule
    (name `expr_s`)
    (alt
      _
      ((ref `bool_or_s`))
      _
      _))
  (rule
    (name `expr_c`)
    (alt
      _
      ((ref `bool_or_c`))
      _
      _))
  (rule
    (name `expr_p`)
    (alt
      _
      ((ref `bool_or_p`))
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
    (name `bool_or`)
    (alt
      _
      ((ref `bool_and`))
      _
      _)
    (alt
      _
      ((ref `bool_or_k`)
        (lit `"or"`)
        (ref `bool_and`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_k`)
    (alt
      _
      ((ref `bool_and_k`))
      _
      _)
    (alt
      _
      ((ref `bool_or_k`)
        (lit `"or"`)
        (ref `bool_and_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_s`)
    (alt
      _
      ((ref `bool_and_s`))
      _
      _)
    (alt
      _
      ((ref `bool_or_sk`)
        (lit `"or"`)
        (ref `bool_and`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_sk`)
    (alt
      _
      ((ref `bool_and_sk`))
      _
      _)
    (alt
      _
      ((ref `bool_or_sk`)
        (lit `"or"`)
        (ref `bool_and_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_c`)
    (alt
      _
      ((ref `bool_and_c`))
      _
      _)
    (alt
      _
      ((ref `bool_or_ck`)
        (lit `"or"`)
        (ref `bool_and`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_ck`)
    (alt
      _
      ((ref `bool_and_ck`))
      _
      _)
    (alt
      _
      ((ref `bool_or_ck`)
        (lit `"or"`)
        (ref `bool_and_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_p`)
    (alt
      _
      ((ref `bool_and_p`))
      _
      _)
    (alt
      _
      ((ref `bool_or_pk`)
        (lit `"or"`)
        (ref `bool_and`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_or_pk`)
    (alt
      _
      ((ref `bool_and_pk`))
      _
      _)
    (alt
      _
      ((ref `bool_or_pk`)
        (lit `"or"`)
        (ref `bool_and_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and`)
    (alt
      _
      ((ref `compare`))
      _
      _)
    (alt
      _
      ((ref `bool_and_k`)
        (lit `"and"`)
        (ref `compare`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_k`)
    (alt
      _
      ((ref `compare_k`))
      _
      _)
    (alt
      _
      ((ref `bool_and_k`)
        (lit `"and"`)
        (ref `compare_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_s`)
    (alt
      _
      ((ref `compare_s`))
      _
      _)
    (alt
      _
      ((ref `bool_and_sk`)
        (lit `"and"`)
        (ref `compare`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_sk`)
    (alt
      _
      ((ref `compare_sk`))
      _
      _)
    (alt
      _
      ((ref `bool_and_sk`)
        (lit `"and"`)
        (ref `compare_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_c`)
    (alt
      _
      ((ref `compare_c`))
      _
      _)
    (alt
      _
      ((ref `bool_and_ck`)
        (lit `"and"`)
        (ref `compare`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_ck`)
    (alt
      _
      ((ref `compare_ck`))
      _
      _)
    (alt
      _
      ((ref `bool_and_ck`)
        (lit `"and"`)
        (ref `compare_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_p`)
    (alt
      _
      ((ref `compare_p`))
      _
      _)
    (alt
      _
      ((ref `bool_and_pk`)
        (lit `"and"`)
        (ref `compare`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bool_and_pk`)
    (alt
      _
      ((ref `compare_pk`))
      _
      _)
    (alt
      _
      ((ref `bool_and_pk`)
        (lit `"and"`)
        (ref `compare_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare`)
    (alt
      _
      ((ref `bitwise`))
      _
      _)
    (alt
      _
      ((ref `bitwise_k`)
        (ref `compare_op`)
        (ref `bitwise`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_k`)
    (alt
      _
      ((ref `bitwise_k`))
      _
      _)
    (alt
      _
      ((ref `bitwise_k`)
        (ref `compare_op`)
        (ref `bitwise_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_s`)
    (alt
      _
      ((ref `bitwise_s`))
      _
      _)
    (alt
      _
      ((ref `bitwise_sk`)
        (ref `compare_op`)
        (ref `bitwise`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_sk`)
    (alt
      _
      ((ref `bitwise_sk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_sk`)
        (ref `compare_op`)
        (ref `bitwise_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_c`)
    (alt
      _
      ((ref `bitwise_c`))
      _
      _)
    (alt
      _
      ((ref `bitwise_ck`)
        (ref `compare_op`)
        (ref `bitwise`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_ck`)
    (alt
      _
      ((ref `bitwise_ck`))
      _
      _)
    (alt
      _
      ((ref `bitwise_ck`)
        (ref `compare_op`)
        (ref `bitwise_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_p`)
    (alt
      _
      ((ref `bitwise_p`))
      _
      _)
    (alt
      _
      ((ref `bitwise_pk`)
        (ref `compare_op`)
        (ref `bitwise`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `compare_pk`)
    (alt
      _
      ((ref `bitwise_pk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_pk`)
        (ref `compare_op`)
        (ref `bitwise_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bitwise`)
    (alt
      _
      ((ref `bit_shift`))
      _
      _)
    (alt
      _
      ((ref `bitwise_k`)
        (ref `bitwise_op`)
        (ref `bit_shift`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_k`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_k`)
    (alt
      _
      ((ref `bit_shift_k`))
      _
      _)
    (alt
      _
      ((ref `bitwise_k`)
        (ref `bitwise_op`)
        (ref `bit_shift_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_k`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_s`)
    (alt
      _
      ((ref `bit_shift_s`))
      _
      _)
    (alt
      _
      ((ref `bitwise_sk`)
        (ref `bitwise_op`)
        (ref `bit_shift`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_sk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_sk`)
    (alt
      _
      ((ref `bit_shift_sk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_sk`)
        (ref `bitwise_op`)
        (ref `bit_shift_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_sk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_c`)
    (alt
      _
      ((ref `bit_shift_c`))
      _
      _)
    (alt
      _
      ((ref `bitwise_ck`)
        (ref `bitwise_op`)
        (ref `bit_shift`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_ck`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_ck`)
    (alt
      _
      ((ref `bit_shift_ck`))
      _
      _)
    (alt
      _
      ((ref `bitwise_ck`)
        (ref `bitwise_op`)
        (ref `bit_shift_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_ck`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_p`)
    (alt
      _
      ((ref `bit_shift_p`))
      _
      _)
    (alt
      _
      ((ref `bitwise_pk`)
        (ref `bitwise_op`)
        (ref `bit_shift`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_pk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bitwise_pk`)
    (alt
      _
      ((ref `bit_shift_pk`))
      _
      _)
    (alt
      _
      ((ref `bitwise_pk`)
        (ref `bitwise_op`)
        (ref `bit_shift_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `bitwise_pk`)
        (lit `"catch"`)
        (group
          opt
          ((ref `payload`)))
        (ref `bit_shift_k`))
      (node
        `catch`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _))
  (rule
    (name `bit_shift`)
    (alt
      _
      ((ref `addition`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_k`)
        (ref `bit_shift_op`)
        (ref `addition`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_k`)
    (alt
      _
      ((ref `addition_k`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_k`)
        (ref `bit_shift_op`)
        (ref `addition_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_s`)
    (alt
      _
      ((ref `addition_s`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_sk`)
        (ref `bit_shift_op`)
        (ref `addition`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_sk`)
    (alt
      _
      ((ref `addition_sk`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_sk`)
        (ref `bit_shift_op`)
        (ref `addition_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_c`)
    (alt
      _
      ((ref `addition_c`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_ck`)
        (ref `bit_shift_op`)
        (ref `addition`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_ck`)
    (alt
      _
      ((ref `addition_ck`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_ck`)
        (ref `bit_shift_op`)
        (ref `addition_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_p`)
    (alt
      _
      ((ref `addition_p`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_pk`)
        (ref `bit_shift_op`)
        (ref `addition`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `bit_shift_pk`)
    (alt
      _
      ((ref `addition_pk`))
      _
      _)
    (alt
      _
      ((ref `bit_shift_pk`)
        (ref `bit_shift_op`)
        (ref `addition_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition`)
    (alt
      _
      ((ref `multiply`))
      _
      _)
    (alt
      _
      ((ref `addition_k`)
        (ref `addition_op`)
        (ref `multiply`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_k`)
    (alt
      _
      ((ref `multiply_k`))
      _
      _)
    (alt
      _
      ((ref `addition_k`)
        (ref `addition_op`)
        (ref `multiply_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_s`)
    (alt
      _
      ((ref `multiply_s`))
      _
      _)
    (alt
      _
      ((ref `addition_sk`)
        (ref `addition_op`)
        (ref `multiply`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_sk`)
    (alt
      _
      ((ref `multiply_sk`))
      _
      _)
    (alt
      _
      ((ref `addition_sk`)
        (ref `addition_op`)
        (ref `multiply_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_c`)
    (alt
      _
      ((ref `multiply_c`))
      _
      _)
    (alt
      _
      ((ref `addition_ck`)
        (ref `addition_op`)
        (ref `multiply`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_ck`)
    (alt
      _
      ((ref `multiply_ck`))
      _
      _)
    (alt
      _
      ((ref `addition_ck`)
        (ref `addition_op`)
        (ref `multiply_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_p`)
    (alt
      _
      ((ref `multiply_p`))
      _
      _)
    (alt
      _
      ((ref `addition_pk`)
        (ref `addition_op`)
        (ref `multiply`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `addition_pk`)
    (alt
      _
      ((ref `multiply_pk`))
      _
      _)
    (alt
      _
      ((ref `addition_pk`)
        (ref `addition_op`)
        (ref `multiply_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply`)
    (alt
      _
      ((ref `prefix`))
      _
      _)
    (alt
      _
      ((ref `multiply_k`)
        (ref `multiply_op`)
        (ref `prefix`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_k`)
    (alt
      _
      ((ref `prefix_k`))
      _
      _)
    (alt
      _
      ((ref `multiply_k`)
        (ref `multiply_op`)
        (ref `prefix_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_s`)
    (alt
      _
      ((ref `prefix_s`))
      _
      _)
    (alt
      _
      ((ref `multiply_sk`)
        (ref `multiply_op`)
        (ref `prefix`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_sk`)
    (alt
      _
      ((ref `prefix_sk`))
      _
      _)
    (alt
      _
      ((ref `multiply_sk`)
        (ref `multiply_op`)
        (ref `prefix_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_c`)
    (alt
      _
      ((ref `prefix_c`))
      _
      _)
    (alt
      _
      ((ref `multiply_ck`)
        (ref `multiply_op`)
        (ref `prefix`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_ck`)
    (alt
      _
      ((ref `prefix_ck`))
      _
      _)
    (alt
      _
      ((ref `multiply_ck`)
        (ref `multiply_op`)
        (ref `prefix_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_p`)
    (alt
      _
      ((ref `prefix_p`))
      _
      _)
    (alt
      _
      ((ref `multiply_pk`)
        (ref `multiply_op`)
        (ref `prefix`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `multiply_pk`)
    (alt
      _
      ((ref `prefix_pk`))
      _
      _)
    (alt
      _
      ((ref `multiply_pk`)
        (ref `multiply_op`)
        (ref `prefix_k`))
      (node
        `binary`
        (pos `2`)
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `prefix`)
    (alt
      _
      ((ref `primary`))
      _
      _)
    (alt
      _
      ((ref `prefixed`))
      _
      _))
  (rule
    (name `prefix_k`)
    (alt
      _
      ((ref `primary_k`))
      _
      _)
    (alt
      _
      ((ref `prefixed_k`))
      _
      _))
  (rule
    (name `prefix_s`)
    (alt
      _
      ((ref `primary_s`))
      _
      _)
    (alt
      _
      ((ref `prefixed`))
      _
      _))
  (rule
    (name `prefix_sk`)
    (alt
      _
      ((ref `primary_sk`))
      _
      _)
    (alt
      _
      ((ref `prefixed_k`))
      _
      _))
  (rule
    (name `prefix_c`)
    (alt
      _
      ((ref `primary_c`))
      _
      _)
    (alt
      _
      ((ref `prefixed`))
      _
      _))
  (rule
    (name `prefix_ck`)
    (alt
      _
      ((ref `primary_ck`))
      _
      _)
    (alt
      _
      ((ref `prefixed_k`))
      _
      _))
  (rule
    (name `prefix_p`)
    (alt
      _
      ((ref `ptr_curly`))
      _
      _))
  (rule
    (name `prefix_pk`)
    (alt
      _
      ((ref `ptr_curly`))
      _
      _))
  (rule
    (name `prefixed`)
    (alt
      _
      ((lit `"!"`)
        (ref `prefix`))
      (node
        `bool_not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `minus`)
        (ref `prefix`))
      (node
        `negation`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `prefix`))
      (node
        `bit_not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `minus_wrap`)
        (ref `prefix`))
      (node
        `negation_wrap`
        (pos `2`))
      _)
    (alt
      _
      ((ref `amp`)
        (ref `prefix`))
      (node
        `address_of`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"try"`)
        (ref `prefix`))
      (node
        `try`
        (pos `2`))
      _))
  (rule
    (name `prefixed_k`)
    (alt
      _
      ((lit `"!"`)
        (ref `prefix_k`))
      (node
        `bool_not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `minus`)
        (ref `prefix_k`))
      (node
        `negation`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"~"`)
        (ref `prefix_k`))
      (node
        `bit_not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `minus_wrap`)
        (ref `prefix_k`))
      (node
        `negation_wrap`
        (pos `2`))
      _)
    (alt
      _
      ((ref `amp`)
        (ref `prefix_k`))
      (node
        `address_of`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"try"`)
        (ref `prefix_k`))
      (node
        `try`
        (pos `2`))
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
    (name `primary`)
    (alt
      _
      ((ref `primary_k`))
      _
      _)
    (alt
      _
      ((ref `open_expr`))
      _
      _))
  (rule
    (name `primary_k`)
    (alt
      _
      ((ref `curly`))
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
    (name `primary_s`)
    (alt
      _
      ((ref `primary_sk`))
      _
      _)
    (alt
      _
      ((ref `jump_open`))
      _
      _))
  (rule
    (name `primary_sk`)
    (alt
      _
      ((ref `curly_s`))
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
    (name `primary_c`)
    (alt
      _
      ((ref `primary_ck`))
      _
      _)
    (alt
      _
      ((ref `open_expr`))
      _
      _))
  (rule
    (name `primary_ck`)
    (alt
      _
      ((ref `curly_c`))
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
    (name `break_label`)
    (alt
      _
      ((tok `BREAK_COLON`)
        (tok `IDENTIFIER`))
      (pos `2`)
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
      ((ref `if_prefix`)
        (ref `expr`))
      (node
        `if`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_prefix`)
        (ref `expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `expr`))
      (node
        `if`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `for_expr`)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (ref `for_prefix`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (null)
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (ref `for_prefix`)
        (ref `expr`)
        (lit `"else"`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (null)
        (pos `3`)
        (pos `4`)
        (pos `6`))
      _)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (ref `for_prefix`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (ref `for_prefix`)
        (ref `expr`)
        (lit `"else"`)
        (ref `expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`))
      _))
  (rule
    (name `while_expr`)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (ref `while_prefix`)
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (null)
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (ref `while_prefix`)
        (ref `expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (null)
        (pos `3`)
        (pos `4`)
        (pos `6`)
        (pos `7`))
      _)
    (alt
      `>`
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (ref `while_prefix`)
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((group
          opt
          ((tok `LABEL`)
            (lit `":"`)))
        (lit `"inline"`)
        (ref `while_prefix`)
        (ref `expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`)
        (pos `8`))
      _))
  (rule
    (name `curly`)
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `curly_s`)
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `curly_c`)
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `ptr_curly`)
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
        (lit `"}"`))
      (node
        `array_init`
        (pos `1`)
        (spread `3`))
      _))
  (rule
    (name `ptr_led`)
    (alt
      _
      ((tok `PTR_STAR`)
        (ref `single_ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `2`)
        (pos `3`))
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
    (name `payload`)
    (alt
      _
      ((ref `pipe`)
        (tok `IDENTIFIER`)
        (ref `pipe`))
      (pos `2`)
      _))
  (rule
    (name `ptr_payload`)
    (alt
      _
      ((ref `pipe`)
        (group
          opt
          ((ref `star`)))
        (tok `IDENTIFIER`)
        (ref `pipe`))
      (node
        `capture`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `ptr_index_payload`)
    (alt
      _
      ((ref `pipe`)
        (group
          opt
          ((ref `star`)))
        (tok `IDENTIFIER`)
        (group
          opt
          ((lit `","`)
            (tok `IDENTIFIER`)))
        (ref `pipe`))
      (node
        `capture`
        (pos `2`)
        (pos `3`)
        (pos `5`))
      _))
  (rule
    (name `ptr_list_payload`)
    (alt
      _
      ((ref `pipe`)
        (list_req
          `L`
          (plain `capture`))
        (group
          opt
          ((lit `","`)))
        (ref `pipe`))
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
    (name `type_expr`)
    (alt
      _
      ((ref `prefix_type`))
      _
      _)
    (alt
      _
      ((ref `error_union`))
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
      ((ref `error_union_n`))
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
      ((ref `error_union_n`))
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
      ((ref `error_union_n`))
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
      ((ref `error_union`))
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
      ((ref `error_union_s`))
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
      ((ref `error_union_c`))
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
      ((ref `star`)
        (ref `single_ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `one`)
        (null)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `"]"`)
        (ref `ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (null)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`)
        (ref `ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `c`)
        (null)
        (pos `5`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"["`)
        (tok `PTR_STAR`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `many`)
        (pos `4`)
        (pos `6`)
        (pos `7`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `"]"`)
        (ref `ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (null)
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"["`)
        (lit `":"`)
        (ref `expr`)
        (lit `"]"`)
        (ref `ptr_mods`)
        (ref `type_expr`))
      (node
        `ptr_type`
        (tag `slice`)
        (pos `3`)
        (pos `5`)
        (pos `6`))
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
    (name `single_ptr_mods`)
    (alt
      _
      ((ref `ptr_quals`))
      (list
        (spread `1`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `bit_align`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `bit_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`)
        (pos `4`)
        (spread `5`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `bit_align`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`)
        (pos `4`)
        (spread `5`))
      _))
  (rule
    (name `ptr_mods`)
    (alt
      _
      ((ref `ptr_quals`))
      (list
        (spread `1`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`)
        (pos `4`)
        (spread `5`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `ptr_quals`)
        (ref `addr_space`)
        (ref `ptr_quals`)
        (ref `byte_align`)
        (ref `ptr_quals`))
      (list
        (spread `1`)
        (pos `2`)
        (spread `3`)
        (pos `4`)
        (spread `5`))
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
    (name `bit_align`)
    (alt
      _
      ((lit `"align"`)
        (lit `"("`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `")"`))
      (node
        `align`
        (pos `3`)
        (pos `5`)
        (pos `7`))
      _)
    (alt
      _
      ((ref `byte_align`))
      _
      _))
  (rule
    (name `error_union`)
    (alt
      _
      ((ref `suffix`))
      _
      _)
    (alt
      _
      ((ref `suffix`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `error_union_s`)
    (alt
      _
      ((ref `suffix_s`))
      _
      _)
    (alt
      _
      ((ref `suffix_s`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `error_union_c`)
    (alt
      _
      ((ref `suffix_c`))
      _
      _)
    (alt
      _
      ((ref `suffix_c`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `error_union_n`)
    (alt
      _
      ((ref `suffix_n`))
      _
      _)
    (alt
      _
      ((ref `suffix_n`)
        (lit `"!"`)
        (ref `type_expr`))
      (node
        `error_union`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `suffix`)
    (alt
      _
      ((ref `primary_type`))
      _
      _)
    (alt
      _
      ((ref `suffix`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix`)
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
      ((ref `suffix`)
        (lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (node
          `ptr_type`
          (tag `one`)
          (null)
          (null)
          (pos `4`)))
      _)
    (alt
      _
      ((ref `suffix`)
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
      ((ref `suffix`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `suffix_s`)
    (alt
      _
      ((ref `primary_type_s`))
      _
      _)
    (alt
      _
      ((ref `suffix_s`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_s`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_s`)
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
      ((ref `suffix_s`)
        (lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (node
          `ptr_type`
          (tag `one`)
          (null)
          (null)
          (pos `4`)))
      _)
    (alt
      _
      ((ref `suffix_s`)
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
      ((ref `suffix_s`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_s`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_s`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `suffix_c`)
    (alt
      _
      ((ref `primary_type_c`))
      _
      _)
    (alt
      _
      ((ref `suffix_c`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_c`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_c`)
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
      ((ref `suffix_c`)
        (lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (node
          `ptr_type`
          (tag `one`)
          (null)
          (null)
          (pos `4`)))
      _)
    (alt
      _
      ((ref `suffix_c`)
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
      ((ref `suffix_c`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_c`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_c`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `suffix_n`)
    (alt
      _
      ((ref `primary_type_n`))
      _
      _)
    (alt
      _
      ((ref `suffix_n`)
        (lit `"("`)
        (lit `")"`))
      (node
        `call`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_n`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (group
          opt
          ((lit `","`)))
        (lit `")"`))
      (node
        `call`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `suffix_n`)
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
      ((ref `suffix_n`)
        (lit `"["`)
        (tok `PTR_STAR`)
        (tok `C_PTR`)
        (lit `"]"`))
      (node
        `array_access`
        (pos `1`)
        (node
          `ptr_type`
          (tag `one`)
          (null)
          (null)
          (pos `4`)))
      _)
    (alt
      _
      ((ref `suffix_n`)
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
      ((ref `suffix_n`)
        (lit `"."`)
        (tok `IDENTIFIER`))
      (node
        `field_access`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `suffix_n`)
        (lit `".*"`))
      (node
        `deref`
        (pos `1`))
      _)
    (alt
      _
      ((ref `suffix_n`)
        (lit `"."`)
        (lit `"?"`))
      (node
        `unwrap_optional`
        (pos `1`))
      _))
  (rule
    (name `primary_type`)
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
    (name `primary_type_s`)
    (alt
      _
      ((ref `atom`))
      _
      _))
  (rule
    (name `primary_type_c`)
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
    (name `primary_type_n`)
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
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
        (group
          opt
          ((lit `","`)))
        (lit `"}"`))
      (node
        `error_set_decl`
        (spread `3`))
      _)
    (alt
      _
      ((lit `"unreachable"`))
      (node `unreachable_literal`)
      _)
    (alt
      _
      ((lit `"anyframe"`))
      (node `anyframe_literal`)
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
      (pos `2`)
      _))
  (rule
    (name `if_type_expr`)
    (alt
      `>`
      ((ref `if_prefix`)
        (ref `type_expr`))
      (node
        `if`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `if_prefix`)
        (ref `type_expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `type_expr`))
      (node
        `if`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `for_type_expr`)
    (alt
      `>`
      ((group
          opt
          ((lit `"inline"`)))
        (ref `for_prefix`)
        (ref `type_expr`))
      (node
        `for`
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((group
          opt
          ((lit `"inline"`)))
        (ref `for_prefix`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `type_expr`))
      (node
        `for`
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `5`))
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
        (ref `for_prefix`)
        (ref `type_expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((tok `LABEL`)
        (lit `":"`)
        (group
          opt
          ((lit `"inline"`)))
        (ref `for_prefix`)
        (ref `type_expr`)
        (lit `"else"`)
        (ref `type_expr`))
      (node
        `for`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`))
      _))
  (rule
    (name `while_type_expr`)
    (alt
      `>`
      ((group
          opt
          ((lit `"inline"`)))
        (ref `while_prefix`)
        (ref `type_expr`))
      (node
        `while`
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((group
          opt
          ((lit `"inline"`)))
        (ref `while_prefix`)
        (ref `type_expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `type_expr`))
      (node
        `while`
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`)
        (pos `5`)
        (pos `6`))
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
        (ref `while_prefix`)
        (ref `type_expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((tok `LABEL`)
        (lit `":"`)
        (group
          opt
          ((lit `"inline"`)))
        (ref `while_prefix`)
        (ref `type_expr`)
        (lit `"else"`)
        (group
          opt
          ((ref `payload`)))
        (ref `type_expr`))
      (node
        `while`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`)
        (pos `7`)
        (pos `8`))
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
        (ref `container_body`)
        (lit `"}"`))
      (node
        `container_decl`
        (pos `1`)
        (pos `2`)
        (spread `4`))
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
      (node `struct`)
      _)
    (alt
      _
      ((lit `"struct"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `struct`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"opaque"`))
      (node `opaque`)
      _)
    (alt
      _
      ((lit `"enum"`))
      (node `enum`)
      _)
    (alt
      _
      ((lit `"enum"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `enum`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"union"`))
      (node `union`)
      _)
    (alt
      _
      ((lit `"union"`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `union`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"union"`)
        (lit `"("`)
        (tok `ENUM_TAG`)
        (lit `")"`))
      (node
        `union`
        (tag `enum`))
      _)
    (alt
      _
      ((lit `"union"`)
        (lit `"("`)
        (tok `ENUM_TAG`)
        (lit `"("`)
        (ref `expr`)
        (lit `")"`)
        (lit `")"`))
      (node
        `union`
        (tag `enum`)
        (pos `5`))
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
          ((ref `switch_prongs`)))
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
          ((ref `switch_prongs`)))
        (lit `"}"`))
      (node
        `switch`
        (pos `1`)
        (pos `5`)
        (spread `8`))
      _))
  (rule
    (name `switch_prongs`)
    (alt
      _
      ((list_req
          `L`
          (plain `switch_prong`))
        (group
          opt
          ((lit `","`))))
      (pos `1`)
      _))
  (rule
    (name `switch_prong`)
    (alt
      _
      ((ref `switch_case`)
        (lit `"=>"`)
        (group
          opt
          ((ref `ptr_index_payload`)))
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (null)
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"inline"`)
        (ref `switch_case`)
        (lit `"=>"`)
        (group
          opt
          ((ref `ptr_index_payload`)))
        (ref `single_assign_expr`))
      (node
        `switch_case`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `switch_case`)
    (alt
      _
      ((lit `"else"`))
      (node `else`)
      _)
    (alt
      _
      ((list_req
          `L`
          (plain `switch_item`))
        (group
          opt
          ((lit `","`))))
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
        (group
          opt
          ((ref `asm_outputs`)))
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`)
        (pos `6`))
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
        (group
          opt
          ((ref `asm_outputs`)))
        (lit `":"`)
        (group
          opt
          ((ref `asm_inputs`)))
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (pos `8`))
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
        (group
          opt
          ((ref `asm_outputs`)))
        (lit `":"`)
        (group
          opt
          ((ref `asm_inputs`)))
        (lit `":"`)
        (ref `expr`)
        (lit `")"`))
      (node
        `asm`
        (pos `2`)
        (pos `4`)
        (pos `6`)
        (pos `8`)
        (pos `10`))
      _))
  (rule
    (name `asm_outputs`)
    (alt
      _
      ((list_req
          `L`
          (plain `asm_output_item`))
        (group
          opt
          ((lit `","`))))
      (pos `1`)
      _))
  (rule
    (name `asm_inputs`)
    (alt
      _
      ((list_req
          `L`
          (plain `asm_input_item`))
        (group
          opt
          ((lit `","`))))
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
        (pos `6`))
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
