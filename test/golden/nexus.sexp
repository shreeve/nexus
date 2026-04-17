(grammar
  (lang `"lang"`)
  (conflicts `16`)
  (rule
    (start `grammar`)
    (alt
      ((ref `entries`))
      `(grammar ...1)`))
  (rule
    (name `entries`)
    (alt
      ((ref `entries`)
        (ref `entry`))
      `(...1 2)`)
    (alt
      ((ref `entries`)
        (tok `NEWLINE`))
      `1`)
    (alt
      ((ref `entries`)
        (tok `COMMENT`))
      `1`)
    (alt
      ((ref `entry`))
      `(1)`)
    (alt () `()`))
  (rule
    (name `entry`)
    (alt
      ((ref `directive`))
      `1`)
    (alt
      ((ref `production`))
      `1`))
  (rule
    (name `directive`)
    (alt
      ((lit `"@"`)
        (tok `KW_LANG`)
        (lit `"="`)
        (tok `STRING`))
      `(lang 4)`)
    (alt
      ((lit `"@"`)
        (tok `KW_CONFLICTS`)
        (lit `"="`)
        (tok `INTEGER`))
      `(conflicts 4)`)
    (alt
      ((lit `"@"`)
        (tok `KW_AS`)
        (ref `as_body`))
      `(as ...3)`)
    (alt
      ((lit `"@"`)
        (tok `KW_OP`)
        (lit `"="`)
        (lit `"["`)
        (ref `op_content`)
        (lit `"]"`))
      `(op ...5)`)
    (alt
      ((lit `"@"`)
        (tok `KW_CODE`)
        (tok `IDENT`)
        (ref `code_block`))
      `(code 3 4)`)
    (alt
      ((lit `"@"`)
        (tok `KW_ERRORS`)
        (ref `error_items`))
      `(errors ...3)`)
    (alt
      ((lit `"@"`)
        (tok `KW_INFIX`)
        (ref `infix_body`))
      `(infix ...3)`))
  (rule
    (name `as_body`)
    (alt
      ((tok `IDENT`)
        (lit `"="`)
        (lit `"["`)
        (ref `as_list`)
        (lit `"]"`))
      `(1 ...4)`))
  (rule
    (name `as_list`)
    (alt
      ((ref `as_list`)
        (lit `","`)
        (ref `as_entry`))
      `(...1 3)`)
    (alt
      ((ref `as_entry`))
      `(1)`))
  (rule
    (name `as_entry`)
    (alt
      ((tok `IDENT`)
        (lit `"!"`))
      `(as_perm 1)`)
    (alt
      ((tok `IDENT`))
      `(as_strict 1)`))
  (rule
    (name `op_content`)
    (alt
      ((ref `op_content`)
        (ref `op_item`))
      `(...1 2)`)
    (alt
      ((ref `op_content`)
        (lit `","`))
      `1`)
    (alt
      ((ref `op_content`)
        (tok `NEWLINE`))
      `1`)
    (alt
      ((ref `op_content`)
        (tok `COMMENT`))
      `1`)
    (alt
      ((ref `op_item`))
      `(1)`)
    (alt () `()`))
  (rule
    (name `op_item`)
    (alt
      ((tok `STRING`)
        (tok `ARROW`)
        (tok `STRING`))
      `(op_map 1 3)`))
  (rule
    (name `error_items`)
    (alt
      ((ref `error_items`)
        (ref `error_pair`))
      `(...1 2)`)
    (alt
      ((ref `error_items`)
        (lit `","`))
      `1`)
    (alt
      ((ref `error_items`)
        (tok `NEWLINE`))
      `1`)
    (alt
      ((ref `error_items`)
        (tok `COMMENT`))
      `1`)
    (alt
      ((ref `error_pair`))
      `(1)`))
  (rule
    (name `error_pair`)
    (alt
      ((tok `IDENT`)
        (lit `":"`)
        (tok `STRING`))
      `(error_name 1 3)`)
    (alt
      ((tok `TOKEN`)
        (lit `":"`)
        (tok `STRING`))
      `(error_name 1 3)`))
  (rule
    (name `infix_body`)
    (alt
      ((tok `IDENT`)
        (ref `nl_skip`)
        (ref `infix_rows`))
      `(1 ...3)`))
  (rule
    (name `nl_skip`)
    (alt
      ((ref `nl_skip`)
        (tok `NEWLINE`))
      `1`)
    (alt
      ((ref `nl_skip`)
        (tok `COMMENT`))
      `1`)
    (alt
      ((tok `NEWLINE`)))
    (alt
      ((tok `COMMENT`))))
  (rule
    (name `infix_rows`)
    (alt
      ((ref `infix_rows`)
        (tok `NEWLINE`)
        (ref `infix_row`))
      `(...1 3)`)
    (alt
      ((ref `infix_rows`)
        (tok `NEWLINE`))
      `1`)
    (alt
      ((ref `infix_rows`)
        (tok `COMMENT`))
      `1`)
    (alt
      ((ref `infix_row`))
      `(1)`))
  (rule
    (name `infix_row`)
    (alt
      ((ref `infix_ops`))
      `(level ...1)`))
  (rule
    (name `infix_ops`)
    (alt
      ((ref `infix_ops`)
        (lit `","`)
        (ref `infix_op`))
      `(...1 3)`)
    (alt
      ((ref `infix_op`))
      `(1)`))
  (rule
    (name `infix_op`)
    (alt
      ((tok `STRING`)
        (tok `KW_LEFT`))
      `(infix_op 1 2)`)
    (alt
      ((tok `STRING`)
        (tok `KW_RIGHT`))
      `(infix_op 1 2)`)
    (alt
      ((tok `STRING`)
        (tok `KW_NONE`))
      `(infix_op 1 2)`)
    (alt
      ((tok `STRING`)
        (tok `IDENT`))
      `(infix_op 1 2)`))
  (rule
    (name `code_block`)
    (alt
      ((tok `CODE_BLOCK`))
      `1`))
  (rule
    (name `production`)
    (alt
      ((ref `rule_name`)
        (lit `"="`)
        (ref `alts`)
        (ref `prod_tail`))
      `(rule 1 ...3 ...4)`))
  (rule
    (name `alts`)
    (alt
      ((ref `alts`)
        (lit `"|"`)
        (ref `alt_line`))
      `(...1 3)`)
    (alt
      ((ref `alt_line`))
      `(1)`))
  (rule
    (name `prod_tail`)
    (alt
      ((ref `prod_tail`)
        (tok `NEWLINE`)
        (lit `"|"`)
        (ref `alts`))
      `(...1 ...4)`)
    (alt
      ((ref `prod_tail`)
        (tok `NEWLINE`)
        (tok `COMMENT`))
      `1`)
    (alt
      ((ref `prod_tail`)
        (tok `NEWLINE`))
      `1`)
    (alt () `()`))
  (rule
    (name `rule_name`)
    (alt
      ((tok `IDENT`)
        (lit `"!"`))
      `(start 1)`)
    (alt
      ((tok `IDENT`))
      `(name 1)`)
    (alt
      ((tok `TOKEN`)
        (lit `"!"`))
      `(start 1)`)
    (alt
      ((tok `TOKEN`))
      `(name 1)`))
  (rule
    (name `alt_line`)
    (alt
      ((ref `elements`)
        (tok `ARROW`)
        (tok `ACTION_TEXT`))
      `(alt 1 3)`)
    (alt
      ((ref `elements`)
        (lit `"<"`)
        (tok `ARROW`)
        (tok `ACTION_TEXT`))
      `(alt_reduce 1 4)`)
    (alt
      ((ref `elements`)
        (lit `">"`)
        (tok `ARROW`)
        (tok `ACTION_TEXT`))
      `(alt_shift 1 4)`)
    (alt
      ((ref `elements`)
        (lit `"<"`))
      `(alt_reduce 1)`)
    (alt
      ((ref `elements`)
        (lit `">"`))
      `(alt_shift 1)`)
    (alt
      ((ref `elements`))
      `(alt 1)`))
  (rule
    (name `elements`)
    (alt
      ((ref `elements`)
        (ref `element`))
      `(...1 2)`)
    (alt () `()`))
  (rule
    (name `element`)
    (alt
      ((ref `primary`)
        (ref `quantifier`))
      `(quantified 1 2)`)
    (alt
      ((lit `"!"`)
        (ref `primary`)
        (ref `quantifier`))
      `(skip_q 2 3)`)
    (alt
      ((lit `"!"`)
        (ref `primary`))
      `(skip 2)`)
    (alt
      ((tok `KW_X`)
        (tok `STRING`))
      `(exclude 2)`)
    (alt
      ((ref `primary`))))
  (rule
    (name `primary`)
    (alt
      ((tok `IDENT`))
      `(ref 1)`)
    (alt
      ((tok `TOKEN`)
        (lit `"("`)
        (ref `bracket_inner`)
        (lit `")"`))
      `(list_req 1 3)`)
    (alt
      ((tok `TOKEN`))
      `(tok 1)`)
    (alt
      ((tok `STRING`))
      `(lit 1)`)
    (alt
      ((lit `"@"`)
        (tok `IDENT`))
      `(at_ref 2)`)
    (alt
      ((lit `"@"`)
        (tok `KW_INFIX`))
      `(at_ref 2)`)
    (alt
      ((lit `"("`)
        (ref `alt_group`)
        (lit `")"`))
      `(group ...2)`)
    (alt
      ((lit `"["`)
        (ref `bracket_body`)
        (lit `"]"`))
      `2`))
  (rule
    (name `bracket_body`)
    (alt
      ((ref `alt_group`)
        (lit `"..."`))
      `(group_many ...1)`)
    (alt
      ((ref `alt_group`))
      `(group_opt ...1)`))
  (rule
    (name `bracket_inner`)
    (alt
      ((tok `IDENT`)
        (lit `"?"`)
        (lit `","`)
        (ref `sep_term`))
      `(opt_items 1 4)`)
    (alt
      ((tok `IDENT`)
        (lit `","`)
        (ref `sep_term`))
      `(sep_items 1 3)`)
    (alt
      ((tok `IDENT`)
        (lit `"?"`))
      `(opt_items_nosep 1)`)
    (alt
      ((tok `IDENT`))
      `(plain 1)`))
  (rule
    (name `sep_term`)
    (alt
      ((tok `STRING`))
      `(1)`)
    (alt
      ((tok `TOKEN`))
      `(1)`))
  (rule
    (name `alt_group`)
    (alt
      ((ref `alt_group`)
        (lit `"|"`)
        (ref `alt_elem`))
      `(...1 3)`)
    (alt
      ((ref `alt_elem`))
      `(1)`))
  (rule
    (name `alt_elem`)
    (alt
      ((ref `alt_elem`)
        (ref `element`))
      `(...1 2)`)
    (alt
      ((ref `element`))
      `(1)`))
  (rule
    (name `quantifier`)
    (alt
      ((lit `"?"`))
      `(opt)`)
    (alt
      ((lit `"*"`))
      `(zero_plus)`)
    (alt
      ((lit `"+"`))
      `(one_plus)`)))
