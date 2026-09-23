(grammar
  (lang `"lang"`)
  (conflicts `0`)
  (rule
    (start `grammar`)
    (alt
      _
      ((ref `body`))
      (pos `1`)))
  (rule
    (name `body`)
    (alt
      _
      ((ref `entries`))
      (node
        `grammar`
        (spread `1`)))
    (alt
      _
      ()
      (node `grammar`)))
  (rule
    (name `entries`)
    (alt
      _
      ((ref `entry`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `entries`)
        (tok `NEWLINE`)
        (ref `entry`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `entries`)
        (tok `NEWLINE`))
      (pos `1`)))
  (rule
    (name `entry`)
    (alt
      _
      ((ref `directive`)))
    (alt
      _
      ((ref `production`))))
  (rule
    (name `directive`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_LANG`)
        (lit `"="`)
        (tok `STRING`))
      (node
        `lang`
        (pos `4`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_CONFLICTS`)
        (lit `"="`)
        (tok `INTEGER`))
      (node
        `conflicts`
        (pos `4`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_CONFLICTS`)
        (ref `conflict_lines`))
      (node
        `manifest`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_AS`)
        (ref `as_body`))
      (node
        `as`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_OP`)
        (lit `"="`)
        (lit `"["`)
        (ref `op_items`)
        (lit `"]"`))
      (node
        `op`
        (spread `5`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_ERRORS`)
        (ref `name_pairs`))
      (node
        `errors`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_DISPLAY`)
        (ref `name_pairs`))
      (node
        `display`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_INFIX`)
        (tok `IDENT`)
        (ref `infix_rows`))
      (node
        `infix`
        (pos `3`)
        (spread `4`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_SCHEMA`)
        (ref `schema_lines`))
      (node
        `schema`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_TAGS`)
        (ref `name_list`))
      (node
        `tags`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_TRIVIA`)
        (ref `name_list`))
      (node
        `trivia`
        (spread `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_REPAIR`)
        (ref `repair_lines`))
      (node
        `repair`
        (spread `3`))))
  (rule
    (name `conflict_lines`)
    (alt
      _
      ((tok `CONT`)
        (ref `conflict_line`))
      (list
        (pos `2`)))
    (alt
      _
      ((ref `conflict_lines`)
        (tok `CONT`)
        (ref `conflict_line`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `conflict_line`)
    (alt
      _
      ((tok `IDENT`)
        (ref `crule`)
        (tok `INTEGER`)
        (tok `COMMENT`))
      (node
        `conflict`
        (pos `1`)
        (pos `2`)
        (null)
        (pos `3`)
        (pos `4`)))
    (alt
      _
      ((tok `IDENT`)
        (ref `crule`)
        (tok `INTEGER`))
      (node
        `conflict`
        (pos `1`)
        (pos `2`)
        (null)
        (pos `3`)))
    (alt
      _
      ((tok `IDENT`)
        (ref `crule`)
        (tok `KW_OVER`)
        (ref `crule`)
        (tok `INTEGER`)
        (tok `COMMENT`))
      (node
        `conflict`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`)
        (pos `6`)))
    (alt
      _
      ((tok `IDENT`)
        (ref `crule`)
        (tok `KW_OVER`)
        (ref `crule`)
        (tok `INTEGER`))
      (node
        `conflict`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (pos `5`))))
  (rule
    (name `crule`)
    (alt
      _
      ((tok `IDENT`)
        (tok `ARROW`)
        (ref `csyms`))
      (node
        `crule`
        (pos `1`)
        (spread `3`))))
  (rule
    (name `csyms`)
    (alt
      _
      ((ref `csym`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `csyms`)
        (ref `csym`))
      (list
        (spread `1`)
        (pos `2`))))
  (rule
    (name `csym`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `TOKEN`)))
    (alt
      _
      ((tok `STRING`)))
    (alt
      _
      ((tok `EPSILON`))))
  (rule
    (name `as_body`)
    (alt
      _
      ((ref `as_token`)
        (lit `"="`)
        (lit `"["`)
        (ref `as_list`)
        (lit `"]"`))
      (list
        (pos `1`)
        (null)
        (spread `4`)))
    (alt
      _
      ((ref `as_token`)
        (tok `KW_VIA`)
        (tok `IDENT`)
        (lit `"="`)
        (lit `"["`)
        (ref `as_list`)
        (lit `"]"`))
      (list
        (pos `1`)
        (pos `3`)
        (spread `6`))))
  (rule
    (name `as_token`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `TOKEN`))))
  (rule
    (name `as_list`)
    (alt
      _
      ((ref `as_entry`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `as_list`)
        (lit `","`)
        (ref `as_entry`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `as_entry`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"!"`))
      (node
        `as_entry`
        (tag `perm`)
        (pos `1`)))
    (alt
      _
      ((tok `IDENT`))
      (node
        `as_entry`
        (null)
        (pos `1`)))
    (alt
      _
      ((tok `IDENT`)
        (lit `"!"`)
        (tok `KW_VIA`)
        (tok `IDENT`))
      (node
        `as_entry`
        (tag `perm`)
        (pos `1`)
        (pos `4`)))
    (alt
      _
      ((tok `IDENT`)
        (tok `KW_VIA`)
        (tok `IDENT`))
      (node
        `as_entry`
        (null)
        (pos `1`)
        (pos `3`))))
  (rule
    (name `op_items`)
    (alt
      _
      ((ref `op_item`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `op_items`)
        (ref `op_item`))
      (list
        (spread `1`)
        (pos `2`)))
    (alt
      _
      ((ref `op_items`)
        (lit `","`))
      (pos `1`)))
  (rule
    (name `op_item`)
    (alt
      _
      ((tok `STRING`)
        (tok `ARROW`)
        (tok `STRING`))
      (node
        `op_map`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `name_pairs`)
    (alt
      _
      ((ref `pair_line`))
      (pos `1`))
    (alt
      _
      ((tok `CONT`)
        (ref `pair_line`))
      (pos `2`))
    (alt
      _
      ((ref `name_pairs`)
        (tok `CONT`)
        (ref `pair_line`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `pair_line`)
    (alt
      _
      ((ref `name_pair`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `pair_line`)
        (lit `","`)
        (ref `name_pair`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `pair_line`)
        (lit `","`))
      (pos `1`)))
  (rule
    (name `name_pair`)
    (alt
      _
      ((tok `LABEL`)
        (tok `STRING`))
      (node
        `name_pair`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `STRING`)
        (lit `":"`)
        (tok `STRING`))
      (node
        `name_pair`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `infix_rows`)
    (alt
      _
      ((tok `CONT`)
        (ref `infix_row`))
      (list
        (pos `2`)))
    (alt
      _
      ((ref `infix_rows`)
        (tok `CONT`)
        (ref `infix_row`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `infix_row`)
    (alt
      _
      ((ref `infix_ops`))
      (node
        `level`
        (spread `1`))))
  (rule
    (name `infix_ops`)
    (alt
      _
      ((ref `infix_op`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `infix_ops`)
        (lit `","`)
        (ref `infix_op`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `infix_op`)
    (alt
      _
      ((tok `STRING`)
        (tok `KW_LEFT`))
      (node
        `infix_op`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `STRING`)
        (tok `KW_RIGHT`))
      (node
        `infix_op`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `STRING`)
        (tok `KW_NONE`))
      (node
        `infix_op`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `STRING`)
        (tok `IDENT`))
      (node
        `infix_op`
        (pos `1`)
        (pos `2`))))
  (rule
    (name `schema_lines`)
    (alt
      _
      ((tok `CONT`)
        (ref `kind_decl`))
      (list
        (pos `2`)))
    (alt
      _
      ((ref `schema_lines`)
        (tok `CONT`)
        (ref `kind_decl`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `kind_decl`)
    (alt
      _
      ((ref `kind_names`)
        (ref `roles`))
      (node
        `kind_decl`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((ref `kind_names`)
        (ref `roles`)
        (lit `"|"`)
        (ref `side_names`))
      (node
        `kind_decl`
        (pos `1`)
        (pos `2`)
        (pos `4`)))
    (alt
      _
      ((ref `kind_names`)
        (ref `roles`)
        (lit `"@"`)
        (tok `KW_WRAPPER`))
      (node
        `kind_decl`
        (pos `1`)
        (pos `2`)
        (null)
        (tag `wrapper`)))
    (alt
      _
      ((ref `kind_names`)
        (ref `roles`)
        (lit `"|"`)
        (ref `side_names`)
        (lit `"@"`)
        (tok `KW_WRAPPER`))
      (node
        `kind_decl`
        (pos `1`)
        (pos `2`)
        (pos `4`)
        (tag `wrapper`))))
  (rule
    (name `kind_names`)
    (alt
      _
      ((ref `kind_name`))
      (node
        `kinds`
        (pos `1`)))
    (alt
      _
      ((ref `kind_names`)
        (lit `","`)
        (ref `kind_name`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `kind_name`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `STRING`))))
  (rule
    (name `roles`)
    (alt
      _
      ()
      (node `roles`))
    (alt
      _
      ((ref `roles`)
        (ref `role`))
      (list
        (spread `1`)
        (pos `2`))))
  (rule
    (name `role`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `role`
        (null)
        (pos `1`)))
    (alt
      _
      ((tok `IDENT`)
        (lit `"?"`))
      (node
        `role`
        (null)
        (pos `1`)
        (null)
        (tag `opt`)))
    (alt
      _
      ((tok `LABEL`)
        (ref `role_type`))
      (node
        `role`
        (null)
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `LABEL`)
        (ref `role_type`)
        (lit `"?"`))
      (node
        `role`
        (null)
        (pos `1`)
        (pos `2`)
        (tag `opt`)))
    (alt
      _
      ((lit `"..."`)
        (tok `IDENT`))
      (node
        `role`
        (tag `rest`)
        (pos `2`)))
    (alt
      _
      ((lit `"..."`)
        (tok `LABEL`)
        (ref `role_type`))
      (node
        `role`
        (tag `rest`)
        (pos `2`)
        (pos `3`))))
  (rule
    (name `role_type`)
    (alt
      _
      ((ref `type_atom`))
      (node
        `type`
        (pos `1`)))
    (alt
      _
      ((ref `role_type`)
        (tok `UNION`)
        (ref `type_atom`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `type_atom`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `STRING`)))
    (alt
      _
      ((tok `IDENT`)
        (lit `"("`)
        (ref `tag_values`)
        (lit `")"`))
      (node
        `tagset`
        (pos `1`)
        (spread `3`))))
  (rule
    (name `tag_values`)
    (alt
      _
      ((ref `tag_value`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `tag_values`)
        (tok `UNION`)
        (ref `tag_value`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `tag_value`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `STRING`))))
  (rule
    (name `side_names`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `sides`
        (pos `1`)))
    (alt
      _
      ((ref `side_names`)
        (tok `IDENT`))
      (list
        (spread `1`)
        (pos `2`))))
  (rule
    (name `name_list`)
    (alt
      _
      ((ref `name_items`))
      (pos `1`))
    (alt
      _
      ((tok `CONT`)
        (ref `name_items`))
      (pos `2`))
    (alt
      _
      ((ref `name_list`)
        (tok `CONT`)
        (ref `name_items`))
      (list
        (spread `1`)
        (spread `3`))))
  (rule
    (name `name_items`)
    (alt
      _
      ((ref `name_item`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `name_items`)
        (ref `name_item`))
      (list
        (spread `1`)
        (pos `2`))))
  (rule
    (name `name_item`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `TOKEN`)))
    (alt
      _
      ((tok `STRING`))))
  (rule
    (name `repair_lines`)
    (alt
      _
      ((tok `CONT`)
        (ref `repair_line`))
      (list
        (pos `2`)))
    (alt
      _
      ((ref `repair_lines`)
        (tok `CONT`)
        (ref `repair_line`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `repair_line`)
    (alt
      _
      ((tok `IDENT`)
        (ref `name_items`))
      (node
        `repair_line`
        (pos `1`)
        (spread `2`))))
  (rule
    (name `production`)
    (alt
      _
      ((ref `rule_name`)
        (lit `"="`)
        (ref `alts`))
      (node
        `rule`
        (pos `1`)
        (spread `3`))))
  (rule
    (name `rule_name`)
    (alt
      _
      ((tok `IDENT`)
        (lit `"!"`))
      (node
        `start`
        (pos `1`)))
    (alt
      _
      ((tok `IDENT`))
      (node
        `name`
        (pos `1`)))
    (alt
      _
      ((tok `TOKEN`)
        (lit `"!"`))
      (node
        `start`
        (pos `1`)))
    (alt
      _
      ((tok `TOKEN`))
      (node
        `name`
        (pos `1`))))
  (rule
    (name `alts`)
    (alt
      _
      ((ref `alt_line`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `alts`)
        (lit `"|"`)
        (ref `alt_line`))
      (list
        (spread `1`)
        (pos `3`)))
    (alt
      _
      ((ref `alts`)
        (tok `NEXT_ALT`)
        (ref `alt_line`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `alt_line`)
    (alt
      _
      ((ref `elements`))
      (node
        `alt`
        (null)
        (pos `1`)))
    (alt
      _
      ((ref `elements`)
        (lit `"<"`))
      (node
        `alt`
        (tag `reduce`)
        (pos `1`)))
    (alt
      _
      ((ref `elements`)
        (lit `">"`))
      (node
        `alt`
        (tag `shift`)
        (pos `1`)))
    (alt
      _
      ((ref `elements`)
        (tok `ARROW`)
        (ref `action`))
      (node
        `alt`
        (null)
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `elements`)
        (lit `"<"`)
        (tok `ARROW`)
        (ref `action`))
      (node
        `alt`
        (tag `reduce`)
        (pos `1`)
        (pos `4`)))
    (alt
      _
      ((ref `elements`)
        (lit `">"`)
        (tok `ARROW`)
        (ref `action`))
      (node
        `alt`
        (tag `shift`)
        (pos `1`)
        (pos `4`)))
    (alt
      _
      ((ref `elements`)
        (tok `ARROW`)
        (ref `action`)
        (lit `"~"`)
        (tok `STRING`))
      (node
        `alt`
        (null)
        (pos `1`)
        (pos `3`)
        (pos `5`)))
    (alt
      _
      ((ref `elements`)
        (lit `"<"`)
        (tok `ARROW`)
        (ref `action`)
        (lit `"~"`)
        (tok `STRING`))
      (node
        `alt`
        (tag `reduce`)
        (pos `1`)
        (pos `4`)
        (pos `6`)))
    (alt
      _
      ((ref `elements`)
        (lit `">"`)
        (tok `ARROW`)
        (ref `action`)
        (lit `"~"`)
        (tok `STRING`))
      (node
        `alt`
        (tag `shift`)
        (pos `1`)
        (pos `4`)
        (pos `6`))))
  (rule
    (name `elements`)
    (alt
      _
      ()
      (list))
    (alt
      _
      ((ref `elements`)
        (ref `element`))
      (list
        (spread `1`)
        (pos `2`)))
    (alt
      _
      ((ref `elements`)
        (tok `CONT`))
      (pos `1`)))
  (rule
    (name `element`)
    (alt
      _
      ((tok `LABEL`)
        (ref `labelable`))
      (node
        `label`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((ref `group_paren`)
        (lit `":"`)
        (tok `IDENT`))
      (node
        `label`
        (pos `3`)
        (pos `1`)))
    (alt
      _
      ((ref `labelable`)))
    (alt
      _
      ((lit `"!"`)
        (ref `primary`)
        (ref `quantifier`))
      (node
        `skip_q`
        (pos `2`)
        (pos `3`)))
    (alt
      _
      ((lit `"!"`)
        (ref `primary`))
      (node
        `skip`
        (pos `2`)))
    (alt
      _
      ((tok `KW_X`)
        (tok `STRING`))
      (node
        `exclude`
        (pos `2`))))
  (rule
    (name `labelable`)
    (alt
      _
      ((ref `primary`)
        (ref `quantifier`))
      (node
        `quantified`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((ref `primary`))))
  (rule
    (name `primary`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `ref`
        (pos `1`)))
    (alt
      _
      ((tok `TOKEN`))
      (node
        `tok`
        (pos `1`)))
    (alt
      _
      ((tok `STRING`))
      (node
        `lit`
        (pos `1`)))
    (alt
      _
      ((tok `KW_LIST`)
        (lit `"("`)
        (ref `list_inner`)
        (lit `")"`))
      (node
        `list_req`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((lit `"@"`)
        (tok `IDENT`))
      (node
        `at_ref`
        (pos `2`)))
    (alt
      _
      ((lit `"@"`)
        (tok `KW_INFIX`))
      (node
        `at_ref`
        (pos `2`)))
    (alt
      _
      ((ref `group_paren`)))
    (alt
      _
      ((lit `"["`)
        (ref `bracket_body`)
        (lit `"]"`))
      (pos `2`)))
  (rule
    (name `group_paren`)
    (alt
      _
      ((lit `"("`)
        (ref `alt_group`)
        (lit `")"`))
      (node
        `group`
        (null)
        (spread `2`))))
  (rule
    (name `bracket_body`)
    (alt
      _
      ((ref `alt_group`)
        (lit `"..."`))
      (node
        `group`
        (tag `many`)
        (spread `1`)))
    (alt
      _
      ((ref `alt_group`)
        (lit `","`)
        (lit `"..."`))
      (node
        `group`
        (tag `many`)
        (spread `1`)))
    (alt
      _
      ((ref `alt_group`))
      (node
        `group`
        (tag `opt`)
        (spread `1`))))
  (rule
    (name `list_inner`)
    (alt
      _
      ((ref `list_item`))
      (node
        `plain`
        (pos `1`)))
    (alt
      _
      ((ref `list_item`)
        (lit `"?"`))
      (node
        `opt_items_nosep`
        (pos `1`)))
    (alt
      _
      ((ref `list_item`)
        (lit `","`)
        (ref `sep_term`))
      (node
        `sep_items`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `list_item`)
        (lit `"?"`)
        (lit `","`)
        (ref `sep_term`))
      (node
        `opt_items`
        (pos `1`)
        (pos `4`))))
  (rule
    (name `list_item`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `TOKEN`))))
  (rule
    (name `sep_term`)
    (alt
      _
      ((tok `STRING`)))
    (alt
      _
      ((tok `TOKEN`))))
  (rule
    (name `alt_group`)
    (alt
      _
      ((ref `alt_elem`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `alt_group`)
        (lit `"|"`)
        (ref `alt_elem`))
      (list
        (spread `1`)
        (pos `3`))))
  (rule
    (name `alt_elem`)
    (alt
      _
      ((ref `element`))
      (list
        (pos `1`)))
    (alt
      _
      ((ref `alt_elem`)
        (ref `element`))
      (list
        (spread `1`)
        (pos `2`))))
  (rule
    (name `quantifier`)
    (alt
      _
      ((lit `"?"`))
      (node `opt`))
    (alt
      _
      ((lit `"*"`))
      (node `zero_plus`))
    (alt
      _
      ((lit `"+"`))
      (node `one_plus`)))
  (rule
    (name `action`)
    (alt
      _
      ((tok `INTEGER`))
      (node
        `pos`
        (pos `1`)))
    (alt
      _
      ((tok `KW_NIL`))
      (node `null`))
    (alt
      _
      ((ref `sexp`))))
  (rule
    (name `sexp`)
    (alt
      _
      ((lit `"("`)
        (tok `WORD`)
        (ref `items`)
        (lit `")"`))
      (node
        `node`
        (pos `2`)
        (spread `3`)))
    (alt
      _
      ((lit `"("`)
        (lit `"!"`)
        (tok `INTEGER`)
        (ref `items`)
        (lit `")"`))
      (node
        `keep`
        (pos `3`)
        (spread `4`)))
    (alt
      _
      ((lit `"("`)
        (ref `items_nohead`)
        (lit `")"`))
      (node
        `list`
        (spread `2`))))
  (rule
    (name `items_nohead`)
    (alt
      _
      ()
      (list))
    (alt
      _
      ((ref `first_item`)
        (ref `items`))
      (list
        (pos `1`)
        (spread `2`))))
  (rule
    (name `items`)
    (alt
      _
      ()
      (list))
    (alt
      _
      ((ref `items`)
        (ref `item`))
      (list
        (spread `1`)
        (pos `2`))))
  (rule
    (name `first_item`)
    (alt
      _
      ((tok `LABEL`)
        (ref `value`))
      (node
        `named`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((ref `plain_value`))))
  (rule
    (name `item`)
    (alt
      _
      ((tok `LABEL`)
        (ref `value`))
      (node
        `named`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((ref `value`))))
  (rule
    (name `value`)
    (alt
      _
      ((ref `plain_value`)))
    (alt
      _
      ((tok `WORD`))
      (node
        `tag`
        (pos `1`))))
  (rule
    (name `plain_value`)
    (alt
      _
      ((tok `INTEGER`))
      (node
        `pos`
        (pos `1`)))
    (alt
      _
      ((lit `"..."`)
        (tok `INTEGER`))
      (node
        `spread`
        (pos `2`)))
    (alt
      _
      ((lit `"~"`)
        (tok `INTEGER`))
      (node
        `symid`
        (pos `2`)))
    (alt
      _
      ((tok `KW_NIL`))
      (node `null`))
    (alt
      _
      ((ref `sexp`)))))
