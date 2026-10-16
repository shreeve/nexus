(grammar
  (section `lexer`)
  (tokens `tokens` `name` `number` `string` `comment` `concat` `eq` `plus` `lt` `not` `dollar` `lparen` `rparen` `comma` `colon` `dot` `newline` `eof` `err`)
  (lex_rule `';' [^\\n]*` _ `comment`)
  (lex_rule `'"' ([^"\\n] | '""')* '"'` _ `string`)
  (lex_rule `[0-9]+` _ `number`)
  (lex_rule `[%A-Za-z] [A-Za-z0-9]*` _ `name`)
  (lex_rule `'_'` _ `concat`)
  (lex_rule `'='` _ `eq`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'<'` _ `lt`)
  (lex_rule `"'"` _ `not`)
  (lex_rule `'$'` _ `dollar`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (keywords
    (kw_group `cmd` `caseless` `base` `100` `S[ET]` `W[RITE]` `I[F]` `E[LSE]` `Q[UIT]` `X[ECUTE]` `D[O]`)
    (kw_group `fn` `caseless` `base` `200` `E[XTRACT]` `L[ENGTH]` `P[IECE]` `D[ATA]`))
  (as
    `NAME`
    _
    (as_entry perm `cmd` _)
    (as_entry perm `fn` _))
  (highlight
    (hl_line `language` `"Mint"`)
    (hl_line `scope-name` `source.mint`)
    (hl_line `extensions` `mint`)
    (hl_line `line-comment` `";"`)
    (hl_line `word-chars` `[%A-Za-z0-9]`)
    (hl_line `label` `line-start ([%A-Za-z] [A-Za-z0-9]* | [0-9]+)`)
    (hl_line `keyword.control` `cmd before [ \\t.] not after [^ \\t:]`)
    (hl_line `function.builtin` `fn before '$' after '('`)
    (hl_line `constant` `"TRUE" "FALSE"`)
    (hl_line `operator` `"_" "=" "+" "<" "'"`)
    (hl_line `punctuation` `"(" ")" "," ":" "$" "."`)
    (hl_line `constant.numeric` `NUMBER`)
    (hl_line `string` `STRING`)
    (hl_line `string.escape` `'""' within STRING`)
    (hl_line `comment` `COMMENT`))
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
      ((tok `NAME`))
      _
      _)
    (alt
      _
      ((tok `NUMBER`))
      _
      _)
    (alt
      _
      ((tok `STRING`))
      _
      _)
    (alt
      _
      ((tok `COMMENT`))
      _
      _)
    (alt
      _
      ((tok `CONCAT`))
      _
      _)
    (alt
      _
      ((tok `EQ`))
      _
      _)
    (alt
      _
      ((tok `PLUS`))
      _
      _)
    (alt
      _
      ((tok `LT`))
      _
      _)
    (alt
      _
      ((tok `NOT`))
      _
      _)
    (alt
      _
      ((tok `DOLLAR`))
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
      ((tok `NEWLINE`))
      _
      _)
    (alt
      _
      ((tok `ERR`))
      _
      _)
    (alt
      _
      ((tok `SET`))
      _
      _)
    (alt
      _
      ((tok `WRITE`))
      _
      _)
    (alt
      _
      ((tok `IF`))
      _
      _)
    (alt
      _
      ((tok `ELSE`))
      _
      _)
    (alt
      _
      ((tok `QUIT`))
      _
      _)
    (alt
      _
      ((tok `XECUTE`))
      _
      _)
    (alt
      _
      ((tok `DO`))
      _
      _)
    (alt
      _
      ((tok `EXTRACT`))
      _
      _)
    (alt
      _
      ((tok `LENGTH`))
      _
      _)
    (alt
      _
      ((tok `PIECE`))
      _
      _)
    (alt
      _
      ((tok `DATA`))
      _
      _)))
