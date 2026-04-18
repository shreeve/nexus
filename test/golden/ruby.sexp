(grammar
  (lang `"ruby"`)
  (conflicts `54`)
  (as
    `ident`
    (as_perm `keyword`))
  (rule
    (start `program`)
    (alt
      ((ref `stmts`))
      `(program ...1)`))
  (rule
    (start `expr`)
    (alt
      ((ref `expr`))
      `1`))
  (rule
    (name `stmts`)
    (alt
      ((ref `stmt_list`))
      `1`)
    (alt () `(stmts)`))
  (rule
    (name `stmt_list`)
    (alt
      ((ref `stmt_list`)
        (ref `sep`)
        (ref `stmt`))
      `(...1 3)`)
    (alt
      ((ref `stmt_list`)
        (ref `sep`))
      `1`)
    (alt
      ((ref `sep`)
        (ref `stmt_list`))
      `2`)
    (alt
      ((ref `stmt`))
      `(stmts 1)`)
    (alt
      ((ref `sep`))
      `(stmts)`))
  (rule
    (name `sep`)
    (alt
      ((tok `NEWLINE`))
      `()`)
    (alt
      ((tok `SEMICOLON`))
      `()`))
  (rule
    (name `stmt`)
    (alt
      ((ref `if_stmt`)))
    (alt
      ((ref `unless_stmt`)))
    (alt
      ((ref `while_stmt`)))
    (alt
      ((ref `until_stmt`)))
    (alt
      ((ref `for_stmt`)))
    (alt
      ((ref `case_stmt`)))
    (alt
      ((ref `def_stmt`)))
    (alt
      ((ref `class_stmt`)))
    (alt
      ((ref `module_stmt`)))
    (alt
      ((ref `begin_stmt`)))
    (alt
      ((ref `alias_stmt`)))
    (alt
      ((ref `undef_stmt`)))
    (alt
      ((ref `flow_stmt`)))
    (alt
      ((ref `cmd_stmt`)))
    (alt
      ((ref `mod_stmt`)))
    (alt
      ((ref `expr`))))
  (rule
    (name `mod_stmt`)
    (alt
      ((ref `expr`)
        (tok `IF_MOD`)
        (ref `expr`))
      `(if 3 1 _)`)
    (alt
      ((ref `expr`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      `(unless 3 1 _)`)
    (alt
      ((ref `expr`)
        (tok `WHILE_MOD`)
        (ref `expr`))
      `(while 3 1)`)
    (alt
      ((ref `expr`)
        (tok `UNTIL_MOD`)
        (ref `expr`))
      `(until 3 1)`)
    (alt
      ((ref `expr`)
        (tok `RESCUE_MOD`)
        (ref `expr`))
      `(rescue 1 3)`))
  (rule
    (name `expr`)
    (alt
      ((ref `kw_not`))))
  (rule
    (name `kw_not`)
    (alt
      ((tok `NOT_KW`)
        (ref `kw_not`))
      `(not 2)`)
    (alt
      ((ref `kw_or`))))
  (rule
    (name `kw_or`)
    (alt
      ((ref `kw_or`)
        (tok `OR_KW`)
        (ref `kw_and`))
      `(or 1 3)`)
    (alt
      ((ref `kw_and`))))
  (rule
    (name `kw_and`)
    (alt
      ((ref `kw_and`)
        (tok `AND_KW`)
        (ref `asgn`))
      `(and 1 3)`)
    (alt
      ((ref `asgn`))))
  (rule
    (name `asgn`)
    (alt
      ((ref `mlhs`)
        (tok `ASSIGN`)
        (ref `mrhs`))
      `(masgn 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `ASSIGN`)
        (ref `asgn`))
      `(assign 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `PLUS_EQ`)
        (ref `asgn`))
      `(+= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `MINUS_EQ`)
        (ref `asgn`))
      `(-= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `STAR_EQ`)
        (ref `asgn`))
      `(*= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `SLASH_EQ`)
        (ref `asgn`))
      `(/= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `PERCENT_EQ`)
        (ref `asgn`))
      `(%= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `POWER_EQ`)
        (ref `asgn`))
      `(**= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `PIPE_EQ`)
        (ref `asgn`))
      `(|= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `AMP_EQ`)
        (ref `asgn`))
      `(&= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `CARET_EQ`)
        (ref `asgn`))
      `(^= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `LSHIFT_EQ`)
        (ref `asgn`))
      `(<<= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `RSHIFT_EQ`)
        (ref `asgn`))
      `(>>= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `OROR_EQ`)
        (ref `asgn`))
      `(||= 1 3)`)
    (alt
      ((ref `lhs`)
        (tok `ANDAND_EQ`)
        (ref `asgn`))
      `(&&= 1 3)`)
    (alt
      ((ref `ternary`))))
  (rule
    (name `mlhs`)
    (alt
      ((ref `lhs`)
        (lit `","`)
        (ref `lhs`))
      `(mlhs 1 3)`)
    (alt
      ((ref `mlhs`)
        (lit `","`)
        (ref `lhs`))
      `(...1 3)`)
    (alt
      ((ref `mlhs`)
        (lit `","`)
        (ref `splat_lhs`))
      `(...1 3)`))
  (rule
    (name `splat_lhs`)
    (alt
      ((tok `STAR_SPLAT`)
        (ref `lhs`))
      `(splat 2)`))
  (rule
    (name `mrhs`)
    (alt
      ((ref `ternary`)
        (lit `","`)
        (ref `ternary`))
      `(mrhs 1 3)`)
    (alt
      ((ref `mrhs`)
        (lit `","`)
        (ref `ternary`))
      `(...1 3)`)
    (alt
      ((ref `mrhs`)
        (lit `","`)
        (ref `splat_val`))
      `(...1 3)`))
  (rule
    (name `splat_val`)
    (alt
      ((tok `STAR_SPLAT`)
        (ref `ternary`))
      `(splat 2)`))
  (rule
    (name `lhs`)
    (alt
      ((tok `IDENT`)))
    (alt
      ((tok `IVAR`)))
    (alt
      ((tok `CVAR`)))
    (alt
      ((tok `GVAR`)))
    (alt
      ((tok `CONSTANT`)))
    (alt
      ((ref `call`)
        (lit `"."`)
        (tok `IDENT`))
      `(attrasgn 1 3)`)
    (alt
      ((ref `call`)
        (lit `"["`)
        (group_opt
          ((list_req
              `L`
              (plain `arg`))))
        (lit `"]"`))
      `(indexasgn 1 3)`))
  (rule
    (name `ternary`)
    (alt
      ((at_ref `infix`)
        (tok `QUESTION`)
        (ref `ternary`)
        (tok `COLON`)
        (ref `ternary`))
      `(if 1 3 5)`)
    (alt
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
      ((tok `MINUS_U`)
        (ref `unary`))
      `(u- 2)`)
    (alt
      ((tok `PLUS_U`)
        (ref `unary`))
      `(u+ 2)`)
    (alt
      ((tok `BANG`)
        (ref `unary`))
      `(! 2)`)
    (alt
      ((tok `TILDE`)
        (ref `unary`))
      `(~ 2)`)
    (alt
      ((tok `DEFINED`)
        (ref `unary`))
      `(defined 2)`)
    (alt
      ((ref `power`))))
  (rule
    (name `power`)
    (alt
      ((ref `call`)
        (tok `POWER`)
        (ref `unary`))
      `(** 1 3)`)
    (alt
      ((ref `call`))))
  (rule
    (name `call`)
    (alt
      ((ref `call`)
        (lit `"."`)
        (ref `methodname`)
        (group_opt
          ((ref `call_args`)))
        (group_opt
          ((ref `block`))))
      `(send 1 3 4 5)`)
    (alt
      ((ref `call`)
        (lit `"&."`)
        (ref `methodname`)
        (group_opt
          ((ref `call_args`)))
        (group_opt
          ((ref `block`))))
      `(csend 1 3 4 5)`)
    (alt
      ((ref `call`)
        (lit `"["`)
        (group_opt
          ((list_req
              `L`
              (plain `arg`))))
        (lit `"]"`))
      `(index 1 3)`)
    (alt
      ((ref `call`)
        (lit `"::"`)
        (tok `CONSTANT`))
      `(scope 1 3)`)
    (alt
      ((lit `"::"`)
        (tok `CONSTANT`))
      `(scope _ 2)`)
    (alt
      ((tok `IDENT`)
        (ref `call_args`)
        (group_opt
          ((ref `block`))))
      `(send _ 1 2 3)`)
    (alt
      ((tok `SUPER`)
        (group_opt
          ((ref `call_args`))))
      `(super 2)`)
    (alt
      ((tok `YIELD`)
        (group_opt
          ((ref `call_args`))))
      `(yield 2)`)
    (alt
      ((ref `primary`))))
  (rule
    (name `methodname`)
    (alt
      ((tok `IDENT`))))
  (rule
    (name `call_args`)
    (alt
      ((lit `"("`)
        (lit `")"`))
      `(args)`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `arg`))
        (lit `")"`))
      `(args ...2)`))
  (rule
    (name `arg`)
    (alt
      ((ref `expr`)))
    (alt
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      `(splat 2)`)
    (alt
      ((lit `"**"`)
        (ref `expr`))
      `(kwsplat 2)`)
    (alt
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      `(block_pass 2)`)
    (alt
      ((ref `pair`))))
  (rule
    (name `cmd_stmt`)
    (alt
      ((tok `CMD_IDENT`)
        (ref `cmd_args`)
        (group_opt
          ((ref `block`))))
      `(send _ 1 2 3)`)
    (alt
      ((ref `call`)
        (lit `"."`)
        (tok `IDENT`)
        (ref `cmd_args`)
        (group_opt
          ((ref `block`))))
      `(send 1 3 4 5)`))
  (rule
    (name `cmd_args`)
    (alt
      ((list_req
          `L`
          (plain `cmd_arg`)))
      `(args ...1)`))
  (rule
    (name `cmd_arg`)
    (alt
      ((ref `expr`)))
    (alt
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      `(splat 2)`)
    (alt
      ((lit `"**"`)
        (ref `expr`))
      `(kwsplat 2)`)
    (alt
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      `(block_pass 2)`)
    (alt
      ((ref `pair`))))
  (rule
    (name `block`)
    (alt
      ((tok `DO_BLOCK`)
        (group_opt
          ((ref `block_params`)))
        (ref `stmts`)
        (tok `END`))
      `(block 2 3)`)
    (alt
      ((tok `LBRACE_BLOCK`)
        (group_opt
          ((ref `block_params`)))
        (ref `stmts`)
        (lit `"}"`))
      `(block 2 3)`))
  (rule
    (name `block_params`)
    (alt
      ((lit `"|"`)
        (list_req
          `L`
          (plain `param`))
        (lit `"|"`))
      `(params ...2)`)
    (alt
      ((lit `"|"`)
        (lit `"|"`))
      `(params)`))
  (rule
    (name `primary`)
    (alt
      ((tok `IDENT`)))
    (alt
      ((tok `CONSTANT`)))
    (alt
      ((tok `IVAR`)))
    (alt
      ((tok `CVAR`)))
    (alt
      ((tok `GVAR`)))
    (alt
      ((tok `INTEGER`)))
    (alt
      ((tok `FLOAT`)))
    (alt
      ((tok `RATIONAL`)))
    (alt
      ((tok `IMAGINARY`)))
    (alt
      ((tok `STRING_SQ`)))
    (alt
      ((tok `STRING_DQ`)))
    (alt
      ((ref `dstring`)))
    (alt
      ((tok `SYMBOL`)))
    (alt
      ((ref `literal_kw`)))
    (alt
      ((ref `lambda`)))
    (alt
      ((ref `array`)))
    (alt
      ((ref `hash`)))
    (alt
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      `2`))
  (rule
    (name `literal_kw`)
    (alt
      ((tok `TRUE`))
      `(true)`)
    (alt
      ((tok `FALSE`))
      `(false)`)
    (alt
      ((tok `NIL`))
      `(nil)`)
    (alt
      ((tok `SELF`))
      `(self)`)
    (alt
      ((tok `KW__FILE__`))
      `(__FILE__)`)
    (alt
      ((tok `KW__LINE__`))
      `(__LINE__)`)
    (alt
      ((tok `KW__ENCODING__`))
      `(__ENCODING__)`))
  (rule
    (name `lambda`)
    (alt
      ((tok `ARROW`)
        (group_opt
          ((ref `params`)))
        (ref `block`))
      `(lambda 2 3)`))
  (rule
    (name `dstring`)
    (alt
      ((tok `DSTR_BEG`)
        (quantified
          (ref `dstr_part`)
          (one_plus))
        (tok `DSTR_END`))
      `(dstr ...2)`)
    (alt
      ((tok `DSTR_BEG`)
        (tok `DSTR_END`))
      `(dstr)`))
  (rule
    (name `dstr_part`)
    (alt
      ((tok `STR_CONTENT`)))
    (alt
      ((tok `EMBEXPR_BEG`)
        (ref `stmts`)
        (tok `EMBEXPR_END`))
      `(evstr 2)`))
  (rule
    (name `array`)
    (alt
      ((lit `"["`)
        (group_opt
          ((list_req
              `L`
              (plain `elem`))))
        (lit `"]"`))
      `(array ...2)`))
  (rule
    (name `elem`)
    (alt
      ((ref `expr`)))
    (alt
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      `(splat 2)`))
  (rule
    (name `hash`)
    (alt
      ((tok `LBRACE`)
        (group_opt
          ((list_req
              `L`
              (plain `pair`))))
        (lit `"}"`))
      `(hash ...2)`))
  (rule
    (name `pair`)
    (alt
      ((tok `LABEL`)
        (ref `expr`))
      `(pair 1 2)`)
    (alt
      ((ref `expr`)
        (lit `"=>"`)
        (ref `expr`))
      `(pair 1 3)`)
    (alt
      ((lit `"**"`)
        (ref `expr`))
      `(kwsplat 2)`))
  (rule
    (name `if_stmt`)
    (alt
      ((tok `IF`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `else_clause`)
        (tok `END`))
      `(if 2 4 5)`))
  (rule
    (name `else_clause`)
    (alt () `()`)
    (alt
      ((tok `ELSE`)
        (ref `stmts`))
      `2`)
    (alt
      ((tok `ELSIF`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `else_clause`))
      `(if 2 4 5)`))
  (rule
    (name `then_sep`)
    (alt
      ((tok `THEN_SEP`))
      `()`))
  (rule
    (name `unless_stmt`)
    (alt
      ((tok `UNLESS`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `opt_else`)
        (tok `END`))
      `(unless 2 4 5)`))
  (rule
    (name `opt_else`)
    (alt () `()`)
    (alt
      ((tok `ELSE`)
        (ref `stmts`))
      `2`))
  (rule
    (name `while_stmt`)
    (alt
      ((tok `WHILE`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      `(while 2 4)`))
  (rule
    (name `until_stmt`)
    (alt
      ((tok `UNTIL`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      `(until 2 4)`))
  (rule
    (name `do_sep`)
    (alt
      ((tok `DO_SEP`))
      `()`))
  (rule
    (name `for_stmt`)
    (alt
      ((tok `FOR`)
        (tok `IDENT`)
        (tok `IN`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      `(for 2 4 6)`))
  (rule
    (name `case_stmt`)
    (alt
      ((tok `CASE`)
        (ref `expr`)
        (ref `then_sep`)
        (quantified
          (ref `when_clause`)
          (one_plus))
        (ref `opt_else`)
        (tok `END`))
      `(case 2 ...4 5)`)
    (alt
      ((tok `CASE`)
        (ref `then_sep`)
        (quantified
          (ref `when_clause`)
          (one_plus))
        (ref `opt_else`)
        (tok `END`))
      `(case _ ...3 4)`))
  (rule
    (name `when_clause`)
    (alt
      ((tok `WHEN`)
        (list_req
          `L`
          (plain `arg`))
        (ref `then_sep`)
        (ref `stmts`))
      `(when ...2 4)`))
  (rule
    (name `begin_stmt`)
    (alt
      ((tok `BEGIN_KW`)
        (ref `sep`)
        (ref `stmts`)
        (quantified
          (ref `rescue_cl`)
          (zero_plus))
        (ref `ensure_cl`)
        (tok `END`))
      `(begin 3 4 5)`))
  (rule
    (name `rescue_cl`)
    (alt
      ((tok `RESCUE`)
        (ref `then_sep`)
        (ref `stmts`))
      `(rescue _ _ 3)`)
    (alt
      ((tok `RESCUE`)
        (list_req
          `L`
          (plain `const_path`))
        (ref `then_sep`)
        (ref `stmts`))
      `(rescue 2 _ 4)`)
    (alt
      ((tok `RESCUE`)
        (list_req
          `L`
          (plain `const_path`))
        (lit `"=>"`)
        (tok `IDENT`)
        (ref `then_sep`)
        (ref `stmts`))
      `(rescue 2 4 6)`))
  (rule
    (name `ensure_cl`)
    (alt
      ((tok `ENSURE`)
        (ref `sep`)
        (ref `stmts`))
      `(ensure 3)`)
    (alt () `()`))
  (rule
    (name `def_stmt`)
    (alt
      ((tok `DEF`)
        (ref `methodname`)
        (group_opt
          ((ref `params`)))
        (ref `sep`)
        (ref `stmts`)
        (quantified
          (ref `rescue_cl`)
          (zero_plus))
        (ref `ensure_cl`)
        (tok `END`))
      `(def 2 3 5 6 7)`)
    (alt
      ((tok `DEF`)
        (ref `primary`)
        (lit `"."`)
        (ref `methodname`)
        (group_opt
          ((ref `params`)))
        (ref `sep`)
        (ref `stmts`)
        (quantified
          (ref `rescue_cl`)
          (zero_plus))
        (ref `ensure_cl`)
        (tok `END`))
      `(defs 2 4 5 7 8 9)`))
  (rule
    (name `params`)
    (alt
      ((lit `"("`)
        (lit `")"`))
      `(params)`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `param`))
        (lit `")"`))
      `(params ...2)`))
  (rule
    (name `param`)
    (alt
      ((tok `IDENT`)))
    (alt
      ((tok `IDENT`)
        (lit `"="`)
        (ref `expr`))
      `(optarg 1 3)`)
    (alt
      ((tok `LABEL`))
      `(kwarg 1)`)
    (alt
      ((tok `LABEL`)
        (ref `expr`))
      `(kwoptarg 1 2)`)
    (alt
      ((tok `STAR_SPLAT`)
        (tok `IDENT`))
      `(restarg 2)`)
    (alt
      ((lit `"**"`)
        (tok `IDENT`))
      `(kwrestarg 2)`)
    (alt
      ((tok `AMP_BLOCK`)
        (tok `IDENT`))
      `(blockarg 2)`))
  (rule
    (name `class_stmt`)
    (alt
      ((tok `CLASS`)
        (ref `const_path`)
        (group_opt
          ((ref `superclass`)))
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      `(class 2 3 5)`)
    (alt
      ((tok `CLASS`)
        (lit `"<<"`)
        (ref `expr`)
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      `(sclass 3 5)`))
  (rule
    (name `superclass`)
    (alt
      ((lit `"<"`)
        (ref `const_path`))
      `2`))
  (rule
    (name `module_stmt`)
    (alt
      ((tok `MODULE`)
        (ref `const_path`)
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      `(module 2 4)`))
  (rule
    (name `const_path`)
    (alt
      ((tok `CONSTANT`)))
    (alt
      ((ref `const_path`)
        (lit `"::"`)
        (tok `CONSTANT`))
      `(scope 1 3)`))
  (rule
    (name `alias_stmt`)
    (alt
      ((tok `ALIAS`)
        (ref `alias_name`)
        (ref `alias_name`))
      `(alias 2 3)`))
  (rule
    (name `undef_stmt`)
    (alt
      ((tok `UNDEF`)
        (list_req
          `L`
          (plain `alias_name`)))
      `(undef ...2)`))
  (rule
    (name `alias_name`)
    (alt
      ((tok `IDENT`)))
    (alt
      ((tok `SYMBOL`))))
  (rule
    (name `flow_stmt`)
    (alt
      ((tok `RETURN`)
        (ref `cmd_args`))
      `(return 2)`)
    (alt
      ((tok `RETURN`))
      `(return)`)
    (alt
      ((tok `BREAK`)
        (ref `cmd_args`))
      `(break 2)`)
    (alt
      ((tok `BREAK`))
      `(break)`)
    (alt
      ((tok `NEXT`)
        (ref `cmd_args`))
      `(next 2)`)
    (alt
      ((tok `NEXT`))
      `(next)`)
    (alt
      ((tok `YIELD`)
        (ref `cmd_args`))
      `(yield 2)`)
    (alt
      ((tok `SUPER`)
        (ref `cmd_args`))
      `(super 2)`)
    (alt
      ((tok `RETRY`))
      `(retry)`)
    (alt
      ((tok `REDO`))
      `(redo)`)))
