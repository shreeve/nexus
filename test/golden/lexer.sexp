(grammar
  (section `lexer`)
  (state
    `state`
    (assign `beg` `1`)
    (assign `mode` `0`))
  (after
    `after`
    (assign `beg` `0`))
  (tokens `tokens` `word` `kw_if` `num` `real` `hex` `str` `sstr` `comment` `minus` `arrow` `lparen` `rparen` `tag` `question` `code` `patend` `bang` `bang_ws` `label` `lt` `newline` `indent` `gap` `eof` `err`)
  (lex_rule
    _
    (guards
      `@`
      (guard _ `beg` _ _)
      (guard _ `pre` `>` `0`))
    `indent`
    (counted `pre` `counted` `'.'`))
  (lex_rule
    _
    (guards
      `@`
      (guard `!` `beg` _ _)
      (guard _ `pre` `>` `1`))
    `gap`
    (set_action `pre` `0`))
  (lex_rule
    `'\\n'`
    _
    `newline`
    (set_action `beg` `1`))
  (lex_rule
    `"\\\\\\n"`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'"' ([^"\\\\\\n] | '\\\\' .)* '"'` _ `str`)
  (lex_rule `"'" ([^'\\n] | "''")* "'"` _ `sstr`)
  (lex_rule `'0x' [0-9a-fA-F]{1,4}` _ `hex`)
  (lex_rule
    `[0-9]+`
    (guards
      `@`
      (guard _ `mode` _ _))
    `num`)
  (lex_rule
    `[0-9]+ ('.' [0-9]+)? [eE] [+-]? [0-9]+`
    (guards
      `@`
      (guard `!` `mode` _ _))
    `real`)
  (lex_rule
    `[0-9]* '.' [0-9]+`
    (guards
      `@`
      (guard `!` `mode` _ _))
    `real`)
  (lex_rule `[0-9]+` _ `num`)
  (lex_rule `"if"` _ `kw_if`)
  (lex_rule `[a-z_][a-z0-9_]*` _ `word`)
  (lex_rule `[A-Z]+ ':' / '('` _ `label`)
  (lex_rule
    `'?' / [0-9]+ [A-Z]`
    _
    `question`
    (set_action `mode` `1`))
  (lex_rule `'?'` _ `question`)
  (lex_rule
    `[A-Z]`
    (guards
      `@`
      (guard _ `mode` _ _))
    `code`)
  (lex_rule
    `')'`
    (guards
      `@`
      (guard _ `mode` _ _))
    `patend`
    (lex_action `hold` _)
    (set_action `mode` `0`))
  (lex_rule `'<' [a-z]+ '>'` _ `tag`)
  (lex_rule
    `"<=>"`
    _
    `lt`
    (lex_action `rewind` `1`))
  (lex_rule `'<'` _ `lt`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule
    `'!'`
    (guards
      `@`
      (guard _ `pre` _ _))
    `bang_ws`)
  (lex_rule `'!'` _ `bang`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"lexer"`)
  (rule
    (start `top`)
    (alt
      _
      ((ref `toks`))
      (node
        `toks`
        (spread `1`))
      _))
  (rule
    (name `toks`)
    (alt
      _
      ((ref `toks`)
        (ref `tok`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `tok`))
      (list
        (pos `1`))
      _))
  (rule
    (name `tok`)
    (alt
      _
      ((tok `WORD`))
      (node
        `word`
        (pos `1`))
      _)
    (alt
      _
      ((tok `KW_IF`))
      (node
        `if`
        (pos `1`))
      _)
    (alt
      _
      ((tok `NUM`))
      (node
        `num`
        (pos `1`))
      _)
    (alt
      _
      ((tok `REAL`))
      (node
        `real`
        (pos `1`))
      _)
    (alt
      _
      ((tok `HEX`))
      (node
        `hex`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STR`))
      (node
        `str`
        (pos `1`))
      _)
    (alt
      _
      ((tok `SSTR`))
      (node
        `sstr`
        (pos `1`))
      _)
    (alt
      _
      ((tok `COMMENT`))
      (node
        `comment`
        (pos `1`))
      _)
    (alt
      _
      ((tok `MINUS`))
      (node
        `minus`
        (pos `1`))
      _)
    (alt
      _
      ((tok `ARROW`))
      (node
        `arrow`
        (pos `1`))
      _)
    (alt
      _
      ((tok `LPAREN`))
      (node
        `lparen`
        (pos `1`))
      _)
    (alt
      _
      ((tok `RPAREN`))
      (node
        `rparen`
        (pos `1`))
      _)
    (alt
      _
      ((tok `TAG`))
      (node
        `tag`
        (pos `1`))
      _)
    (alt
      _
      ((tok `QUESTION`))
      (node
        `question`
        (pos `1`))
      _)
    (alt
      _
      ((tok `CODE`))
      (node
        `code`
        (pos `1`))
      _)
    (alt
      _
      ((tok `PATEND`))
      (node
        `patend`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BANG`))
      (node
        `bang`
        (pos `1`))
      _)
    (alt
      _
      ((tok `BANG_WS`))
      (node
        `bang_ws`
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
      ((tok `LT`))
      (node
        `lt`
        (pos `1`))
      _)
    (alt
      _
      ((tok `NEWLINE`))
      (node
        `newline`
        (pos `1`))
      _)
    (alt
      _
      ((tok `INDENT`))
      (node
        `indent`
        (pos `1`))
      _)
    (alt
      _
      ((tok `GAP`))
      (node
        `gap`
        (pos `1`))
      _)
    (alt
      _
      ((tok `ERR`))
      (node
        `err`
        (pos `1`))
      _)))
