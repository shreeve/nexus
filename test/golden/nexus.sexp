(grammar
  (lang `"lang"`)
  (conflicts `16`)
  (rule
    (start `grammar`)
    (alt
      _
      ((ref `entries`))
      `(grammar ...1)`))
  (rule
    (name `entries`)
    (alt
      _
      ((ref `entries`)
        (ref `entry`))
      `(...1 2)`)
    (alt
      _
      ((ref `entries`)
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((ref `entries`)
        (tok `COMMENT`))
      `1`)
    (alt
      _
      ((ref `entry`))
      `(1)`)
    (alt _ () `()`))
  (rule
    (name `entry`)
    (alt
      _
      ((ref `directive`))
      `1`)
    (alt
      _
      ((ref `production`))
      `1`))
  (rule
    (name `directive`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_LANG`)
        (lit `"="`)
        (tok `STRING`))
      `(lang 4)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_CONFLICTS`)
        (lit `"="`)
        (tok `INTEGER`))
      `(conflicts 4)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_AS`)
        (ref `as_body`))
      `(as ...3)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_OP`)
        (lit `"="`)
        (lit `"["`)
        (ref `op_content`)
        (lit `"]"`))
      `(op ...5)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_CODE`)
        (tok `IDENT`)
        (ref `code_block`))
      `(code 3 4)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_ERRORS`)
        (ref `error_items`))
      `(errors ...3)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_INFIX`)
        (ref `infix_body`))
      `(infix ...3)`))
  (rule
    (name `as_body`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"="`)
        (lit `"["`)
        (ref `as_list`)
        (lit `"]"`))
      `(1 ...4)`))
  (rule
    (name `as_list`)
    (alt
      _
      ((ref `as_list`)
        (lit `","`)
        (ref `as_entry`))
      `(...1 3)`)
    (alt
      _
      ((ref `as_entry`))
      `(1)`))
  (rule
    (name `as_entry`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"!"`))
      `(as_entry perm 1)`)
    (alt
      _
      ((tok `IDENT`))
      `(as_entry _ 1)`))
  (rule
    (name `op_content`)
    (alt
      _
      ((ref `op_content`)
        (ref `op_item`))
      `(...1 2)`)
    (alt
      _
      ((ref `op_content`)
        (lit `","`))
      `1`)
    (alt
      _
      ((ref `op_content`)
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((ref `op_content`)
        (tok `COMMENT`))
      `1`)
    (alt
      _
      ((ref `op_item`))
      `(1)`)
    (alt _ () `()`))
  (rule
    (name `op_item`)
    (alt
      _
      ((tok `STRING`)
        (tok `ARROW`)
        (tok `STRING`))
      `(op_map 1 3)`))
  (rule
    (name `error_items`)
    (alt
      _
      ((ref `error_items`)
        (ref `error_pair`))
      `(...1 2)`)
    (alt
      _
      ((ref `error_items`)
        (lit `","`))
      `1`)
    (alt
      _
      ((ref `error_items`)
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((ref `error_items`)
        (tok `COMMENT`))
      `1`)
    (alt
      _
      ((ref `error_pair`))
      `(1)`))
  (rule
    (name `error_pair`)
    (alt
      _
      ((tok `IDENT`)
        (lit `":"`)
        (tok `STRING`))
      `(error_name 1 3)`)
    (alt
      _
      ((tok `TOKEN`)
        (lit `":"`)
        (tok `STRING`))
      `(error_name 1 3)`))
  (rule
    (name `infix_body`)
    (alt
      _
      ((tok `IDENT`)
        (ref `nl_skip`)
        (ref `infix_rows`))
      `(1 ...3)`))
  (rule
    (name `nl_skip`)
    (alt
      _
      ((ref `nl_skip`)
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((ref `nl_skip`)
        (tok `COMMENT`))
      `1`)
    (alt
      _
      ((tok `NEWLINE`)))
    (alt
      _
      ((tok `COMMENT`))))
  (rule
    (name `infix_rows`)
    (alt
      _
      ((ref `infix_rows`)
        (tok `NEWLINE`)
        (ref `infix_row`))
      `(...1 3)`)
    (alt
      _
      ((ref `infix_rows`)
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((ref `infix_rows`)
        (tok `COMMENT`))
      `1`)
    (alt
      _
      ((ref `infix_row`))
      `(1)`))
  (rule
    (name `infix_row`)
    (alt
      _
      ((ref `infix_ops`))
      `(level ...1)`))
  (rule
    (name `infix_ops`)
    (alt
      _
      ((ref `infix_ops`)
        (lit `","`)
        (ref `infix_op`))
      `(...1 3)`)
    (alt
      _
      ((ref `infix_op`))
      `(1)`))
  (rule
    (name `infix_op`)
    (alt
      _
      ((tok `STRING`)
        (tok `KW_LEFT`))
      `(infix_op 1 2)`)
    (alt
      _
      ((tok `STRING`)
        (tok `KW_RIGHT`))
      `(infix_op 1 2)`)
    (alt
      _
      ((tok `STRING`)
        (tok `KW_NONE`))
      `(infix_op 1 2)`)
    (alt
      _
      ((tok `STRING`)
        (tok `IDENT`))
      `(infix_op 1 2)`))
  (rule
    (name `code_block`)
    (alt
      _
      ((tok `CODE_BLOCK`))
      `1`))
  (rule
    (name `production`)
    (alt
      _
      ((ref `rule_name`)
        (lit `"="`)
        (ref `alts`)
        (ref `prod_tail`))
      `(rule 1 ...3 ...4)`))
  (rule
    (name `alts`)
    (alt
      _
      ((ref `alts`)
        (lit `"|"`)
        (ref `alt_line`))
      `(...1 3)`)
    (alt
      _
      ((ref `alt_line`))
      `(1)`))
  (rule
    (name `prod_tail`)
    (alt
      _
      ((ref `prod_tail`)
        (tok `NEWLINE`)
        (lit `"|"`)
        (ref `alts`))
      `(...1 ...4)`)
    (alt
      _
      ((ref `prod_tail`)
        (tok `NEWLINE`)
        (tok `COMMENT`))
      `1`)
    (alt
      _
      ((ref `prod_tail`)
        (tok `NEWLINE`))
      `1`)
    (alt _ () `()`))
  (rule
    (name `rule_name`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"!"`))
      `(start 1)`)
    (alt
      _
      ((tok `IDENT`))
      `(name 1)`)
    (alt
      _
      ((tok `TOKEN`)
        (lit `"!"`))
      `(start 1)`)
    (alt
      _
      ((tok `TOKEN`))
      `(name 1)`))
  (rule
    (name `alt_line`)
    (alt
      _
      ((ref `elements`)
        (tok `ARROW`)
        (tok `ACTION_TEXT`))
      `(alt _      1 3)`)
    (alt
      _
      ((ref `elements`)
        (lit `"<"`)
        (tok `ARROW`)
        (tok `ACTION_TEXT`))
      `(alt reduce 1 4)`)
    (alt
      _
      ((ref `elements`)
        (lit `">"`)
        (tok `ARROW`)
        (tok `ACTION_TEXT`))
      `(alt shift  1 4)`)
    (alt
      _
      ((ref `elements`)
        (lit `"<"`))
      `(alt reduce 1)`)
    (alt
      _
      ((ref `elements`)
        (lit `">"`))
      `(alt shift  1)`)
    (alt
      _
      ((ref `elements`))
      `(alt _      1)`))
  (rule
    (name `elements`)
    (alt
      _
      ((ref `elements`)
        (ref `element`))
      `(...1 2)`)
    (alt _ () `()`))
  (rule
    (name `element`)
    (alt
      _
      ((ref `primary`)
        (ref `quantifier`))
      `(quantified 1 2)`)
    (alt
      _
      ((lit `"!"`)
        (ref `primary`)
        (ref `quantifier`))
      `(skip_q 2 3)`)
    (alt
      _
      ((lit `"!"`)
        (ref `primary`))
      `(skip 2)`)
    (alt
      _
      ((tok `KW_X`)
        (tok `STRING`))
      `(exclude 2)`)
    (alt
      _
      ((ref `primary`))))
  (rule
    (name `primary`)
    (alt
      _
      ((tok `IDENT`))
      `(ref 1)`)
    (alt
      _
      ((tok `TOKEN`)
        (lit `"("`)
        (ref `bracket_inner`)
        (lit `")"`))
      `(list_req 1 3)`)
    (alt
      _
      ((tok `TOKEN`))
      `(tok 1)`)
    (alt
      _
      ((tok `STRING`))
      `(lit 1)`)
    (alt
      _
      ((lit `"@"`)
        (tok `IDENT`))
      `(at_ref 2)`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_INFIX`))
      `(at_ref 2)`)
    (alt
      _
      ((lit `"("`)
        (ref `alt_group`)
        (lit `")"`))
      `(group _ ...2)`)
    (alt
      _
      ((lit `"["`)
        (ref `bracket_body`)
        (lit `"]"`))
      `2`))
  (rule
    (name `bracket_body`)
    (alt
      _
      ((ref `alt_group`)
        (lit `"..."`))
      `(group many ...1)`)
    (alt
      _
      ((ref `alt_group`))
      `(group opt  ...1)`))
  (rule
    (name `bracket_inner`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"?"`)
        (lit `","`)
        (ref `sep_term`))
      `(opt_items 1 4)`)
    (alt
      _
      ((tok `IDENT`)
        (lit `","`)
        (ref `sep_term`))
      `(sep_items 1 3)`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"?"`))
      `(opt_items_nosep 1)`)
    (alt
      _
      ((tok `IDENT`))
      `(plain 1)`))
  (rule
    (name `sep_term`)
    (alt
      _
      ((tok `STRING`))
      `(1)`)
    (alt
      _
      ((tok `TOKEN`))
      `(1)`))
  (rule
    (name `alt_group`)
    (alt
      _
      ((ref `alt_group`)
        (lit `"|"`)
        (ref `alt_elem`))
      `(...1 3)`)
    (alt
      _
      ((ref `alt_elem`))
      `(1)`))
  (rule
    (name `alt_elem`)
    (alt
      _
      ((ref `alt_elem`)
        (ref `element`))
      `(...1 2)`)
    (alt
      _
      ((ref `element`))
      `(1)`))
  (rule
    (name `quantifier`)
    (alt
      _
      ((lit `"?"`))
      `(opt)`)
    (alt
      _
      ((lit `"*"`))
      `(zero_plus)`)
    (alt
      _
      ((lit `"+"`))
      `(one_plus)`)))
