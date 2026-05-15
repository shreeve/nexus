(grammar
  (lang `"slash"`)
  (conflicts `0`)
  (as
    `ident`
    (as_entry perm `keyword`))
  (rule
    (start `program`)
    (alt
      _
      ((ref `sequence`))
      `1`))
  (rule
    (name `sequence`)
    (alt
      _
      ((ref `sequence_item`)
        (quantified
          (ref `sequence_tail`)
          (zero_plus)))
      `(sequence 1 ...2)`))
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
      `(seq_always 2)`)
    (alt
      _
      ((tok `SEMI`))
      `(seq_always _)`)
    (alt
      _
      ((tok `AND_AND`)
        (ref `sequence_item`))
      `(seq_and 2)`)
    (alt
      _
      ((tok `OR_OR`)
        (ref `sequence_item`))
      `(seq_or 2)`)
    (alt
      _
      ((tok `AMP`)
        (ref `sequence_item`))
      `(seq_bg 2)`)
    (alt
      _
      ((tok `AMP`))
      `(seq_bg _)`))
  (rule
    (name `pipeline`)
    (alt
      _
      ((ref `stage`))
      `1`)
    (alt
      _
      ((ref `stage`)
        (quantified
          (ref `pipe_tail`)
          (one_plus)))
      `(pipeline 1 ...2)`))
  (rule
    (name `pipe_tail`)
    (alt
      _
      ((tok `PIPE`)
        (ref `stage`))
      `2`))
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
      `(subshell 2 4)`))
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
      `(block 2 4)`))
  (rule
    (name `redirect_list`)
    (alt
      _
      ((quantified
          (ref `redirect`)
          (one_plus)))
      `(redirects ...1)`))
  (rule
    (name `simple_command`)
    (alt
      _
      ((ref `leading_word`)
        (quantified
          (ref `part`)
          (zero_plus)))
      `(command _ 1 ...2)`)
    (alt
      _
      ((ref `env_prefix_list`)
        (ref `leading_word`)
        (quantified
          (ref `part`)
          (zero_plus)))
      `(command 1 2 ...3)`))
  (rule
    (name `env_prefix_list`)
    (alt
      _
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      `(env_binds ...1)`))
  (rule
    (name `assigns`)
    (alt
      _
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      `(assigns ...1)`))
  (rule
    (name `assign_prefix`)
    (alt
      _
      ((tok `NAME_EQ`)
        (ref `assign_value`))
      `(env_bind 1 2)`))
  (rule
    (name `assign_value`)
    (alt
      _
      ((ref `word_atom`))
      `(scalar 1)`)
    (alt
      _
      ((tok `LBRACKET`)
        (ref `word_atoms_opt`)
        (tok `RBRACKET`))
      `(list ...2)`))
  (rule
    (name `word_atoms_opt`)
    (alt
      _
      ((quantified
          (ref `word_atom`)
          (zero_plus)))
      `(...1)`))
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
      `(word 1)`)
    (alt
      _
      ((tok `INTEGER`))
      `(word 1)`)
    (alt
      _
      ((tok `STRING_SQ`))
      `(word 1)`)
    (alt
      _
      ((tok `STRING_DQ`))
      `(word 1)`)
    (alt
      _
      ((tok `VARIABLE`))
      `(var 1)`)
    (alt
      _
      ((tok `VAR_BRACED`))
      `(var_braced 1)`)
    (alt
      _
      ((tok `DOLLAR_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(cmd_subst 2)`)
    (alt
      _
      ((tok `AT_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(list_capture 2)`)
    (alt
      _
      ((tok `PROC_SUB_IN`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(proc_sub_in 2)`)
    (alt
      _
      ((tok `PROC_SUB_OUT`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(proc_sub_out 2)`))
  (rule
    (name `word_atom`)
    (alt
      _
      ((ref `leading_word`)))
    (alt
      _
      ((tok `NAME_EQ`))
      `(word 1)`)
    (alt
      _
      ((tok `ASSIGN`))
      `(word 1)`))
  (rule
    (name `conditional`)
    (alt
      _
      ((tok `IF`)
        (ref `cond_chain`)
        (ref `block_form`))
      `(if 2 3 _)`)
    (alt
      _
      ((tok `IF`)
        (ref `cond_chain`)
        (ref `block_form`)
        (ref `else_part`))
      `(if 2 3 4)`))
  (rule
    (name `cond_chain`)
    (alt
      _
      ((ref `pipeline`))
      `1`)
    (alt
      _
      ((ref `cond_chain`)
        (tok `AND_AND`)
        (ref `pipeline`))
      `(cond_and 1 3)`)
    (alt
      _
      ((ref `cond_chain`)
        (tok `OR_OR`)
        (ref `pipeline`))
      `(cond_or 1 3)`))
  (rule
    (name `else_part`)
    (alt
      _
      ((tok `ELSE`)
        (ref `block_form`))
      `(else 2)`)
    (alt
      _
      ((tok `ELSE`)
        (ref `conditional`))
      `(elif 2)`))
  (rule
    (name `block_form`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `sequence`)
        (tok `RBRACE`))
      `(body 2)`)
    (alt
      _
      ((tok `INDENT`)
        (ref `sequence`)
        (tok `OUTDENT`))
      `(body 2)`))
  (rule
    (name `while_loop`)
    (alt
      _
      ((tok `WHILE`)
        (ref `cond_chain`)
        (ref `block_form`))
      `(while 2 3)`))
  (rule
    (name `for_loop`)
    (alt
      _
      ((tok `FOR`)
        (tok `IDENT`)
        (tok `IN`)
        (ref `word_atoms`)
        (ref `block_form`))
      `(for 2 4 5)`))
  (rule
    (name `match_stmt`)
    (alt
      _
      ((tok `MATCH`)
        (ref `word_atom`)
        (ref `match_block`))
      `(match 2 3)`))
  (rule
    (name `match_block`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `match_arms`)
        (tok `RBRACE`))
      `(match_arms ...2)`)
    (alt
      _
      ((tok `INDENT`)
        (ref `match_arms`)
        (tok `OUTDENT`))
      `(match_arms ...2)`))
  (rule
    (name `match_arms`)
    (alt
      _
      ((ref `match_arm`)
        (quantified
          (ref `match_arm_tail`)
          (zero_plus)))
      `(1 ...2)`))
  (rule
    (name `match_arm_tail`)
    (alt
      _
      ((tok `SEMI`)
        (ref `match_arm`))
      `2`)
    (alt
      _
      ((tok `SEMI`))
      `_`))
  (rule
    (name `match_arm`)
    (alt
      _
      ((ref `word_atoms`)
        (ref `block_form`))
      `(match_arm 1 2)`))
  (rule
    (name `cmd_def`)
    (alt
      _
      ((tok `CMD`)
        (tok `IDENT`)
        (ref `block_form`))
      `(cmd_def 2 3)`))
  (rule
    (name `str_def`)
    (alt
      _
      ((tok `STR_OPEN`)
        (tok `IDENT`)
        (tok `STR_BODY`))
      `(str_def 2 3)`))
  (rule
    (name `word_atoms`)
    (alt
      _
      ((quantified
          (ref `word_atom`)
          (one_plus)))
      `(words ...1)`))
  (rule
    (name `redirect`)
    (alt
      _
      ((tok `LT`)
        (ref `word_atom`))
      `(redir_read 2)`)
    (alt
      _
      ((tok `FD_LT`)
        (ref `word_atom`))
      `(redir_read_fd 1 2)`)
    (alt
      _
      ((tok `GT`)
        (ref `word_atom`))
      `(redir_write 2)`)
    (alt
      _
      ((tok `FD_GT`)
        (ref `word_atom`))
      `(redir_write_fd 1 2)`)
    (alt
      _
      ((tok `GT_GT`)
        (ref `word_atom`))
      `(redir_append 2)`)
    (alt
      _
      ((tok `AMP_GT`)
        (ref `word_atom`))
      `(redir_both 2)`)
    (alt
      _
      ((tok `AMP_GT_GT`)
        (ref `word_atom`))
      `(redir_both_append 2)`)
    (alt
      _
      ((tok `FD_DUP_OUT`))
      `(redir_dup_out 1)`)
    (alt
      _
      ((tok `FD_DUP_IN`))
      `(redir_dup_in 1)`)
    (alt
      _
      ((tok `HEREDOC_OPEN`)
        (tok `HEREDOC_BODY`))
      `(redir_heredoc 1 2)`)
    (alt
      _
      ((tok `HEREDOC_OPEN_LIT`)
        (tok `HEREDOC_BODY`))
      `(redir_heredoc_lit 1 2)`)))
