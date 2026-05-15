(grammar
  (lang `"ruby"`)
  (conflicts `66`)
  (as
    `ident`
    (as_entry perm `keyword`))
  (rule
    (start `program`)
    (alt
      _
      ((ref `stmts`))
      `(program ...1)`))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      `1`))
  (rule
    (name `stmts`)
    (alt
      _
      ((ref `stmt_list`))
      `1`)
    (alt _ () `(stmts)`))
  (rule
    (name `stmt_list`)
    (alt
      _
      ((ref `stmt_list`)
        (ref `sep`)
        (ref `stmt`))
      `(...1 3)`)
    (alt
      _
      ((ref `stmt_list`)
        (ref `sep`))
      `1`)
    (alt
      _
      ((ref `sep`)
        (ref `stmt_list`))
      `2`)
    (alt
      _
      ((ref `stmt`))
      `(stmts 1)`)
    (alt
      _
      ((ref `sep`))
      `(stmts)`))
  (rule
    (name `sep`)
    (alt
      _
      ((tok `NEWLINE`))
      `()`)
    (alt
      _
      ((tok `SEMICOLON`))
      `()`))
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
      `(if 3 1 _)`)
    (alt
      _
      ((ref `expr`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      `(unless 3 1 _)`)
    (alt
      _
      ((ref `expr`)
        (tok `WHILE_MOD`)
        (ref `expr`))
      `(while 3 1)`)
    (alt
      _
      ((ref `expr`)
        (tok `UNTIL_MOD`)
        (ref `expr`))
      `(until 3 1)`)
    (alt
      _
      ((ref `expr`)
        (tok `RESCUE_MOD`)
        (ref `expr`))
      `(rescue 1 3)`)
    (alt
      _
      ((ref `flow_stmt`)
        (tok `IF_MOD`)
        (ref `expr`))
      `(if 3 1 _)`)
    (alt
      _
      ((ref `flow_stmt`)
        (tok `UNLESS_MOD`)
        (ref `expr`))
      `(unless 3 1 _)`))
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
      `(not 2)`)
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
      `(or 1 3)`)
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
      `(and 1 3)`)
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
      `(masgn 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `ASSIGN`)
        (ref `asgn`))
      `(assign 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `PLUS_EQ`)
        (ref `asgn`))
      `(+= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `MINUS_EQ`)
        (ref `asgn`))
      `(-= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `STAR_EQ`)
        (ref `asgn`))
      `(*= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `SLASH_EQ`)
        (ref `asgn`))
      `(/= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `PERCENT_EQ`)
        (ref `asgn`))
      `(%= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `POWER_EQ`)
        (ref `asgn`))
      `(**= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `PIPE_EQ`)
        (ref `asgn`))
      `(|= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `AMP_EQ`)
        (ref `asgn`))
      `(&= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `CARET_EQ`)
        (ref `asgn`))
      `(^= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `LSHIFT_EQ`)
        (ref `asgn`))
      `(<<= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `RSHIFT_EQ`)
        (ref `asgn`))
      `(>>= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `OROR_EQ`)
        (ref `asgn`))
      `(||= 1 3)`)
    (alt
      _
      ((ref `lhs`)
        (tok `ANDAND_EQ`)
        (ref `asgn`))
      `(&&= 1 3)`)
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
      `(mlhs 1 3)`)
    (alt
      _
      ((ref `mlhs`)
        (lit `","`)
        (ref `lhs`))
      `(...1 3)`)
    (alt
      _
      ((ref `mlhs`)
        (lit `","`)
        (ref `splat_lhs`))
      `(...1 3)`))
  (rule
    (name `splat_lhs`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `lhs`))
      `(splat 2)`))
  (rule
    (name `mrhs`)
    (alt
      _
      ((ref `ternary`)
        (lit `","`)
        (ref `ternary`))
      `(mrhs 1 3)`)
    (alt
      _
      ((ref `mrhs`)
        (lit `","`)
        (ref `ternary`))
      `(...1 3)`)
    (alt
      _
      ((ref `mrhs`)
        (lit `","`)
        (ref `splat_val`))
      `(...1 3)`))
  (rule
    (name `splat_val`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `ternary`))
      `(splat 2)`))
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
      `(attrasgn 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (group
          opt
          ((ref `index_args`)))
        (lit `"]"`))
      `(indexasgn 1 3)`))
  (rule
    (name `ternary`)
    (alt
      _
      ((at_ref `infix`)
        (tok `QUESTION`)
        (ref `ternary`)
        (tok `COLON`)
        (ref `ternary`))
      `(if 1 3 5)`)
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
      `(u- 2)`)
    (alt
      _
      ((tok `PLUS_U`)
        (ref `unary`))
      `(u+ 2)`)
    (alt
      _
      ((tok `BANG`)
        (ref `unary`))
      `(! 2)`)
    (alt
      _
      ((tok `TILDE`)
        (ref `unary`))
      `(~ 2)`)
    (alt
      _
      ((tok `DEFINED`)
        (ref `unary`))
      `(defined 2)`)
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
      `(** 1 3)`)
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
      `(send 1 3 4 5)`)
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
      `(csend 1 3 4 5)`)
    (alt
      _
      ((ref `call`)
        (lit `"["`)
        (group
          opt
          ((ref `index_args`)))
        (lit `"]"`))
      `(index 1 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"::"`)
        (tok `CONSTANT`))
      `(scope 1 3)`)
    (alt
      _
      ((lit `"::"`)
        (tok `CONSTANT`))
      `(scope _ 2)`)
    (alt
      _
      ((tok `IDENT`)
        (ref `call_args`)
        (group
          opt
          ((ref `block`))))
      `(send _ 1 2 3)`)
    (alt
      _
      ((tok `IDENT`)
        (ref `block`))
      `(send _ 1 _ 2)`)
    (alt
      _
      ((tok `SUPER`)
        (group
          opt
          ((ref `call_args`))))
      `(super 2)`)
    (alt
      _
      ((tok `YIELD`)
        (group
          opt
          ((ref `call_args`))))
      `(yield 2)`)
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
      `(args ...1)`))
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
      `(args)`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `arg`))
        (lit `")"`))
      `(args ...2)`))
  (rule
    (name `arg`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      `(splat 2)`)
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      `(kwsplat 2)`)
    (alt
      _
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      `(block_pass 2)`)
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
      `(send _ 1 2 3)`)
    (alt
      _
      ((ref `call`)
        (lit `"."`)
        (tok `IDENT`)
        (ref `cmd_args`)
        (group
          opt
          ((ref `block`))))
      `(send 1 3 4 5)`))
  (rule
    (name `cmd_args`)
    (alt
      _
      ((list_req
          `L`
          (plain `cmd_arg`)))
      `(args ...1)`))
  (rule
    (name `cmd_arg`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      `(splat 2)`)
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      `(kwsplat 2)`)
    (alt
      _
      ((tok `AMP_BLOCK`)
        (ref `expr`))
      `(block_pass 2)`)
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
      `(block 2 3)`)
    (alt
      _
      ((tok `LBRACE_BLOCK`)
        (group
          opt
          ((ref `block_params`)))
        (ref `stmts`)
        (lit `"}"`))
      `(block 2 3)`))
  (rule
    (name `block_params`)
    (alt
      _
      ((lit `"|"`)
        (list_req
          `L`
          (plain `param`))
        (lit `"|"`))
      `(params ...2)`)
    (alt
      _
      ((lit `"|"`)
        (lit `"|"`))
      `(params)`))
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
      `2`))
  (rule
    (name `literal_kw`)
    (alt
      _
      ((tok `TRUE`))
      `(true)`)
    (alt
      _
      ((tok `FALSE`))
      `(false)`)
    (alt
      _
      ((tok `NIL`))
      `(nil)`)
    (alt
      _
      ((tok `SELF`))
      `(self)`)
    (alt
      _
      ((tok `KW__FILE__`))
      `(__FILE__)`)
    (alt
      _
      ((tok `KW__LINE__`))
      `(__LINE__)`)
    (alt
      _
      ((tok `KW__ENCODING__`))
      `(__ENCODING__)`))
  (rule
    (name `lambda`)
    (alt
      _
      ((tok `ARROW`)
        (group
          opt
          ((ref `params`)))
        (ref `block`))
      `(lambda 2 3)`))
  (rule
    (name `dstring`)
    (alt
      _
      ((tok `DSTR_BEG`)
        (quantified
          (ref `dstr_part`)
          (one_plus))
        (tok `DSTR_END`))
      `(dstr ...2)`)
    (alt
      _
      ((tok `DSTR_BEG`)
        (tok `DSTR_END`))
      `(dstr)`))
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
      `(evstr 2)`))
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
      `(array ...2)`))
  (rule
    (name `elem`)
    (alt
      _
      ((ref `expr`)))
    (alt
      _
      ((tok `STAR_SPLAT`)
        (ref `expr`))
      `(splat 2)`))
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
      `(hash ...2)`))
  (rule
    (name `pair`)
    (alt
      _
      ((tok `LABEL`)
        (ref `expr`))
      `(pair 1 2)`)
    (alt
      _
      ((ref `expr`)
        (lit `"=>"`)
        (ref `expr`))
      `(pair 1 3)`)
    (alt
      _
      ((lit `"**"`)
        (ref `expr`))
      `(kwsplat 2)`))
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
      `(if 2 4 5)`))
  (rule
    (name `else_clause`)
    (alt _ () `()`)
    (alt
      _
      ((tok `ELSE`)
        (ref `stmts`))
      `2`)
    (alt
      _
      ((tok `ELSIF`)
        (ref `expr`)
        (ref `then_sep`)
        (ref `stmts`)
        (ref `else_clause`))
      `(if 2 4 5)`))
  (rule
    (name `then_sep`)
    (alt
      _
      ((tok `THEN_SEP`))
      `()`))
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
      `(unless 2 4 5)`))
  (rule
    (name `opt_else`)
    (alt _ () `()`)
    (alt
      _
      ((tok `ELSE`)
        (ref `stmts`))
      `2`))
  (rule
    (name `while_stmt`)
    (alt
      _
      ((tok `WHILE`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      `(while 2 4)`))
  (rule
    (name `until_stmt`)
    (alt
      _
      ((tok `UNTIL`)
        (ref `expr`)
        (ref `do_sep`)
        (ref `stmts`)
        (tok `END`))
      `(until 2 4)`))
  (rule
    (name `do_sep`)
    (alt
      _
      ((tok `DO_SEP`))
      `()`))
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
      `(for 2 4 6)`))
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
      `(case 2 ...4 5)`)
    (alt
      _
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
      _
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
      _
      ((tok `BEGIN_KW`)
        (ref `sep`)
        (ref `stmts`)
        (ref `rescues`)
        (ref `ensure_cl`)
        (tok `END`))
      `(begin 3 4 5)`))
  (rule
    (name `rescues`)
    (alt
      _
      ((ref `rescue_cl`))
      `1`)
    (alt
      _
      ((ref `rescues`)
        (ref `rescue_cl`))
      `(...1 2)`)
    (alt _ () `()`))
  (rule
    (name `rescue_cl`)
    (alt
      _
      ((tok `RESCUE`)
        (ref `then_sep`)
        (ref `stmts`))
      `(rescue _ _ 3)`)
    (alt
      _
      ((tok `RESCUE`)
        (lit `"=>"`)
        (tok `IDENT`)
        (ref `then_sep`)
        (ref `stmts`))
      `(rescue _ 3 5)`)
    (alt
      _
      ((tok `RESCUE`)
        (list_req
          `L`
          (plain `const_path`))
        (ref `then_sep`)
        (ref `stmts`))
      `(rescue 2 _ 4)`)
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
      `(rescue 2 4 6)`))
  (rule
    (name `ensure_cl`)
    (alt
      _
      ((tok `ENSURE`)
        (ref `sep`)
        (ref `stmts`))
      `(ensure 3)`)
    (alt _ () `()`))
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
      `(def 2 3 5 6 7)`)
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
      `(defs 2 4 5 7 8 9)`))
  (rule
    (name `params`)
    (alt
      _
      ((lit `"("`)
        (lit `")"`))
      `(params)`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `param`))
        (lit `")"`))
      `(params ...2)`))
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
      `(optarg 1 3)`)
    (alt
      _
      ((tok `LABEL`))
      `(kwarg 1)`)
    (alt
      _
      ((tok `LABEL`)
        (ref `expr`))
      `(kwoptarg 1 2)`)
    (alt
      _
      ((tok `STAR_SPLAT`)
        (tok `IDENT`))
      `(restarg 2)`)
    (alt
      _
      ((lit `"**"`)
        (tok `IDENT`))
      `(kwrestarg 2)`)
    (alt
      _
      ((tok `AMP_BLOCK`)
        (tok `IDENT`))
      `(blockarg 2)`))
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
      `(class 2 3 5)`)
    (alt
      _
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
      _
      ((lit `"<"`)
        (ref `const_path`))
      `2`))
  (rule
    (name `module_stmt`)
    (alt
      _
      ((tok `MODULE`)
        (ref `const_path`)
        (ref `sep`)
        (ref `stmts`)
        (tok `END`))
      `(module 2 4)`))
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
      `(scope 1 3)`))
  (rule
    (name `alias_stmt`)
    (alt
      _
      ((tok `ALIAS`)
        (ref `alias_name`)
        (ref `alias_name`))
      `(alias 2 3)`))
  (rule
    (name `undef_stmt`)
    (alt
      _
      ((tok `UNDEF`)
        (list_req
          `L`
          (plain `alias_name`)))
      `(undef ...2)`))
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
      `(return 2)`)
    (alt
      _
      ((tok `RETURN`))
      `(return)`)
    (alt
      _
      ((tok `BREAK`)
        (ref `cmd_args`))
      `(break 2)`)
    (alt
      _
      ((tok `BREAK`))
      `(break)`)
    (alt
      _
      ((tok `NEXT`)
        (ref `cmd_args`))
      `(next 2)`)
    (alt
      _
      ((tok `NEXT`))
      `(next)`)
    (alt
      _
      ((tok `YIELD`)
        (ref `cmd_args`))
      `(yield 2)`)
    (alt
      _
      ((tok `SUPER`)
        (ref `cmd_args`))
      `(super 2)`)
    (alt
      _
      ((tok `RETRY`))
      `(retry)`)
    (alt
      _
      ((tok `REDO`))
      `(redo)`)))
