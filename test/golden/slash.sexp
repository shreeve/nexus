(grammar
  (lang `"slash"`)
  (conflicts `0`)
  (as
    `ident`
    _
    (as_entry perm `keyword`))
  (rule
    (start `program`)
    (alt
      _
      ((ref `sequence`))
      (pos `1`)))
  (rule
    (name `sequence`)
    (alt
      _
      ((ref `sequence_item`)
        (quantified
          (ref `sequence_tail`)
          (zero_plus)))
      (node
        `sequence`
        (pos `1`)
        (spread `2`))))
  (rule
    (name `sequence_item`)
    (alt
      _
      ((ref `pipeline`)))
    (alt
      _
      ((ref `conditional`)))
    (alt
      _
      ((ref `while_loop`)))
    (alt
      _
      ((ref `for_loop`)))
    (alt
      _
      ((ref `match_stmt`)))
    (alt
      _
      ((ref `block_stmt`)))
    (alt
      _
      ((ref `assigns`)))
    (alt
      _
      ((ref `cmd_def`)))
    (alt
      _
      ((ref `str_def`))))
  (rule
    (name `sequence_tail`)
    (alt
      _
      ((tok `SEMI`)
        (ref `sequence_item`))
      (node
        `seq_always`
        (pos `2`)))
    (alt
      _
      ((tok `SEMI`))
      (node
        `seq_always`
        (null)))
    (alt
      _
      ((tok `AND_AND`)
        (ref `sequence_item`))
      (node
        `seq_and`
        (pos `2`)))
    (alt
      _
      ((tok `OR_OR`)
        (ref `sequence_item`))
      (node
        `seq_or`
        (pos `2`)))
    (alt
      _
      ((tok `AMP`)
        (ref `sequence_item`))
      (node
        `seq_bg`
        (pos `2`)))
    (alt
      _
      ((tok `AMP`))
      (node
        `seq_bg`
        (null))))
  (rule
    (name `pipeline`)
    (alt
      _
      ((ref `stage`))
      (pos `1`))
    (alt
      _
      ((ref `stage`)
        (quantified
          (ref `pipe_tail`)
          (one_plus)))
      (node
        `pipeline`
        (pos `1`)
        (spread `2`))))
  (rule
    (name `pipe_tail`)
    (alt
      _
      ((tok `PIPE`)
        (ref `stage`))
      (pos `2`)))
  (rule
    (name `stage`)
    (alt
      _
      ((ref `simple_command`)))
    (alt
      _
      ((ref `subshell`))))
  (rule
    (name `subshell`)
    (alt
      _
      ((tok `LPAREN`)
        (ref `sequence`)
        (tok `RPAREN`)
        (quantified
          (ref `redirect_list`)
          (opt)))
      (node
        `subshell`
        (pos `2`)
        (pos `4`))))
  (rule
    (name `block_stmt`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `sequence`)
        (tok `RBRACE`)
        (quantified
          (ref `redirect_list`)
          (opt)))
      (node
        `block`
        (pos `2`)
        (pos `4`))))
  (rule
    (name `redirect_list`)
    (alt
      _
      ((quantified
          (ref `redirect`)
          (one_plus)))
      (node
        `redirects`
        (spread `1`))))
  (rule
    (name `simple_command`)
    (alt
      _
      ((ref `leading_word`)
        (quantified
          (ref `part`)
          (zero_plus)))
      (node
        `command`
        (null)
        (pos `1`)
        (spread `2`)))
    (alt
      _
      ((ref `env_prefix_list`)
        (ref `leading_word`)
        (quantified
          (ref `part`)
          (zero_plus)))
      (node
        `command`
        (pos `1`)
        (pos `2`)
        (spread `3`))))
  (rule
    (name `env_prefix_list`)
    (alt
      _
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      (node
        `env_binds`
        (spread `1`))))
  (rule
    (name `assigns`)
    (alt
      _
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      (node
        `assigns`
        (spread `1`))))
  (rule
    (name `assign_prefix`)
    (alt
      _
      ((tok `NAME_EQ`)
        (ref `assign_value`))
      (node
        `env_bind`
        (pos `1`)
        (pos `2`))))
  (rule
    (name `assign_value`)
    (alt
      _
      ((ref `word_atom`))
      (node
        `scalar`
        (pos `1`)))
    (alt
      _
      ((tok `LBRACKET`)
        (ref `word_atoms_opt`)
        (tok `RBRACKET`))
      (node
        `list`
        (spread `2`))))
  (rule
    (name `word_atoms_opt`)
    (alt
      _
      ((quantified
          (ref `word_atom`)
          (zero_plus)))
      (list
        (spread `1`))))
  (rule
    (name `part`)
    (alt
      _
      ((ref `word_atom`)))
    (alt
      _
      ((ref `redirect`))))
  (rule
    (name `leading_word`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `word`
        (pos `1`)))
    (alt
      _
      ((tok `INTEGER`))
      (node
        `word`
        (pos `1`)))
    (alt
      _
      ((tok `STRING_SQ`))
      (node
        `word`
        (pos `1`)))
    (alt
      _
      ((tok `STRING_DQ`))
      (node
        `word`
        (pos `1`)))
    (alt
      _
      ((tok `VARIABLE`))
      (node
        `var`
        (pos `1`)))
    (alt
      _
      ((tok `VAR_BRACED`))
      (node
        `var_braced`
        (pos `1`)))
    (alt
      _
      ((tok `DOLLAR_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `cmd_subst`
        (pos `2`)))
    (alt
      _
      ((tok `AT_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `list_capture`
        (pos `2`)))
    (alt
      _
      ((tok `PROC_SUB_IN`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `proc_sub_in`
        (pos `2`)))
    (alt
      _
      ((tok `PROC_SUB_OUT`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `proc_sub_out`
        (pos `2`))))
  (rule
    (name `word_atom`)
    (alt
      _
      ((ref `leading_word`)))
    (alt
      _
      ((tok `NAME_EQ`))
      (node
        `word`
        (pos `1`)))
    (alt
      _
      ((tok `ASSIGN`))
      (node
        `word`
        (pos `1`))))
  (rule
    (name `conditional`)
    (alt
      _
      ((tok `IF`)
        (ref `cond_chain`)
        (ref `block_form`))
      (node
        `if`
        (pos `2`)
        (pos `3`)
        (null)))
    (alt
      _
      ((tok `IF`)
        (ref `cond_chain`)
        (ref `block_form`)
        (ref `else_part`))
      (node
        `if`
        (pos `2`)
        (pos `3`)
        (pos `4`))))
  (rule
    (name `cond_chain`)
    (alt
      _
      ((ref `pipeline`))
      (pos `1`))
    (alt
      _
      ((ref `cond_chain`)
        (tok `AND_AND`)
        (ref `pipeline`))
      (node
        `cond_and`
        (pos `1`)
        (pos `3`)))
    (alt
      _
      ((ref `cond_chain`)
        (tok `OR_OR`)
        (ref `pipeline`))
      (node
        `cond_or`
        (pos `1`)
        (pos `3`))))
  (rule
    (name `else_part`)
    (alt
      _
      ((tok `ELSE`)
        (ref `block_form`))
      (node
        `else`
        (pos `2`)))
    (alt
      _
      ((tok `ELSE`)
        (ref `conditional`))
      (node
        `elif`
        (pos `2`))))
  (rule
    (name `block_form`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `sequence`)
        (tok `RBRACE`))
      (node
        `body`
        (pos `2`)))
    (alt
      _
      ((tok `INDENT`)
        (ref `sequence`)
        (tok `OUTDENT`))
      (node
        `body`
        (pos `2`))))
  (rule
    (name `while_loop`)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond_chain`)
        (ref `block_form`))
      (node
        `while`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `for_loop`)
    (alt
      _
      ((tok `FOR`)
        (tok `IDENT`)
        (tok `IN`)
        (ref `word_atoms`)
        (ref `block_form`))
      (node
        `for`
        (pos `2`)
        (pos `4`)
        (pos `5`))))
  (rule
    (name `match_stmt`)
    (alt
      _
      ((tok `MATCH`)
        (ref `word_atom`)
        (ref `match_block`))
      (node
        `match`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `match_block`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `match_arms`)
        (tok `RBRACE`))
      (node
        `match_arms`
        (spread `2`)))
    (alt
      _
      ((tok `INDENT`)
        (ref `match_arms`)
        (tok `OUTDENT`))
      (node
        `match_arms`
        (spread `2`))))
  (rule
    (name `match_arms`)
    (alt
      _
      ((ref `match_arm`)
        (quantified
          (ref `match_arm_tail`)
          (zero_plus)))
      (list
        (pos `1`)
        (spread `2`))))
  (rule
    (name `match_arm_tail`)
    (alt
      _
      ((tok `SEMI`)
        (ref `match_arm`))
      (pos `2`))
    (alt
      _
      ((tok `SEMI`))
      (null)))
  (rule
    (name `match_arm`)
    (alt
      _
      ((ref `word_atoms`)
        (ref `block_form`))
      (node
        `match_arm`
        (pos `1`)
        (pos `2`))))
  (rule
    (name `cmd_def`)
    (alt
      _
      ((tok `CMD`)
        (tok `IDENT`)
        (ref `block_form`))
      (node
        `cmd_def`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `str_def`)
    (alt
      _
      ((tok `STR_OPEN`)
        (tok `IDENT`)
        (tok `STR_BODY`))
      (node
        `str_def`
        (pos `2`)
        (pos `3`))))
  (rule
    (name `word_atoms`)
    (alt
      _
      ((quantified
          (ref `word_atom`)
          (one_plus)))
      (node
        `words`
        (spread `1`))))
  (rule
    (name `redirect`)
    (alt
      _
      ((tok `LT`)
        (ref `word_atom`))
      (node
        `redir_read`
        (pos `2`)))
    (alt
      _
      ((tok `FD_LT`)
        (ref `word_atom`))
      (node
        `redir_read_fd`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `GT`)
        (ref `word_atom`))
      (node
        `redir_write`
        (pos `2`)))
    (alt
      _
      ((tok `FD_GT`)
        (ref `word_atom`))
      (node
        `redir_write_fd`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `GT_GT`)
        (ref `word_atom`))
      (node
        `redir_append`
        (pos `2`)))
    (alt
      _
      ((tok `AMP_GT`)
        (ref `word_atom`))
      (node
        `redir_both`
        (pos `2`)))
    (alt
      _
      ((tok `AMP_GT_GT`)
        (ref `word_atom`))
      (node
        `redir_both_append`
        (pos `2`)))
    (alt
      _
      ((tok `FD_DUP_OUT`))
      (node
        `redir_dup_out`
        (pos `1`)))
    (alt
      _
      ((tok `FD_DUP_IN`))
      (node
        `redir_dup_in`
        (pos `1`)))
    (alt
      _
      ((tok `HEREDOC_OPEN`)
        (tok `HEREDOC_BODY`))
      (node
        `redir_heredoc`
        (pos `1`)
        (pos `2`)))
    (alt
      _
      ((tok `HEREDOC_OPEN_LIT`)
        (tok `HEREDOC_BODY`))
      (node
        `redir_heredoc_lit`
        (pos `1`)
        (pos `2`)))))
