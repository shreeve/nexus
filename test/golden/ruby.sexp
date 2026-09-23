(grammar
  (section `lexer`)
  (state
    `state`
    (assign `paren` `0`)
    (assign `brack` `0`)
    (assign `brace` `0`))
  (tokens `tokens` `ident` `constant` `ivar` `cvar` `gvar` `integer` `float` `rational` `imaginary` `string_sq` `string_dq` `symbol` `label` `pct_w` `pct_i` `plus` `minus` `star` `slash` `percent` `power` `eq` `ne` `eqq` `cmp` `match_op` `nmatch` `lt` `gt` `le` `ge` `oror` `andand` `bang` `ampersand` `pipe` `caret` `tilde` `lshift` `rshift` `assign` `plus_eq` `minus_eq` `star_eq` `slash_eq` `percent_eq` `power_eq` `pipe_eq` `amp_eq` `caret_eq` `lshift_eq` `rshift_eq` `oror_eq` `andand_eq` `lparen` `rparen` `lbracket` `rbracket` `lbrace` `rbrace` `comma` `dot` `dotdot` `dotdotdot` `colon` `semicolon` `question` `fat_arrow` `arrow` `scope` `safe_nav` `dstr_beg` `str_content` `embexpr_beg` `embexpr_end` `dstr_end` `plus_u` `minus_u` `star_splat` `amp_block` `cmd_ident` `lbrace_block` `then_sep` `do_sep` `if_mod` `unless_mod` `while_mod` `until_mod` `rescue_mod` `do_block` `do_cond` `not_kw` `or_kw` `and_kw` `begin_kw` `if` `unless` `elsif` `else` `end` `while` `until` `for` `in` `case` `when` `then` `def` `class` `module` `rescue` `ensure` `return` `break` `next` `yield` `super` `defined` `alias` `undef` `retry` `redo` `self` `true` `false` `nil` `kw__file__` `kw__line__` `kw__encoding__` `newline` `comment` `eof` `err`)
  (lex_rule
    `[ \\t\\r]+`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule
    `"\\\\\\n"`
    _
    `skip`
    (lex_action `skip` _))
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `'"' ([^"\\\\] | '\\\\' .)* '"'` _ `string_dq`)
  (lex_rule `"'" ([^'\\\\] | '\\\\' .)* "'"` _ `string_sq`)
  (lex_rule `'0' [xX] [0-9a-fA-F] [0-9a-fA-F_]*` _ `integer`)
  (lex_rule `'0' [bB] [01] [01_]*` _ `integer`)
  (lex_rule `'0' [oO] [0-7] [0-7_]*` _ `integer`)
  (lex_rule `[0-9] [0-9_]* '.' [0-9] [0-9_]* 'ri'` _ `imaginary`)
  (lex_rule `[0-9] [0-9_]* '.' [0-9] [0-9_]* 'r'` _ `rational`)
  (lex_rule `[0-9] [0-9_]* '.' [0-9] [0-9_]* 'i'` _ `imaginary`)
  (lex_rule `[0-9] [0-9_]* '.' [0-9] [0-9_]* ([eE] [+-]? [0-9] [0-9_]*)?` _ `float`)
  (lex_rule `[0-9] [0-9_]* [eE] [+-]? [0-9] [0-9_]*` _ `float`)
  (lex_rule `[0-9] [0-9_]* 'ri'` _ `imaginary`)
  (lex_rule `[0-9] [0-9_]* 'r'` _ `rational`)
  (lex_rule `[0-9] [0-9_]* 'i'` _ `imaginary`)
  (lex_rule `[0-9] [0-9_]*` _ `integer`)
  (lex_rule `"==="` _ `eqq`)
  (lex_rule `"<=>"` _ `cmp`)
  (lex_rule `"..."` _ `dotdotdot`)
  (lex_rule `"**="` _ `power_eq`)
  (lex_rule `"<<="` _ `lshift_eq`)
  (lex_rule `">>="` _ `rshift_eq`)
  (lex_rule `"||="` _ `oror_eq`)
  (lex_rule `"&&="` _ `andand_eq`)
  (lex_rule `"**"` _ `power`)
  (lex_rule `"=~"` _ `match_op`)
  (lex_rule `"!~"` _ `nmatch`)
  (lex_rule `"=="` _ `eq`)
  (lex_rule `"!="` _ `ne`)
  (lex_rule `"<="` _ `le`)
  (lex_rule `">="` _ `ge`)
  (lex_rule `"||"` _ `oror`)
  (lex_rule `"&&"` _ `andand`)
  (lex_rule `"<<"` _ `lshift`)
  (lex_rule `">>"` _ `rshift`)
  (lex_rule `"+="` _ `plus_eq`)
  (lex_rule `"-="` _ `minus_eq`)
  (lex_rule `"*="` _ `star_eq`)
  (lex_rule `"/="` _ `slash_eq`)
  (lex_rule `"%="` _ `percent_eq`)
  (lex_rule `"|="` _ `pipe_eq`)
  (lex_rule `"&="` _ `amp_eq`)
  (lex_rule `"^="` _ `caret_eq`)
  (lex_rule `"=>"` _ `fat_arrow`)
  (lex_rule `"->"` _ `arrow`)
  (lex_rule `"::"` _ `scope`)
  (lex_rule `"&."` _ `safe_nav`)
  (lex_rule `".."` _ `dotdot`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'/'` _ `slash`)
  (lex_rule `'%'` _ `percent`)
  (lex_rule `'<'` _ `lt`)
  (lex_rule `'>'` _ `gt`)
  (lex_rule `'!'` _ `bang`)
  (lex_rule `'?'` _ `question`)
  (lex_rule `'|'` _ `pipe`)
  (lex_rule `'&'` _ `ampersand`)
  (lex_rule `'^'` _ `caret`)
  (lex_rule `'~'` _ `tilde`)
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
  (lex_rule
    `'['`
    _
    `lbracket`
    (step_action `brack` `++`))
  (lex_rule
    `']'`
    _
    `rbracket`
    (step_action `brack` `--`))
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `';'` _ `semicolon`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `"@@" [a-zA-Z_][a-zA-Z0-9_]*` _ `cvar`)
  (lex_rule `'$' [a-zA-Z_][a-zA-Z0-9_]*` _ `gvar`)
  (lex_rule `'$' [0-9]+` _ `gvar`)
  (lex_rule `'@' [a-zA-Z_][a-zA-Z0-9_]*` _ `ivar`)
  (lex_rule `[A-Z][a-zA-Z0-9_]*` _ `constant`)
  (lex_rule `[a-z_][a-zA-Z0-9_]* [?!]?` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"ruby"`)
  (manifest
    (conflict `shift` `stmt_list → sep stmt_list` _ `2` `# a newline after a separator is another separator, not the end of the list`)
    (conflict `shift` `stmt_list → sep` _ `2` `# a newline after a separator is another separator, not the end of the list`)
    (conflict `shift` `asgn → mlhs ASSIGN mrhs` _ `1` `# a comma after a multiple assignment's values adds another value`)
    (conflict `shift` `call → call "." IDENT` _ `6` `# a following [ or do binds to this method call`)
    (conflict `shift` `call → call "." IDENT call_args` _ `2` `# do binds to the innermost call with arguments`)
    (conflict `shift` `call → call "&." IDENT` _ `2` `# do binds to the innermost call`)
    (conflict `shift` `call → call "&." IDENT call_args` _ `2` `# do binds to the innermost call with arguments`)
    (conflict `shift` `call → IDENT call_args` _ `2` `# do binds to the innermost call with arguments`)
    (conflict `shift` `call → SUPER` _ `2` `# [ after super starts its argument array`)
    (conflict `shift` `call → YIELD` _ `2` `# [ after yield starts its argument array`)
    (conflict `shift` `arg → expr` _ `1` `# (expr) after a method name is a parenthesized expression`)
    (conflict `shift` `primary → IDENT` _ `4` `# do or [ after a bare name binds to that name as a method call`)
    (conflict `shift` `rescues → ε` _ `5` `# each rescue clause joins the begin block`)
    (conflict `shift` `infix(">" ">=" "<" "<=") → infix("|" "^") ">" infix("|" "^")` _ `1` `# | after a comparison operand continues the operand (| binds tighter)`)
    (conflict `shift` `infix(">" ">=" "<" "<=") → infix("|" "^") ">=" infix("|" "^")` _ `1` `# | after a comparison operand continues the operand (| binds tighter)`)
    (conflict `shift` `infix(">" ">=" "<" "<=") → infix("|" "^") "<" infix("|" "^")` _ `1` `# | after a comparison operand continues the operand (| binds tighter)`)
    (conflict `shift` `infix(">" ">=" "<" "<=") → infix("|" "^") "<=" infix("|" "^")` _ `1` `# | after a comparison operand continues the operand (| binds tighter)`)
    (conflict `shift` `infix(">" ">=" "<" "<=") → infix("|" "^")` _ `1` `# | after a comparison operand continues the operand (| binds tighter)`)
    (conflict `reduce` `lhs → IDENT` `primary → IDENT` `1` `# a name before a comma is an assignment target (multiple assignment)`)
    (conflict `reduce` `lhs → IVAR` `primary → IVAR` `1` `# an instance variable before a comma is an assignment target`)
    (conflict `reduce` `lhs → CVAR` `primary → CVAR` `1` `# a class variable before a comma is an assignment target`)
    (conflict `reduce` `lhs → GVAR` `primary → GVAR` `1` `# a global before a comma is an assignment target`)
    (conflict `reduce` `lhs → CONSTANT` `primary → CONSTANT` `1` `# a constant before a comma is an assignment target`)
    (conflict `reduce` `lhs → call "." IDENT` `call → call "." IDENT` `1` `# an attribute before a comma is an assignment target`)
    (conflict `reduce` `lhs → call "[" "]"` `call → call "[" "]"` `1` `# an index before a comma is an assignment target`)
    (conflict `reduce` `lhs → call "[" index_args "]"` `call → call "[" index_args "]"` `1` `# an index before a comma is an assignment target`)
    (conflict `reduce` `arg → "**" expr` `pair → "**" expr` `4` `# **expr in call arguments is a double splat argument`)
    (conflict `reduce` `cmd_arg → "**" expr` `pair → "**" expr` `16` `# **expr in command arguments is a double splat argument`))
  (as
    `ident`
    _
    (as_entry perm `keyword` _))
  (rule
    (start `program`)
    (alt
      _
      ((ref `stmts`))
      (node
        `program`
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
    (name `stmts`)
    (alt
      _
      ((ref `stmt_list`))
      (pos `1`)
      _)
    (alt
      _
      ()
      (node `stmts`)
      _))
  (rule
    (name `stmt_list`)
    (alt
      _
      ((ref `stmt_list`)
        (ref `sep`)
        (ref `stmt`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `stmt_list`)
        (ref `sep`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `sep`)
        (ref `stmt_list`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `stmt`))
      (node
        `stmts`
        (pos `1`))
      _)
    (alt
      _
      ((ref `sep`))
      (node `stmts`)
      _))
  (rule
    (name `sep`)
    (alt
      _
      ((tok `NEWLINE`))
      (list)
      _)
    (alt
      _
      ((tok `SEMICOLON`))
      (list)
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((ref `if_stmt`))
      _
      _)
    (alt
      _
      ((ref `unless_stmt`))
      _
      _)
    (alt
      _
      ((ref `while_stmt`))
      _
      _)
    (alt
      _
      ((ref `until_stmt`))
      _
      _)
    (alt
      _
      ((ref `for_stmt`))
      _
      _)
    (alt
      _
      ((ref `case_stmt`))
      _
      _)
    (alt
      _
      ((ref `def_stmt`))
      _
      _)
    (alt
      _
      ((ref `class_stmt`))
      _
      _)
    (alt
      _
      ((ref `module_stmt`))
      _
      _)
    (alt
      _
      ((ref `begin_stmt`))
      _
      _)
    (alt
      _
      ((ref `alias_stmt`))
      _
      _)
    (alt
      _
      ((ref `undef_stmt`))
      _
      _)
    (alt
      _
      ((ref `flow_stmt`))
      _
      _)
    (alt
      _
      ((ref `cmd_stmt`))
      _
      _)
    (alt
      _
      ((ref `mod_stmt`))
      _
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `mod_stmt`)
    (alt
      _
      ((ref `expr`)
        (tok `IF_MOD`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `1`)
        (null))
      _)
    (alt
      _
      ((ref `expr`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      (node
        `unless`
        (pos `3`)
        (pos `1`)
        (null))
      _)
    (alt
      _
      ((ref `expr`)
        (tok `WHILE_MOD`)
        (ref `expr`))
      (node
        `while`
        (pos `3`)
        (pos `1`))
      _)
    (alt
      _
      ((ref `expr`)
        (tok `UNTIL_MOD`)
        (ref `expr`))
      (node
        `until`
        (pos `3`)
        (pos `1`))
      _)
    (alt
      _
      ((ref `expr`)
        (tok `RESCUE_MOD`)
        (ref `expr`))
      (node
        `rescue`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `flow_stmt`)
        (tok `IF_MOD`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `1`)
        (null))
      _)
    (alt
      _
      ((ref `flow_stmt`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      (node
        `unless`
        (pos `3`)
        (pos `1`)
        (null))
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `kw_not`))
      _
      _))
  (rule
    (name `kw_not`)
    (alt
      _
      ((tok `NOT_KW`)
        (ref `kw_not`))
      (node
        `not`
        (pos `2`))
      _)
    (alt
      _
      ((ref `kw_or`))
      _
      _))
  (rule
    (name `kw_or`)
    (alt
      _
      ((ref `kw_or`)
        (tok `OR_KW`)
        (ref `kw_and`))
      (node
        `or`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `kw_and`))
      _
      _))
  (rule
    (name `kw_and`)
    (alt
      _
      ((ref `kw_and`)
        (tok `AND_KW`)
        (ref `asgn`))
      (node
        `and`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `asgn`))
      _
      _))
  (rule
    (name `asgn`)
    (alt
      _
      ((ref `mlhs`)
        (tok `ASSIGN`)
        (ref `mrhs`))
      (node
        `masgn`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `ASSIGN`)
        (ref `asgn`))
      (node
        `assign`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `PLUS_EQ`)
        (ref `asgn`))
      (node
        `+=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `MINUS_EQ`)
        (ref `asgn`))
      (node
        `-=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `STAR_EQ`)
        (ref `asgn`))
      (node
        `*=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `SLASH_EQ`)
        (ref `asgn`))
      (node
        `/=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `PERCENT_EQ`)
        (ref `asgn`))
      (node
        `%=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `POWER_EQ`)
        (ref `asgn`))
      (node
        `**=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `PIPE_EQ`)
        (ref `asgn`))
      (node
        `|=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `AMP_EQ`)
        (ref `asgn`))
      (node
        `&=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `CARET_EQ`)
        (ref `asgn`))
      (node
        `^=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `LSHIFT_EQ`)
        (ref `asgn`))
      (node
        `<<=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `RSHIFT_EQ`)
        (ref `asgn`))
      (node
        `>>=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `OROR_EQ`)
        (ref `asgn`))
      (node
        `||=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `lhs`)
        (tok `ANDAND_EQ`)
        (ref `asgn`))
      (node
        `&&=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `ternary`))
      _
      _))
  (rule
    (name `mlhs`)
    (alt
      _
      ((ref `lhs`)
        (lit `","`)
        (ref `lhs`))
      (node
        `mlhs`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `mlhs`)
        (lit `","`)
        (ref `lhs`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `mlhs`)
        (lit `","`)
        (ref `splat_lhs`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `splat_lhs`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `lhs`))
      (node
        `splat`
        (pos `2`))
      _))
  (rule
    (name `mrhs`)
    (alt
      _
      ((ref `ternary`)
        (lit `","`)
        (ref `ternary`))
      (node
        `mrhs`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `mrhs`)
        (lit `","`)
        (ref `ternary`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `mrhs`)
        (lit `","`)
        (ref `splat_val`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `splat_val`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `ternary`))
      (node
        `splat`
        (pos `2`))
      _))
  (rule
    (name `lhs`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `IVAR`))
      _
      _)
    (alt
      _
      ((tok `CVAR`))
      _
      _)
    (alt
      _
      ((tok `GVAR`))
      _
      _)
    (alt
      _
      ((tok `CONSTANT`))
      _
      _)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (tok `IDENT`))
      (node
        `attrasgn`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (group
          opt
          ((ref `index_args`)))
        (lit `"]"`))
      (node
        `indexasgn`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `ternary`)
    (alt
      _
      ((at_ref `infix`)
        (tok `QUESTION`)
        (ref `ternary`)
        (tok `COLON`)
        (ref `ternary`))
      (node
        `if`
        (pos `1`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((at_ref `infix`))
      _
      _))
  (infix
    `unary`
    (level
      (infix_op `".."` `none`)
      (infix_op `"..."` `none`))
    (level
      (infix_op `"||"` `left`))
    (level
      (infix_op `"&&"` `left`))
    (level
      (infix_op `"=="` `none`)
      (infix_op `"!="` `none`)
      (infix_op `"==="` `none`)
      (infix_op `"<=>"` `none`)
      (infix_op `"=~"` `none`)
      (infix_op `"!~"` `none`))
    (level
      (infix_op `">"` `none`)
      (infix_op `">="` `none`)
      (infix_op `"<"` `none`)
      (infix_op `"<="` `none`))
    (level
      (infix_op `"|"` `left`)
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
      (infix_op `"%"` `left`)))
  (rule
    (name `unary`)
    (alt
      _
      ((tok `MINUS_U`)
        (ref `unary`))
      (node
        `u-`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PLUS_U`)
        (ref `unary`))
      (node
        `u+`
        (pos `2`))
      _)
    (alt
      _
      ((tok `BANG`)
        (ref `unary`))
      (node
        `!`
        (pos `2`))
      _)
    (alt
      _
      ((tok `TILDE`)
        (ref `unary`))
      (node
        `~`
        (pos `2`))
      _)
    (alt
      _
      ((tok `DEFINED`)
        (ref `unary`))
      (node
        `defined`
        (pos `2`))
      _)
    (alt
      _
      ((ref `power`))
      _
      _))
  (rule
    (name `power`)
    (alt
      _
      ((ref `call`)
        (tok `POWER`)
        (ref `unary`))
      (node
        `**`
        (pos `1`)
        (pos `3`))
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
        (ref `methodname`)
        (group
          opt
          ((ref `call_args`)))
        (group
          opt
          ((ref `block`))))
      (node
        `send`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"&."`)
        (ref `methodname`)
        (group
          opt
          ((ref `call_args`)))
        (group
          opt
          ((ref `block`))))
      (node
        `csend`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (group
          opt
          ((ref `index_args`)))
        (lit `"]"`))
      (node
        `index`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"::"`)
        (tok `CONSTANT`))
      (node
        `scope`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"::"`)
        (tok `CONSTANT`))
      (node
        `scope`
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (ref `call_args`)
        (group
          opt
          ((ref `block`))))
      (node
        `send`
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `IDENT`)
        (ref `block`))
      (node
        `send`
        (null)
        (pos `1`)
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((tok `SUPER`)
        (group
          opt
          ((ref `call_args`))))
      (node
        `super`
        (pos `2`))
      _)
    (alt
      _
      ((tok `YIELD`)
        (group
          opt
          ((ref `call_args`))))
      (node
        `yield`
        (pos `2`))
      _)
    (alt
      _
      ((ref `primary`))
      _
      _))
  (rule
    (name `index_args`)
    (alt
      _
      ((list_req
          `L`
          (plain `arg`)))
      (node
        `args`
        (spread `1`))
      _))
  (rule
    (name `methodname`)
    (alt
      _
      ((tok `IDENT`))
      _
      _))
  (rule
    (name `call_args`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      (node `args`)
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `arg`))
        (lit `")"`))
      (node
        `args`
        (spread `2`))
      _))
  (rule
    (name `arg`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      (node
        `splat`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      (node
        `kwsplat`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      (node
        `block_pass`
        (pos `2`))
      _)
    (alt
      _
      ((ref `pair`))
      _
      _))
  (rule
    (name `cmd_stmt`)
    (alt
      _
      ((tok `CMD_IDENT`)
        (ref `cmd_args`)
        (group
          opt
          ((ref `block`))))
      (node
        `send`
        (null)
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (tok `IDENT`)
        (ref `cmd_args`)
        (group
          opt
          ((ref `block`))))
      (node
        `send`
        (pos `1`)
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `cmd_args`)
    (alt
      _
      ((list_req
          `L`
          (plain `cmd_arg`)))
      (node
        `args`
        (spread `1`))
      _))
  (rule
    (name `cmd_arg`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      (node
        `splat`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      (node
        `kwsplat`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      (node
        `block_pass`
        (pos `2`))
      _)
    (alt
      _
      ((ref `pair`))
      _
      _))
  (rule
    (name `block`)
    (alt
      _
      ((tok `DO_BLOCK`)
        (group
          opt
          ((ref `block_params`)))
        (ref `stmts`)
        (tok `END`))
      (node
        `block`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `LBRACE_BLOCK`)
        (group
          opt
          ((ref `block_params`)))
        (ref `stmts`)
        (lit `"}"`))
      (node
        `block`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `block_params`)
    (alt
      _
      ((lit `"|"`)
        (list_req
          `L`
          (plain `param`))
        (lit `"|"`))
      (node
        `params`
        (spread `2`))
      _)
    (alt
      _
      ((lit `"|"`)
        (lit `"|"`))
      (node `params`)
      _))
  (rule
    (name `primary`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `CONSTANT`))
      _
      _)
    (alt
      _
      ((tok `IVAR`))
      _
      _)
    (alt
      _
      ((tok `CVAR`))
      _
      _)
    (alt
      _
      ((tok `GVAR`))
      _
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `FLOAT`))
      _
      _)
    (alt
      _
      ((tok `RATIONAL`))
      _
      _)
    (alt
      _
      ((tok `IMAGINARY`))
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
      ((tok `PCT_W`))
      _
      _)
    (alt
      _
      ((tok `PCT_I`))
      _
      _)
    (alt
      _
      ((ref `dstring`))
      _
      _)
    (alt
      _
      ((tok `SYMBOL`))
      _
      _)
    (alt
      _
      ((ref `literal_kw`))
      _
      _)
    (alt
      _
      ((ref `lambda`))
      _
      _)
    (alt
      _
      ((ref `array`))
      _
      _)
    (alt
      _
      ((ref `hash`))
      _
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `literal_kw`)
    (alt
      _
      ((tok `TRUE`))
      (node `true`)
      _)
    (alt
      _
      ((tok `FALSE`))
      (node `false`)
      _)
    (alt
      _
      ((tok `NIL`))
      (list
        (null))
      _)
    (alt
      _
      ((tok `SELF`))
      (node `self`)
      _)
    (alt
      _
      ((tok `KW__FILE__`))
      (node `__FILE__`)
      _)
    (alt
      _
      ((tok `KW__LINE__`))
      (node `__LINE__`)
      _)
    (alt
      _
      ((tok `KW__ENCODING__`))
      (node `__ENCODING__`)
      _))
  (rule
    (name `lambda`)
    (alt
      _
      ((tok `ARROW`)
        (group
          opt
          ((ref `params`)))
        (ref `block`))
      (node
        `lambda`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `dstring`)
    (alt
      _
      ((tok `DSTR_BEG`)
        (quantified
          (ref `dstr_part`)
          (one_plus))
        (tok `DSTR_END`))
      (node
        `dstr`
        (spread `2`))
      _)
    (alt
      _
      ((tok `DSTR_BEG`)
        (tok `DSTR_END`))
      (node `dstr`)
      _))
  (rule
    (name `dstr_part`)
    (alt
      _
      ((tok `STR_CONTENT`))
      _
      _)
    (alt
      _
      ((tok `EMBEXPR_BEG`)
        (ref `stmts`)
        (tok `EMBEXPR_END`))
      (node
        `evstr`
        (pos `2`))
      _))
  (rule
    (name `array`)
    (alt
      _
      ((lit `"["`)
        (group
          opt
          ((list_req
              `L`
              (plain `elem`))))
        (lit `"]"`))
      (node
        `array`
        (spread `2`))
      _))
  (rule
    (name `elem`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      (node
        `splat`
        (pos `2`))
      _))
  (rule
    (name `hash`)
    (alt
      _
      ((tok `LBRACE`)
        (group
          opt
          ((list_req
              `L`
              (plain `pair`))))
        (lit `"}"`))
      (node
        `hash`
        (spread `2`))
      _))
  (rule
    (name `pair`)
    (alt
      _
      ((tok `LABEL`)
        (ref `expr`))
      (node
        `pair`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `"=>"`)
        (ref `expr`))
      (node
        `pair`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      (node
        `kwsplat`
        (pos `2`))
      _))
  (rule
    (name `if_stmt`)
    (alt
      _
      ((tok `IF`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `else_clause`)
        (tok `END`))
      (node
        `if`
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `else_clause`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((tok `ELSE`)
        (ref `stmts`))
      (pos `2`)
      _)
    (alt
      _
      ((tok `ELSIF`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `else_clause`))
      (node
        `if`
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `then_sep`)
    (alt
      _
      ((tok `THEN_SEP`))
      (list)
      _))
  (rule
    (name `unless_stmt`)
    (alt
      _
      ((tok `UNLESS`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `opt_else`)
        (tok `END`))
      (node
        `unless`
        (pos `2`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `opt_else`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((tok `ELSE`)
        (ref `stmts`))
      (pos `2`)
      _))
  (rule
    (name `while_stmt`)
    (alt
      _
      ((tok `WHILE`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      (node
        `while`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `until_stmt`)
    (alt
      _
      ((tok `UNTIL`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      (node
        `until`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `do_sep`)
    (alt
      _
      ((tok `DO_SEP`))
      (list)
      _))
  (rule
    (name `for_stmt`)
    (alt
      _
      ((tok `FOR`)
        (tok `IDENT`)
        (tok `IN`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      (node
        `for`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _))
  (rule
    (name `case_stmt`)
    (alt
      _
      ((tok `CASE`)
        (ref `expr`)
        (ref `then_sep`)
        (quantified
          (ref `when_clause`)
          (one_plus))
        (ref `opt_else`)
        (tok `END`))
      (node
        `case`
        (pos `2`)
        (spread `4`)
        (pos `5`))
      _)
    (alt
      _
      ((tok `CASE`)
        (ref `then_sep`)
        (quantified
          (ref `when_clause`)
          (one_plus))
        (ref `opt_else`)
        (tok `END`))
      (node
        `case`
        (null)
        (spread `3`)
        (pos `4`))
      _))
  (rule
    (name `when_clause`)
    (alt
      _
      ((tok `WHEN`)
        (list_req
          `L`
          (plain `arg`))
        (ref `then_sep`)
        (ref `stmts`))
      (node
        `when`
        (pos `4`)
        (spread `2`))
      _))
  (rule
    (name `begin_stmt`)
    (alt
      _
      ((tok `BEGIN_KW`)
        (ref `sep`)
        (ref `stmts`)
        (ref `rescues`)
        (ref `ensure_cl`)
        (tok `END`))
      (node
        `begin`
        (pos `3`)
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `rescues`)
    (alt
      _
      ((ref `rescue_cl`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `rescues`)
        (ref `rescue_cl`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `rescue_cl`)
    (alt
      _
      ((tok `RESCUE`)
        (ref `then_sep`)
        (ref `stmts`))
      (node
        `rescue`
        (null)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((tok `RESCUE`)
        (lit `"=>"`)
        (tok `IDENT`)
        (ref `then_sep`)
        (ref `stmts`))
      (node
        `rescue`
        (null)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((tok `RESCUE`)
        (list_req
          `L`
          (plain `const_path`))
        (ref `then_sep`)
        (ref `stmts`))
      (node
        `rescue`
        (pos `2`)
        (null)
        (pos `4`))
      _)
    (alt
      _
      ((tok `RESCUE`)
        (list_req
          `L`
          (plain `const_path`))
        (lit `"=>"`)
        (tok `IDENT`)
        (ref `then_sep`)
        (ref `stmts`))
      (node
        `rescue`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _))
  (rule
    (name `ensure_cl`)
    (alt
      _
      ((tok `ENSURE`)
        (ref `sep`)
        (ref `stmts`))
      (node
        `ensure`
        (pos `3`))
      _)
    (alt
      _
      ()
      (list)
      _))
  (rule
    (name `def_stmt`)
    (alt
      _
      ((tok `DEF`)
        (ref `methodname`)
        (group
          opt
          ((ref `params`)))
        (ref `sep`)
        (ref `stmts`)
        (ref `rescues`)
        (ref `ensure_cl`)
        (tok `END`))
      (node
        `def`
        (pos `2`)
        (pos `3`)
        (pos `5`)
        (pos `6`)
        (pos `7`))
      _)
    (alt
      _
      ((tok `DEF`)
        (ref `primary`)
        (lit `"."`)
        (ref `methodname`)
        (group
          opt
          ((ref `params`)))
        (ref `sep`)
        (ref `stmts`)
        (ref `rescues`)
        (ref `ensure_cl`)
        (tok `END`))
      (node
        `defs`
        (pos `2`)
        (pos `4`)
        (pos `5`)
        (pos `7`)
        (pos `8`)
        (pos `9`))
      _))
  (rule
    (name `params`)
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
          (plain `param`))
        (lit `")"`))
      (node
        `params`
        (spread `2`))
      _))
  (rule
    (name `param`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `IDENT`)
        (lit `"="`)
        (ref `expr`))
      (node
        `optarg`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((tok `LABEL`))
      (node
        `kwarg`
        (pos `1`))
      _)
    (alt
      _
      ((tok `LABEL`)
        (ref `expr`))
      (node
        `kwoptarg`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (tok `IDENT`))
      (node
        `restarg`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"**"`)
        (tok `IDENT`))
      (node
        `kwrestarg`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP_BLOCK`)
        (tok `IDENT`))
      (node
        `blockarg`
        (pos `2`))
      _))
  (rule
    (name `class_stmt`)
    (alt
      _
      ((tok `CLASS`)
        (ref `const_path`)
        (group
          opt
          ((ref `superclass`)))
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      (node
        `class`
        (pos `2`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((tok `CLASS`)
        (lit `"<<"`)
        (ref `expr`)
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      (node
        `sclass`
        (pos `3`)
        (pos `5`))
      _))
  (rule
    (name `superclass`)
    (alt
      _
      ((lit `"<"`)
        (ref `const_path`))
      (pos `2`)
      _))
  (rule
    (name `module_stmt`)
    (alt
      _
      ((tok `MODULE`)
        (ref `const_path`)
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      (node
        `module`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `const_path`)
    (alt
      _
      ((tok `CONSTANT`))
      _
      _)
    (alt
      _
      ((ref `const_path`)
        (lit `"::"`)
        (tok `CONSTANT`))
      (node
        `scope`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `alias_stmt`)
    (alt
      _
      ((tok `ALIAS`)
        (ref `alias_name`)
        (ref `alias_name`))
      (node
        `alias`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `undef_stmt`)
    (alt
      _
      ((tok `UNDEF`)
        (list_req
          `L`
          (plain `alias_name`)))
      (node
        `undef`
        (spread `2`))
      _))
  (rule
    (name `alias_name`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `SYMBOL`))
      _
      _))
  (rule
    (name `flow_stmt`)
    (alt
      _
      ((tok `RETURN`)
        (ref `cmd_args`))
      (node
        `return`
        (pos `2`))
      _)
    (alt
      _
      ((tok `RETURN`))
      (node `return`)
      _)
    (alt
      _
      ((tok `BREAK`)
        (ref `cmd_args`))
      (node
        `break`
        (pos `2`))
      _)
    (alt
      _
      ((tok `BREAK`))
      (node `break`)
      _)
    (alt
      _
      ((tok `NEXT`)
        (ref `cmd_args`))
      (node
        `next`
        (pos `2`))
      _)
    (alt
      _
      ((tok `NEXT`))
      (node `next`)
      _)
    (alt
      _
      ((tok `YIELD`)
        (ref `cmd_args`))
      (node
        `yield`
        (pos `2`))
      _)
    (alt
      _
      ((tok `SUPER`)
        (ref `cmd_args`))
      (node
        `super`
        (pos `2`))
      _)
    (alt
      _
      ((tok `RETRY`))
      (node `retry`)
      _)
    (alt
      _
      ((tok `REDO`))
      (node `redo`)
      _)))
