(grammar
  (lang `"ruby"`)
  (conflicts `66`)
  (as
    `ident`
    _
    (as_entry perm `keyword`))
  (rule
    (start `program`)
    (alt
      _
      ((ref `stmts`))
      (node
        `program`
        (spread `1`))))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)))
  (rule
    (name `stmts`)
    (alt
      _
      ((ref `stmt_list`))
      (pos `1`))
    (alt
      _
      ()
      (node `stmts`)))
  (rule
    (name `stmt_list`)
    (alt
      _
      ((ref `stmt_list`)
        (ref `sep`)
        (ref `stmt`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `stmt_list`)
        (ref `sep`))
      (pos `1`))
    (alt
      _
      ((ref `sep`)
        (ref `stmt_list`))
      (pos `2`))
    (alt
      _
      ((ref `stmt`))
      (node
        `stmts`
        (pos `1`)))
    (alt
      _
      ((ref `sep`))
      (node `stmts`)))
  (rule
    (name `sep`)
    (alt
      _
      ((tok `NEWLINE`))
      (list))
    (alt
      _
      ((tok `SEMICOLON`))
      (list)))
  (rule
    (name `stmt`)
    (alt
      _
      ((ref `if_stmt`)))
    (alt
      _
      ((ref `unless_stmt`)))
    (alt
      _
      ((ref `while_stmt`)))
    (alt
      _
      ((ref `until_stmt`)))
    (alt
      _
      ((ref `for_stmt`)))
    (alt
      _
      ((ref `case_stmt`)))
    (alt
      _
      ((ref `def_stmt`)))
    (alt
      _
      ((ref `class_stmt`)))
    (alt
      _
      ((ref `module_stmt`)))
    (alt
      _
      ((ref `begin_stmt`)))
    (alt
      _
      ((ref `alias_stmt`)))
    (alt
      _
      ((ref `undef_stmt`)))
    (alt
      _
      ((ref `flow_stmt`)))
    (alt
      _
      ((ref `cmd_stmt`)))
    (alt
      _
      ((ref `mod_stmt`)))
    (alt
      _
      ((ref `expr`))))
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
        (null)))
    (alt
      _
      ((ref `expr`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      (node
        `unless`
        (pos `3`)
        (pos `1`)
        (null)))
    (alt
      _
      ((ref `expr`)
        (tok `WHILE_MOD`)
        (ref `expr`))
      (node
        `while`
        (pos `3`)
        (pos `1`)))
    (alt
      _
      ((ref `expr`)
        (tok `UNTIL_MOD`)
        (ref `expr`))
      (node
        `until`
        (pos `3`)
        (pos `1`)))
    (alt
      _
      ((ref `expr`)
        (tok `RESCUE_MOD`)
        (ref `expr`))
      (node
        `rescue`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `flow_stmt`)
        (tok `IF_MOD`)
        (ref `expr`))
      (node
        `if`
        (pos `3`)
        (pos `1`)
        (null)))
    (alt
      _
      ((ref `flow_stmt`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      (node
        `unless`
        (pos `3`)
        (pos `1`)
        (null))))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `kw_not`))))
  (rule
    (name `kw_not`)
    (alt
      _
      ((tok `NOT_KW`)
        (ref `kw_not`))
      (node
        `not`
        (pos `2`)))
    (alt
      _
      ((ref `kw_or`))))
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
        (pos `3`)))
    (alt
      _
      ((ref `kw_and`))))
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
        (pos `3`)))
    (alt
      _
      ((ref `asgn`))))
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
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `ASSIGN`)
        (ref `asgn`))
      (node
        `assign`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `PLUS_EQ`)
        (ref `asgn`))
      (node
        `+=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `MINUS_EQ`)
        (ref `asgn`))
      (node
        `-=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `STAR_EQ`)
        (ref `asgn`))
      (node
        `*=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `SLASH_EQ`)
        (ref `asgn`))
      (node
        `/=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `PERCENT_EQ`)
        (ref `asgn`))
      (node
        `%=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `POWER_EQ`)
        (ref `asgn`))
      (node
        `**=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `PIPE_EQ`)
        (ref `asgn`))
      (node
        `|=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `AMP_EQ`)
        (ref `asgn`))
      (node
        `&=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `CARET_EQ`)
        (ref `asgn`))
      (node
        `^=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `LSHIFT_EQ`)
        (ref `asgn`))
      (node
        `<<=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `RSHIFT_EQ`)
        (ref `asgn`))
      (node
        `>>=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `OROR_EQ`)
        (ref `asgn`))
      (node
        `||=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `lhs`)
        (tok `ANDAND_EQ`)
        (ref `asgn`))
      (node
        `&&=`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `ternary`))))
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
        (pos `3`)))
    (alt
      _
      ((ref `mlhs`)
        (lit `","`)
        (ref `lhs`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `mlhs`)
        (lit `","`)
        (ref `splat_lhs`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `splat_lhs`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `lhs`))
      (node
        `splat`
        (pos `2`))))
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
        (pos `3`)))
    (alt
      _
      ((ref `mrhs`)
        (lit `","`)
        (ref `ternary`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `mrhs`)
        (lit `","`)
        (ref `splat_val`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `splat_val`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `ternary`))
      (node
        `splat`
        (pos `2`))))
  (rule
    (name `lhs`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `IVAR`)))
    (alt
      _
      ((tok `CVAR`)))
    (alt
      _
      ((tok `GVAR`)))
    (alt
      _
      ((tok `CONSTANT`)))
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (tok `IDENT`))
      (node
        `attrasgn`
        (pos `1`)
        (pos `3`)))
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
        (pos `3`))))
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
        (pos `5`)))
    (alt
      _
      ((at_ref `infix`))))
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
        (pos `2`)))
    (alt
      _
      ((tok `PLUS_U`)
        (ref `unary`))
      (node
        `u+`
        (pos `2`)))
    (alt
      _
      ((tok `BANG`)
        (ref `unary`))
      (node
        `!`
        (pos `2`)))
    (alt
      _
      ((tok `TILDE`)
        (ref `unary`))
      (node
        `~`
        (pos `2`)))
    (alt
      _
      ((tok `DEFINED`)
        (ref `unary`))
      (node
        `defined`
        (pos `2`)))
    (alt
      _
      ((ref `power`))))
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
        (pos `3`)))
    (alt
      _
      ((ref `call`))))
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
        (pos `5`)))
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
        (pos `5`)))
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
        (pos `3`)))
    (alt
      _
      ((ref `call`)
        (lit `"::"`)
        (tok `CONSTANT`))
      (node
        `scope`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((lit `"::"`)
        (tok `CONSTANT`))
      (node
        `scope`
        (null)
        (pos `2`)))
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
        (pos `3`)))
    (alt
      _
      ((tok `IDENT`)
        (ref `block`))
      (node
        `send`
        (null)
        (pos `1`)
        (null)
        (pos `2`)))
    (alt
      _
      ((tok `SUPER`)
        (group
          opt
          ((ref `call_args`))))
      (node
        `super`
        (pos `2`)))
    (alt
      _
      ((tok `YIELD`)
        (group
          opt
          ((ref `call_args`))))
      (node
        `yield`
        (pos `2`)))
    (alt
      _
      ((ref `primary`))))
  (rule
    (name `index_args`)
    (alt
      _
      ((list_req
          `L`
          (plain `arg`)))
      (node
        `args`
        (spread `1`))))
  (rule
    (name `methodname`)
    (alt
      _
      ((tok `IDENT`))))
  (rule
    (name `call_args`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      (node `args`))
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `arg`))
        (lit `")"`))
      (node
        `args`
        (spread `2`))))
  (rule
    (name `arg`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      (node
        `splat`
        (pos `2`)))
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      (node
        `kwsplat`
        (pos `2`)))
    (alt
      _
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      (node
        `block_pass`
        (pos `2`)))
    (alt
      _
      ((ref `pair`))))
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
        (pos `3`)))
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
        (pos `5`))))
  (rule
    (name `cmd_args`)
    (alt
      _
      ((list_req
          `L`
          (plain `cmd_arg`)))
      (node
        `args`
        (spread `1`))))
  (rule
    (name `cmd_arg`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      (node
        `splat`
        (pos `2`)))
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      (node
        `kwsplat`
        (pos `2`)))
    (alt
      _
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      (node
        `block_pass`
        (pos `2`)))
    (alt
      _
      ((ref `pair`))))
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
        (pos `3`)))
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
        (pos `3`))))
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
        (spread `2`)))
    (alt
      _
      ((lit `"|"`)
        (lit `"|"`))
      (node `params`)))
  (rule
    (name `primary`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `CONSTANT`)))
    (alt
      _
      ((tok `IVAR`)))
    (alt
      _
      ((tok `CVAR`)))
    (alt
      _
      ((tok `GVAR`)))
    (alt
      _
      ((tok `INTEGER`)))
    (alt
      _
      ((tok `FLOAT`)))
    (alt
      _
      ((tok `RATIONAL`)))
    (alt
      _
      ((tok `IMAGINARY`)))
    (alt
      _
      ((tok `STRING_SQ`)))
    (alt
      _
      ((tok `STRING_DQ`)))
    (alt
      _
      ((tok `PCT_W`)))
    (alt
      _
      ((tok `PCT_I`)))
    (alt
      _
      ((ref `dstring`)))
    (alt
      _
      ((tok `SYMBOL`)))
    (alt
      _
      ((ref `literal_kw`)))
    (alt
      _
      ((ref `lambda`)))
    (alt
      _
      ((ref `array`)))
    (alt
      _
      ((ref `hash`)))
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)))
  (rule
    (name `literal_kw`)
    (alt
      _
      ((tok `TRUE`))
      (node `true`))
    (alt
      _
      ((tok `FALSE`))
      (node `false`))
    (alt
      _
      ((tok `NIL`))
      (list
        (null)))
    (alt
      _
      ((tok `SELF`))
      (node `self`))
    (alt
      _
      ((tok `KW__FILE__`))
      (node `__FILE__`))
    (alt
      _
      ((tok `KW__LINE__`))
      (node `__LINE__`))
    (alt
      _
      ((tok `KW__ENCODING__`))
      (node `__ENCODING__`)))
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
        (pos `3`))))
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
        (spread `2`)))
    (alt
      _
      ((tok `DSTR_BEG`)
        (tok `DSTR_END`))
      (node `dstr`)))
  (rule
    (name `dstr_part`)
    (alt
      _
      ((tok `STR_CONTENT`)))
    (alt
      _
      ((tok `EMBEXPR_BEG`)
        (ref `stmts`)
        (tok `EMBEXPR_END`))
      (node
        `evstr`
        (pos `2`))))
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
        (spread `2`))))
  (rule
    (name `elem`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      (node
        `splat`
        (pos `2`))))
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
        (spread `2`))))
  (rule
    (name `pair`)
    (alt
      _
      ((tok `LABEL`)
        (ref `expr`))
      (node
        `pair`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((ref `expr`)
        (lit `"=>"`)
        (ref `expr`))
      (node
        `pair`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      (node
        `kwsplat`
        (pos `2`))))
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
        (pos `5`))))
  (rule
    (name `else_clause`)
    (alt
      _
      ()
      (list))
    (alt
      _
      ((tok `ELSE`)
        (ref `stmts`))
      (pos `2`))
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
        (pos `5`))))
  (rule
    (name `then_sep`)
    (alt
      _
      ((tok `THEN_SEP`))
      (list)))
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
        (pos `5`))))
  (rule
    (name `opt_else`)
    (alt
      _
      ()
      (list))
    (alt
      _
      ((tok `ELSE`)
        (ref `stmts`))
      (pos `2`)))
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
        (pos `4`))))
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
        (pos `4`))))
  (rule
    (name `do_sep`)
    (alt
      _
      ((tok `DO_SEP`))
      (list)))
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
        (pos `6`))))
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
        (pos `5`)))
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
        (pos `4`))))
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
        (spread `2`)
        (pos `4`))))
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
        (pos `5`))))
  (rule
    (name `rescues`)
    (alt
      _
      ((ref `rescue_cl`))
      (pos `1`))
    (alt
      _
      ((ref `rescues`)
        (ref `rescue_cl`))
      (list
        (spread `1`)
        (pos `2`)))
    (alt
      _
      ()
      (list)))
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
        (pos `3`)))
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
        (pos `5`)))
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
        (pos `4`)))
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
        (pos `6`))))
  (rule
    (name `ensure_cl`)
    (alt
      _
      ((tok `ENSURE`)
        (ref `sep`)
        (ref `stmts`))
      (node
        `ensure`
        (pos `3`)))
    (alt
      _
      ()
      (list)))
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
        (pos `7`)))
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
        (pos `9`))))
  (rule
    (name `params`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      (node `params`))
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `param`))
        (lit `")"`))
      (node
        `params`
        (spread `2`))))
  (rule
    (name `param`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `IDENT`)
        (lit `"="`)
        (ref `expr`))
      (node
        `optarg`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((tok `LABEL`))
      (node
        `kwarg`
        (pos `1`)))
    (alt
      _
      ((tok `LABEL`)
        (ref `expr`))
      (node
        `kwoptarg`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (tok `IDENT`))
      (node
        `restarg`
        (pos `2`)))
    (alt
      _
      ((lit `"**"`)
        (tok `IDENT`))
      (node
        `kwrestarg`
        (pos `2`)))
    (alt
      _
      ((tok `AMP_BLOCK`)
        (tok `IDENT`))
      (node
        `blockarg`
        (pos `2`))))
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
        (pos `5`)))
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
        (pos `5`))))
  (rule
    (name `superclass`)
    (alt
      _
      ((lit `"<"`)
        (ref `const_path`))
      (pos `2`)))
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
        (pos `4`))))
  (rule
    (name `const_path`)
    (alt
      _
      ((tok `CONSTANT`)))
    (alt
      _
      ((ref `const_path`)
        (lit `"::"`)
        (tok `CONSTANT`))
      (node
        `scope`
        (pos `1`)
        (pos `3`))))
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
        (pos `3`))))
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
        (spread `2`))))
  (rule
    (name `alias_name`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `SYMBOL`))))
  (rule
    (name `flow_stmt`)
    (alt
      _
      ((tok `RETURN`)
        (ref `cmd_args`))
      (node
        `return`
        (pos `2`)))
    (alt
      _
      ((tok `RETURN`))
      (node `return`))
    (alt
      _
      ((tok `BREAK`)
        (ref `cmd_args`))
      (node
        `break`
        (pos `2`)))
    (alt
      _
      ((tok `BREAK`))
      (node `break`))
    (alt
      _
      ((tok `NEXT`)
        (ref `cmd_args`))
      (node
        `next`
        (pos `2`)))
    (alt
      _
      ((tok `NEXT`))
      (node `next`))
    (alt
      _
      ((tok `YIELD`)
        (ref `cmd_args`))
      (node
        `yield`
        (pos `2`)))
    (alt
      _
      ((tok `SUPER`)
        (ref `cmd_args`))
      (node
        `super`
        (pos `2`)))
    (alt
      _
      ((tok `RETRY`))
      (node `retry`))
    (alt
      _
      ((tok `REDO`))
      (node `redo`))))
