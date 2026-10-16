(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `call` `type_name` `integer` `real` `string_dq` `string_sq` `comment` `block_comment` `directive` `builtin` `plus` `minus` `star` `power` `lt` `le` `shl` `shl_assign` `assign` `eq` `arrow` `lparen` `rparen` `lbracket` `rbracket` `lbrace` `rbrace` `comma` `colon` `dot` `bang` `question` `newline` `kw_fun` `kw_if` `kw_else` `kw_while` `kw_return` `kw_pub` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'/*' ([^*] | '*'+ [^*/])* '*'+ '/'` _ `block_comment`)
  (lex_rule `'%' [a-z]+` _ `directive`)
  (lex_rule `'"' ([^"\\\\\\n] | '\\\\' [^\\n])* '"'` _ `string_dq`)
  (lex_rule `"'" ([^'\\n] | "''")* "'"` _ `string_sq`)
  (lex_rule `[0-9]+ '.' [0-9]+` _ `real`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `'@' [a-z_]+` _ `builtin`)
  (lex_rule `"<<="` _ `shl_assign`)
  (lex_rule `"<<"` _ `shl`)
  (lex_rule `"<="` _ `le`)
  (lex_rule `'<'` _ `lt`)
  (lex_rule `"=="` _ `eq`)
  (lex_rule `'='` _ `assign`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule `"**"` _ `power`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'['` _ `lbracket`)
  (lex_rule `']'` _ `rbracket`)
  (lex_rule `'{'` _ `lbrace`)
  (lex_rule `'}'` _ `rbrace`)
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `'!'` _ `bang`)
  (lex_rule `'?'` _ `question`)
  (lex_rule `"fun"` _ `kw_fun`)
  (lex_rule `"if"` _ `kw_if`)
  (lex_rule `"else"` _ `kw_else`)
  (lex_rule `"while"` _ `kw_while`)
  (lex_rule `"return"` _ `kw_return`)
  (lex_rule `"pub"` _ `kw_pub`)
  (lex_rule `[a-z_] [A-Za-z0-9_]* / '('` _ `call`)
  (lex_rule `[A-Z] [A-Za-z0-9_]*` _ `type_name`)
  (lex_rule `[a-z_] [A-Za-z0-9_]*` _ `ident`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (keywords
    (kw_group `stmt` `caseless` `P[RINT]` `WR[ITE]` `ECHO=PRINT`))
  (as
    `IDENT`
    _
    (as_entry perm `stmt` _))
  (highlight
    (hl_line `language` `"Lamp"`)
    (hl_line `scope-name` `source.lamp`)
    (hl_line `extensions` `lamp lmp`)
    (hl_line `line-comment` `"#"`)
    (hl_line `block-comment` `"/*" "*/"`)
    (hl_line `indent` `'{' [ \\t]* line-end`)
    (hl_line `dedent` `line-start [ \\t]* '}'`)
    (hl_line `keyword` `"fun" [ \\t]+ function:([a-z_] [A-Za-z0-9_]*)`)
    (hl_line `keyword.control` `DIRECTIVE line-start`)
    (hl_line `operator` `'\\\\' line-end`)
    (hl_line `label` `line-start ([a-z_] [a-z0-9_]* | [0-9]+) after ':'`)
    (hl_line `constant` `[A-Z] [A-Z0-9_]+ not after [A-Za-z0-9_]`)
    (hl_line `type` `[a-z_] [a-z0-9_]* before "-> "`)
    (hl_line `label` `':' [a-z_]+ after [ \\t]* '{'`)
    (hl_line `constant.symbol` `':' [a-z_]+ not before [A-Za-z0-9_)]`)
    (hl_line `variable.parameter` `[a-z_] [a-z0-9_]* after ':' [ \\t]`)
    (hl_line `storage.modifier` `[!?] after [a-z_] not before [A-Za-z0-9_)\\]]`)
    (hl_line `keyword` `"fun" stmt`)
    (hl_line `keyword.control` `"if" "else" "while" "return"`)
    (hl_line `keyword.operator` `"and" "or" "not"`)
    (hl_line `constant` `"true" "false" "nil" not before '.' not after '('`)
    (hl_line `storage.modifier` `"pub"`)
    (hl_line `variable.special` `"self"`)
    (hl_line `operator` `"+" "-" "*" "<" "<=" "<<" "<<=" "==" "=" "->" "!" "?"`)
    (hl_line `punctuation` `"(" ")" "[" "]" "{" "}" "," "." ":"`)
    (hl_line `constant.numeric` `INTEGER REAL`)
    (hl_line `function` `CALL`)
    (hl_line `function.builtin` `BUILTIN`)
    (hl_line `type` `TYPE_NAME`)
    (hl_line `invalid` `"**" ERR`)
    (hl_line `string` `STRING_DQ STRING_SQ`)
    (hl_line `comment` `COMMENT BLOCK_COMMENT`)
    (hl_line `string.escape` `'\\\\' [nt"\\\\] within STRING_DQ`)
    (hl_line `variable.special` `'{' [a-z]+ '}' within STRING_DQ`)
    (hl_line `string.escape` `"''" within STRING_SQ`)
    (hl_line `keyword` `"TODO" within BLOCK_COMMENT`))
  (rule
    (start `program`)
    (alt
      _
      ((quantified
          (ref `item`)
          (zero_plus)))
      (node
        `program`
        (spread `1`))
      _))
  (rule
    (name `item`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `CALL`))
      _
      _)
    (alt
      _
      ((tok `TYPE_NAME`))
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
      ((tok `STRING_DQ`))
      _
      _)
    (alt
      _
      ((tok `STRING_SQ`))
      _
      _)
    (alt
      _
      ((tok `COMMENT`))
      _
      _)
    (alt
      _
      ((tok `BLOCK_COMMENT`))
      _
      _)
    (alt
      _
      ((tok `DIRECTIVE`))
      _
      _)
    (alt
      _
      ((tok `BUILTIN`))
      _
      _)
    (alt
      _
      ((tok `PLUS`))
      _
      _)
    (alt
      _
      ((tok `MINUS`))
      _
      _)
    (alt
      _
      ((tok `STAR`))
      _
      _)
    (alt
      _
      ((tok `POWER`))
      _
      _)
    (alt
      _
      ((tok `LT`))
      _
      _)
    (alt
      _
      ((tok `LE`))
      _
      _)
    (alt
      _
      ((tok `SHL`))
      _
      _)
    (alt
      _
      ((tok `SHL_ASSIGN`))
      _
      _)
    (alt
      _
      ((tok `ASSIGN`))
      _
      _)
    (alt
      _
      ((tok `EQ`))
      _
      _)
    (alt
      _
      ((tok `ARROW`))
      _
      _)
    (alt
      _
      ((tok `LPAREN`))
      _
      _)
    (alt
      _
      ((tok `RPAREN`))
      _
      _)
    (alt
      _
      ((tok `LBRACKET`))
      _
      _)
    (alt
      _
      ((tok `RBRACKET`))
      _
      _)
    (alt
      _
      ((tok `LBRACE`))
      _
      _)
    (alt
      _
      ((tok `RBRACE`))
      _
      _)
    (alt
      _
      ((tok `COMMA`))
      _
      _)
    (alt
      _
      ((tok `COLON`))
      _
      _)
    (alt
      _
      ((tok `DOT`))
      _
      _)
    (alt
      _
      ((tok `BANG`))
      _
      _)
    (alt
      _
      ((tok `QUESTION`))
      _
      _)
    (alt
      _
      ((tok `NEWLINE`))
      _
      _)
    (alt
      _
      ((tok `KW_FUN`))
      _
      _)
    (alt
      _
      ((tok `KW_IF`))
      _
      _)
    (alt
      _
      ((tok `KW_ELSE`))
      _
      _)
    (alt
      _
      ((tok `KW_WHILE`))
      _
      _)
    (alt
      _
      ((tok `KW_RETURN`))
      _
      _)
    (alt
      _
      ((tok `KW_PUB`))
      _
      _)
    (alt
      _
      ((tok `PRINT`))
      _
      _)
    (alt
      _
      ((tok `WRITE`))
      _
      _)
    (alt
      _
      ((tok `ERR`))
      _
      _)))
