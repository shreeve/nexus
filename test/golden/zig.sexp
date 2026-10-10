(grammar
  (lang `"zig"`)
  (section `lexer`)
  (tokens `tokens` `invalid` `identifier` `string_literal` `multiline_string_literal_line` `char_literal` `builtin` `number_literal` `doc_comment` `container_doc_comment` `bang` `pipe` `pipe_pipe` `pipe_equal` `equal` `equal_equal` `equal_angle_bracket_right` `bang_equal` `l_paren` `r_paren` `semicolon` `percent` `percent_equal` `l_brace` `r_brace` `l_bracket` `r_bracket` `period` `period_asterisk` `ellipsis2` `ellipsis3` `caret` `caret_equal` `plus` `plus_plus` `plus_equal` `plus_percent` `plus_percent_equal` `plus_pipe` `plus_pipe_equal` `minus` `minus_equal` `minus_percent` `minus_percent_equal` `minus_pipe` `minus_pipe_equal` `asterisk` `asterisk_equal` `asterisk_percent` `asterisk_percent_equal` `asterisk_pipe` `asterisk_pipe_equal` `arrow` `colon` `slash` `slash_equal` `comma` `ampersand` `ampersand_equal` `question_mark` `angle_bracket_left` `angle_bracket_left_equal` `angle_bracket_angle_bracket_left` `angle_bracket_angle_bracket_left_equal` `angle_bracket_angle_bracket_left_pipe` `angle_bracket_angle_bracket_left_pipe_equal` `angle_bracket_right` `angle_bracket_right_equal` `angle_bracket_angle_bracket_right` `angle_bracket_angle_bracket_right_equal` `tilde` `keyword_addrspace` `keyword_align` `keyword_allowzero` `keyword_and` `keyword_anyframe` `keyword_anytype` `keyword_asm` `keyword_break` `keyword_callconv` `keyword_catch` `keyword_comptime` `keyword_const` `keyword_continue` `keyword_defer` `keyword_else` `keyword_enum` `keyword_errdefer` `keyword_error` `keyword_export` `keyword_extern` `keyword_fn` `keyword_for` `keyword_if` `keyword_inline` `keyword_noalias` `keyword_noinline` `keyword_nosuspend` `keyword_opaque` `keyword_or` `keyword_orelse` `keyword_packed` `keyword_pub` `keyword_resume` `keyword_return` `keyword_linksection` `keyword_struct` `keyword_suspend` `keyword_switch` `keyword_test` `keyword_threadlocal` `keyword_try` `keyword_union` `keyword_unreachable` `keyword_var` `keyword_volatile` `keyword_while` `eof` `err`)
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
      _)))
