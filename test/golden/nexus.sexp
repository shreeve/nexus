(grammar
  (lang `"lang"`)
  (schema
    (kind_decl
      (kinds `grammar`)
      (roles
        (role rest `entries` _ _))
      _
      _)
    (kind_decl
      (kinds `lang`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `conflicts`)
      (roles
        (role
          _
          `count`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `manifest`)
      (roles
        (role
          rest
          `entries`
          (type `conflict`)
          _))
      _
      _)
    (kind_decl
      (kinds `conflict`)
      (roles
        (role
          _
          `kind`
          (type `leaf`)
          _)
        (role
          _
          `rule`
          (type `leaf`)
          _)
        (role
          _
          `over`
          (type `leaf`)
          opt)
        (role
          _
          `count`
          (type `leaf`)
          _)
        (role
          _
          `reason`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `as`)
      (roles
        (role
          _
          `token`
          (type `leaf`)
          _)
        (role
          _
          `via`
          (type `leaf`)
          opt)
        (role
          rest
          `groups`
          (type `as_entry`)
          _))
      _
      _)
    (kind_decl
      (kinds `as_entry`)
      (roles
        (role
          _
          `perm`
          (type
            (tagset `tag` `perm`))
          opt)
        (role
          _
          `group`
          (type `leaf`)
          _)
        (role
          _
          `via`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `op`)
      (roles
        (role
          rest
          `maps`
          (type `op_map`)
          _))
      _
      _)
    (kind_decl
      (kinds `op_map`)
      (roles
        (role
          _
          `lit`
          (type `leaf`)
          _)
        (role
          _
          `token`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `errors` `display`)
      (roles
        (role
          rest
          `pairs`
          (type `name_pair`)
          _))
      _
      _)
    (kind_decl
      (kinds `name_pair`)
      (roles
        (role
          _
          `key`
          (type `leaf`)
          _)
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `infix`)
      (roles
        (role
          _
          `base`
          (type `leaf`)
          _)
        (role
          rest
          `levels`
          (type `level`)
          _))
      _
      _)
    (kind_decl
      (kinds `level`)
      (roles
        (role
          rest
          `ops`
          (type `infix_op`)
          _))
      _
      _)
    (kind_decl
      (kinds `infix_op`)
      (roles
        (role
          _
          `op`
          (type `leaf`)
          _)
        (role
          _
          `assoc`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `schema`)
      (roles
        (role
          rest
          `decls`
          (type `kind_decl`)
          _))
      _
      _)
    (kind_decl
      (kinds `kind_decl`)
      (roles
        (role
          _
          `kinds`
          (type `kinds`)
          _)
        (role
          _
          `roles`
          (type `roles`)
          _)
        (role
          _
          `sides`
          (type `sides`)
          opt)
        (role
          _
          `wrapper`
          (type
            (tagset `tag` `wrapper`))
          opt))
      _
      _)
    (kind_decl
      (kinds `kinds` `sides`)
      (roles
        (role
          rest
          `names`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `roles`)
      (roles
        (role
          rest
          `roles`
          (type `role`)
          _))
      _
      _)
    (kind_decl
      (kinds `role`)
      (roles
        (role
          _
          `rest`
          (type
            (tagset `tag` `rest`))
          opt)
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `type`
          (type `type`)
          opt)
        (role
          _
          `opt`
          (type
            (tagset `tag` `opt`))
          opt))
      _
      _)
    (kind_decl
      (kinds `type`)
      (roles
        (role rest `atoms` _ _))
      _
      _)
    (kind_decl
      (kinds `tagset`)
      (roles
        (role
          _
          `tag`
          (type `leaf`)
          _)
        (role
          rest
          `values`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `tags` `trivia`)
      (roles
        (role
          rest
          `names`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `repair`)
      (roles
        (role
          rest
          `lines`
          (type `repair_line`)
          _))
      _
      _)
    (kind_decl
      (kinds `repair_line`)
      (roles
        (role
          _
          `class`
          (type `leaf`)
          _)
        (role
          rest
          `names`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `rule`)
      (roles
        (role
          _
          `name`
          (type `start` `name`)
          _)
        (role
          rest
          `alts`
          (type `alt`)
          _))
      _
      _)
    (kind_decl
      (kinds `start` `name`)
      (roles
        (role
          _
          `id`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `alt`)
      (roles
        (role
          _
          `hint`
          (type `leaf`)
          opt)
        (role
          _
          `elements`
          (type `group`)
          _)
        (role
          _
          `action`
          (type `pos` `null` `"node"` `list` `keep`)
          opt)
        (role
          _
          `optout`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `ref` `tok` `lit` `at_ref`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `list_req`)
      (roles
        (role
          _
          `keyword`
          (type `leaf`)
          _)
        (role
          _
          `inner`
          (type `plain` `opt_items_nosep` `sep_items` `opt_items`)
          _))
      _
      _)
    (kind_decl
      (kinds `plain` `opt_items_nosep`)
      (roles
        (role
          _
          `item`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `sep_items` `opt_items`)
      (roles
        (role
          _
          `item`
          (type `leaf`)
          _)
        (role
          _
          `sep`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `group`)
      (roles
        (role
          _
          `kind`
          (type
            (tagset `tag` `many` `opt`))
          opt)
        (role
          rest
          `bodies`
          (type `group`)
          _))
      _
      _)
    (kind_decl
      (kinds `quantified` `skip_q`)
      (roles
        (role _ `element` _ _)
        (role
          _
          `quant`
          (type `opt` `zero_plus` `one_plus`)
          _))
      _
      _)
    (kind_decl
      (kinds `skip`)
      (roles
        (role _ `element` _ _))
      _
      _)
    (kind_decl
      (kinds `exclude`)
      (roles
        (role
          _
          `char`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `label`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `element` _ _))
      _
      _)
    (kind_decl
      (kinds `opt` `zero_plus` `one_plus`)
      (roles)
      _
      _)
    (kind_decl
      (kinds `pos` `spread` `symid`)
      (roles
        (role
          _
          `n`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `null`)
      (roles)
      _
      _)
    (kind_decl
      (kinds `tag`)
      (roles
        (role
          _
          `word`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `named`)
      (roles
        (role
          _
          `role`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `node`)
      (roles
        (role
          _
          `head`
          (type `leaf`)
          _)
        (role rest `items` _ _))
      _
      _)
    (kind_decl
      (kinds `list`)
      (roles
        (role rest `items` _ _))
      _
      _)
    (kind_decl
      (kinds `keep`)
      (roles
        (role
          _
          `n`
          (type `leaf`)
          _)
        (role rest `items` _ _))
      _
      _))
  (rule
    (start `grammar`)
    (alt
      _
      ((ref `entries`))
      (node
        `grammar`
        (spread `1`))
      _)
    (alt
      _
      ()
      (node `grammar`)
      _))
  (rule
    (name `entries`)
    (alt
      _
      ((ref `entry`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `entries`)
        (tok `NEWLINE`)
        (ref `entry`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `entries`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `entry`)
    (alt
      _
      ((ref `directive`))
      _
      _)
    (alt
      _
      ((ref `production`))
      _
      _))
  (rule
    (name `directive`)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_LANG`)
        (lit `"="`)
        (label
          `name`
          (tok `STRING`)))
      (node `lang`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_CONFLICTS`)
        (lit `"="`)
        (label
          `count`
          (tok `INTEGER`)))
      (node `conflicts`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_CONFLICTS`)
        (label
          `entries`
          (ref `conflict_lines`)))
      (node `manifest`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_AS`)
        (ref `as_body`))
      (pos `3`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_OP`)
        (lit `"="`)
        (lit `"["`)
        (label
          `maps`
          (ref `op_items`))
        (lit `"]"`))
      (node `op`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_ERRORS`)
        (label
          `pairs`
          (ref `name_pairs`)))
      (node `errors`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_DISPLAY`)
        (label
          `pairs`
          (ref `name_pairs`)))
      (node `display`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_INFIX`)
        (label
          `base`
          (tok `IDENT`))
        (label
          `levels`
          (ref `infix_rows`)))
      (node `infix`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_SCHEMA`)
        (label
          `decls`
          (ref `schema_lines`)))
      (node `schema`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_TAGS`)
        (label
          `names`
          (ref `name_list`)))
      (node `tags`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_TRIVIA`)
        (label
          `names`
          (ref `name_list`)))
      (node `trivia`)
      _)
    (alt
      _
      ((lit `"@"`)
        (tok `KW_REPAIR`)
        (label
          `lines`
          (ref `repair_lines`)))
      (node `repair`)
      _))
  (rule
    (name `conflict_lines`)
    (alt
      _
      ((tok `CONT`)
        (ref `conflict_line`))
      (list
        (pos `2`))
      _)
    (alt
      _
      ((ref `conflict_lines`)
        (tok `CONT`)
        (ref `conflict_line`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `conflict_line`)
    (alt
      _
      ((label
          `kind`
          (tok `IDENT`))
        (label
          `rule`
          (tok `RULE_TEXT`))
        (group
          opt
          ((tok `KW_OVER`)
            (label
              `over`
              (tok `RULE_TEXT`))))
        (label
          `count`
          (tok `INTEGER`))
        (label
          `reason`
          (quantified
            (tok `COMMENT`)
            (opt))))
      (node `conflict`)
      _))
  (rule
    (name `as_body`)
    (alt
      _
      ((label
          `token`
          (group
            _
            ((tok `IDENT`))
            ((tok `TOKEN`))))
        (group
          opt
          ((tok `KW_VIA`)
            (label
              `via`
              (tok `IDENT`))))
        (lit `"="`)
        (lit `"["`)
        (label
          `groups`
          (ref `as_list`))
        (lit `"]"`))
      (node `as`)
      _))
  (rule
    (name `as_list`)
    (alt
      _
      ((ref `as_entry`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `as_list`)
        (lit `","`)
        (ref `as_entry`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `as_entry`)
    (alt
      _
      ((label
          `group`
          (tok `IDENT`))
        (group
          opt
          ((tok `KW_VIA`)
            (label
              `via`
              (tok `IDENT`)))))
      (node `as_entry`)
      _)
    (alt
      _
      ((label
          `group`
          (tok `IDENT`))
        (lit `"!"`)
        (group
          opt
          ((tok `KW_VIA`)
            (label
              `via`
              (tok `IDENT`)))))
      (node
        `as_entry`
        (named
          `perm`
          (tag `perm`)))
      _))
  (rule
    (name `op_items`)
    (alt
      _
      ((ref `op_item`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `op_items`)
        (ref `op_item`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `op_items`)
        (lit `","`))
      (pos `1`)
      _))
  (rule
    (name `op_item`)
    (alt
      _
      ((label
          `lit`
          (tok `STRING`))
        (tok `ARROW`)
        (label
          `token`
          (tok `STRING`)))
      (node `op_map`)
      _))
  (rule
    (name `name_pairs`)
    (alt
      _
      ((ref `pair_line`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `CONT`)
        (ref `pair_line`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `name_pairs`)
        (tok `CONT`)
        (ref `pair_line`))
      (list
        (spread `1`)
        (spread `3`))
      _))
  (rule
    (name `pair_line`)
    (alt
      _
      ((ref `name_pair`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `pair_line`)
        (lit `","`)
        (ref `name_pair`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `pair_line`)
        (lit `","`))
      (pos `1`)
      _))
  (rule
    (name `name_pair`)
    (alt
      _
      ((label
          `key`
          (tok `LABEL`))
        (label
          `name`
          (tok `STRING`)))
      (node `name_pair`)
      _)
    (alt
      _
      ((label
          `key`
          (tok `STRING`))
        (lit `":"`)
        (label
          `name`
          (tok `STRING`)))
      (node `name_pair`)
      _))
  (rule
    (name `infix_rows`)
    (alt
      _
      ((tok `CONT`)
        (ref `infix_row`))
      (list
        (pos `2`))
      _)
    (alt
      _
      ((ref `infix_rows`)
        (tok `CONT`)
        (ref `infix_row`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `infix_row`)
    (alt
      _
      ((label
          `ops`
          (ref `infix_ops`)))
      (node `level`)
      _))
  (rule
    (name `infix_ops`)
    (alt
      _
      ((ref `infix_op`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `infix_ops`)
        (lit `","`)
        (ref `infix_op`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `infix_op`)
    (alt
      _
      ((label
          `op`
          (tok `STRING`))
        (label
          `assoc`
          (group
            _
            ((tok `KW_LEFT`))
            ((tok `KW_RIGHT`))
            ((tok `KW_NONE`))
            ((tok `IDENT`)))))
      (node `infix_op`)
      _))
  (rule
    (name `schema_lines`)
    (alt
      _
      ((tok `CONT`)
        (ref `kind_decl`))
      (list
        (pos `2`))
      _)
    (alt
      _
      ((ref `schema_lines`)
        (tok `CONT`)
        (ref `kind_decl`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `kind_decl`)
    (alt
      _
      ((ref `kind_names`)
        (ref `role_list`))
      (node
        `kind_decl`
        (named
          `kinds`
          (node
            `kinds`
            (spread `1`)))
        (named
          `roles`
          (node
            `roles`
            (spread `2`))))
      _)
    (alt
      _
      ((ref `kind_names`)
        (ref `role_list`)
        (lit `"|"`)
        (ref `side_names`))
      (node
        `kind_decl`
        (named
          `kinds`
          (node
            `kinds`
            (spread `1`)))
        (named
          `roles`
          (node
            `roles`
            (spread `2`)))
        (named
          `sides`
          (node
            `sides`
            (spread `4`))))
      _)
    (alt
      _
      ((ref `kind_names`)
        (ref `role_list`)
        (lit `"@"`)
        (tok `KW_WRAPPER`))
      (node
        `kind_decl`
        (named
          `kinds`
          (node
            `kinds`
            (spread `1`)))
        (named
          `roles`
          (node
            `roles`
            (spread `2`)))
        (named
          `wrapper`
          (tag `wrapper`)))
      _)
    (alt
      _
      ((ref `kind_names`)
        (ref `role_list`)
        (lit `"|"`)
        (ref `side_names`)
        (lit `"@"`)
        (tok `KW_WRAPPER`))
      (node
        `kind_decl`
        (named
          `kinds`
          (node
            `kinds`
            (spread `1`)))
        (named
          `roles`
          (node
            `roles`
            (spread `2`)))
        (named
          `sides`
          (node
            `sides`
            (spread `4`)))
        (named
          `wrapper`
          (tag `wrapper`)))
      _))
  (rule
    (name `kind_names`)
    (alt
      _
      ((ref `kind_name`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `kind_names`)
        (lit `","`)
        (ref `kind_name`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `kind_name`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `STRING`))
      _
      _))
  (rule
    (name `role_list`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((ref `role_list`)
        (ref `role`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `role`)
    (alt
      _
      ((label
          `name`
          (tok `IDENT`)))
      (node `role`)
      _)
    (alt
      _
      ((label
          `name`
          (tok `IDENT`))
        (lit `"?"`))
      (node
        `role`
        (named
          `opt`
          (tag `opt`)))
      _)
    (alt
      _
      ((label
          `name`
          (tok `LABEL`))
        (label
          `type`
          (ref `role_type`)))
      (node `role`)
      _)
    (alt
      _
      ((label
          `name`
          (tok `LABEL`))
        (label
          `type`
          (ref `role_type`))
        (lit `"?"`))
      (node
        `role`
        (named
          `opt`
          (tag `opt`)))
      _)
    (alt
      _
      ((lit `"..."`)
        (label
          `name`
          (tok `IDENT`)))
      (node
        `role`
        (named
          `rest`
          (tag `rest`)))
      _)
    (alt
      _
      ((lit `"..."`)
        (label
          `name`
          (tok `LABEL`))
        (label
          `type`
          (ref `role_type`)))
      (node
        `role`
        (named
          `rest`
          (tag `rest`)))
      _))
  (rule
    (name `role_type`)
    (alt
      _
      ((ref `type_atoms`))
      (node
        `type`
        (spread `1`))
      _))
  (rule
    (name `type_atoms`)
    (alt
      _
      ((ref `type_atom`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `type_atoms`)
        (tok `UNION`)
        (ref `type_atom`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `type_atom`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `STRING`))
      _
      _)
    (alt
      _
      ((label
          `tag`
          (tok `IDENT`))
        (lit `"("`)
        (label
          `values`
          (ref `tag_values`))
        (lit `")"`))
      (node `tagset`)
      _))
  (rule
    (name `tag_values`)
    (alt
      _
      ((ref `tag_value`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `tag_values`)
        (tok `UNION`)
        (ref `tag_value`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `tag_value`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `STRING`))
      _
      _))
  (rule
    (name `side_names`)
    (alt
      _
      ((tok `IDENT`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `side_names`)
        (tok `IDENT`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `name_list`)
    (alt
      _
      ((ref `name_items`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `CONT`)
        (ref `name_items`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `name_list`)
        (tok `CONT`)
        (ref `name_items`))
      (list
        (spread `1`)
        (spread `3`))
      _))
  (rule
    (name `name_items`)
    (alt
      _
      ((ref `name_item`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `name_items`)
        (ref `name_item`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `name_item`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `TOKEN`))
      _
      _)
    (alt
      _
      ((tok `STRING`))
      _
      _))
  (rule
    (name `repair_lines`)
    (alt
      _
      ((tok `CONT`)
        (ref `repair_line`))
      (list
        (pos `2`))
      _)
    (alt
      _
      ((ref `repair_lines`)
        (tok `CONT`)
        (ref `repair_line`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `repair_line`)
    (alt
      _
      ((label
          `class`
          (tok `IDENT`))
        (label
          `names`
          (ref `name_items`)))
      (node `repair_line`)
      _))
  (rule
    (name `production`)
    (alt
      _
      ((label
          `name`
          (ref `rule_name`))
        (lit `"="`)
        (label
          `alts`
          (ref `alts`)))
      (node `rule`)
      _))
  (rule
    (name `rule_name`)
    (alt
      _
      ((label
          `id`
          (group
            _
            ((tok `IDENT`))
            ((tok `TOKEN`))))
        (lit `"!"`))
      (node `start`)
      _)
    (alt
      _
      ((label
          `id`
          (group
            _
            ((tok `IDENT`))
            ((tok `TOKEN`)))))
      (node `name`)
      _))
  (rule
    (name `alts`)
    (alt
      _
      ((ref `alt_line`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `alts`)
        (lit `"|"`)
        (ref `alt_line`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `alts`)
        (tok `NEXT_ALT`)
        (ref `alt_line`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `alt_line`)
    (alt
      _
      ((label
          `elements`
          (ref `elements`))
        (label
          `hint`
          (quantified
            (group
              _
              ((lit `"<"`))
              ((lit `">"`)))
            (opt)))
        (group
          opt
          ((tok `ARROW`)
            (label
              `action`
              (ref `action`)))))
      (node `alt`)
      _)
    (alt
      _
      ((label
          `elements`
          (ref `elements`))
        (label
          `hint`
          (quantified
            (group
              _
              ((lit `"<"`))
              ((lit `">"`)))
            (opt)))
        (tok `ARROW`)
        (label
          `action`
          (ref `action`))
        (lit `"~"`)
        (label
          `optout`
          (tok `STRING`)))
      (node `alt`)
      _))
  (rule
    (name `elements`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((ref `elements`)
        (ref `element`))
      (list
        (spread `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `elements`)
        (tok `CONT`))
      (pos `1`)
      _))
  (rule
    (name `element`)
    (alt
      _
      ((label
          `name`
          (tok `LABEL`))
        (label
          `element`
          (ref `labelable`)))
      (node `label`)
      _)
    (alt
      _
      ((label
          `element`
          (ref `group_paren`))
        (lit `":"`)
        (label
          `name`
          (tok `IDENT`)))
      (node `label`)
      _)
    (alt
      _
      ((ref `labelable`))
      _
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `element`
          (ref `primary`))
        (label
          `quant`
          (ref `quantifier`)))
      (node `skip_q`)
      _)
    (alt
      _
      ((lit `"!"`)
        (label
          `element`
          (ref `primary`)))
      (node `skip`)
      _)
    (alt
      _
      ((tok `KW_X`)
        (label
          `char`
          (tok `STRING`)))
      (node `exclude`)
      _))
  (rule
    (name `labelable`)
    (alt
      _
      ((label
          `element`
          (ref `primary`))
        (label
          `quant`
          (ref `quantifier`)))
      (node `quantified`)
      _)
    (alt
      _
      ((ref `primary`))
      _
      _))
  (rule
    (name `primary`)
    (alt
      _
      ((label
          `name`
          (tok `IDENT`)))
      (node `ref`)
      _)
    (alt
      _
      ((label
          `name`
          (tok `TOKEN`)))
      (node `tok`)
      _)
    (alt
      _
      ((label
          `name`
          (tok `STRING`)))
      (node `lit`)
      _)
    (alt
      _
      ((label
          `keyword`
          (tok `KW_LIST`))
        (lit `"("`)
        (label
          `inner`
          (ref `list_inner`))
        (lit `")"`))
      (node `list_req`)
      _)
    (alt
      _
      ((lit `"@"`)
        (label
          `name`
          (group
            _
            ((tok `IDENT`))
            ((tok `KW_INFIX`)))))
      (node `at_ref`)
      _)
    (alt
      _
      ((ref `group_paren`))
      _
      _)
    (alt
      _
      ((lit `"["`)
        (ref `bracket_body`)
        (lit `"]"`))
      (pos `2`)
      _))
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
        (spread `2`))
      _))
  (rule
    (name `bracket_body`)
    (alt
      _
      ((ref `alt_group`)
        (lit `"..."`))
      (node
        `group`
        (tag `many`)
        (spread `1`))
      _)
    (alt
      _
      ((ref `alt_group`)
        (lit `","`)
        (lit `"..."`))
      (node
        `group`
        (tag `many`)
        (spread `1`))
      _)
    (alt
      _
      ((ref `alt_group`))
      (node
        `group`
        (tag `opt`)
        (spread `1`))
      _))
  (rule
    (name `list_inner`)
    (alt
      _
      ((label
          `item`
          (ref `list_item`)))
      (node `plain`)
      _)
    (alt
      _
      ((label
          `item`
          (ref `list_item`))
        (lit `"?"`))
      (node `opt_items_nosep`)
      _)
    (alt
      _
      ((label
          `item`
          (ref `list_item`))
        (lit `","`)
        (label
          `sep`
          (ref `sep_term`)))
      (node `sep_items`)
      _)
    (alt
      _
      ((label
          `item`
          (ref `list_item`))
        (lit `"?"`)
        (lit `","`)
        (label
          `sep`
          (ref `sep_term`)))
      (node `opt_items`)
      _))
  (rule
    (name `list_item`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `TOKEN`))
      _
      _))
  (rule
    (name `sep_term`)
    (alt
      _
      ((tok `STRING`))
      _
      _)
    (alt
      _
      ((tok `TOKEN`))
      _
      _))
  (rule
    (name `alt_group`)
    (alt
      _
      ((ref `alt_elem`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `alt_group`)
        (lit `"|"`)
        (ref `alt_elem`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `alt_elem`)
    (alt
      _
      ((ref `element`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `alt_elem`)
        (ref `element`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `quantifier`)
    (alt
      _
      ((lit `"?"`))
      (node `opt`)
      _)
    (alt
      _
      ((lit `"*"`))
      (node `zero_plus`)
      _)
    (alt
      _
      ((lit `"+"`))
      (node `one_plus`)
      _))
  (rule
    (name `action`)
    (alt
      _
      ((label
          `n`
          (tok `INTEGER`)))
      (node `pos`)
      _)
    (alt
      _
      ((tok `KW_NIL`))
      (node `null`)
      _)
    (alt
      _
      ((ref `sexp`))
      _
      _))
  (rule
    (name `sexp`)
    (alt
      _
      ((lit `"("`)
        (label
          `head`
          (tok `WORD`))
        (label
          `items`
          (ref `items`))
        (lit `")"`))
      (node `node`)
      _)
    (alt
      _
      ((lit `"("`)
        (lit `"!"`)
        (label
          `n`
          (tok `INTEGER`))
        (label
          `items`
          (ref `items`))
        (lit `")"`))
      (node `keep`)
      _)
    (alt
      _
      ((lit `"("`)
        (ref `items_nohead`)
        (lit `")"`))
      (node
        `list`
        (spread `2`))
      _))
  (rule
    (name `items_nohead`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((ref `first_item`)
        (ref `items`))
      (list
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `items`)
    (alt
      _
      ()
      (list)
      _)
    (alt
      _
      ((ref `items`)
        (ref `item`))
      (list
        (spread `1`)
        (pos `2`))
      _))
  (rule
    (name `first_item`)
    (alt
      _
      ((label
          `role`
          (tok `LABEL`))
        (label
          `value`
          (ref `value`)))
      (node `named`)
      _)
    (alt
      _
      ((ref `plain_value`))
      _
      _))
  (rule
    (name `item`)
    (alt
      _
      ((label
          `role`
          (tok `LABEL`))
        (label
          `value`
          (ref `value`)))
      (node `named`)
      _)
    (alt
      _
      ((ref `value`))
      _
      _))
  (rule
    (name `value`)
    (alt
      _
      ((ref `plain_value`))
      _
      _)
    (alt
      _
      ((label
          `word`
          (tok `WORD`)))
      (node `tag`)
      _))
  (rule
    (name `plain_value`)
    (alt
      _
      ((label
          `n`
          (tok `INTEGER`)))
      (node `pos`)
      _)
    (alt
      _
      ((lit `"..."`)
        (label
          `n`
          (tok `INTEGER`)))
      (node `spread`)
      _)
    (alt
      _
      ((lit `"~"`)
        (label
          `n`
          (tok `INTEGER`)))
      (node `symid`)
      _)
    (alt
      _
      ((tok `KW_NIL`))
      (node `null`)
      _)
    (alt
      _
      ((ref `sexp`))
      _
      _)))
