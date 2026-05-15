(grammar
  (lang `"slash"`)
  (conflicts `0`)
  (as
    `ident`
    (as_perm `keyword`))
  (rule
    (start `program`)
    (alt
      ((ref `sequence`))
      `1`))
  (rule
    (name `sequence`)
    (alt
      ((ref `sequence_item`)
        (quantified
          (ref `sequence_tail`)
          (zero_plus)))
      `(sequence 1 ...2)`))
  (rule
    (name `sequence_item`)
    (alt
      ((ref `pipeline`)))
    (alt
      ((ref `conditional`)))
    (alt
      ((ref `while_loop`)))
    (alt
      ((ref `for_loop`)))
    (alt
      ((ref `match_stmt`)))
    (alt
      ((ref `block_stmt`)))
    (alt
      ((ref `assigns`)))
    (alt
      ((ref `cmd_def`))))
  (rule
    (name `sequence_tail`)
    (alt
      ((tok `SEMI`)
        (ref `sequence_item`))
      `(seq_always 2)`)
    (alt
      ((tok `SEMI`))
      `(seq_always _)`)
    (alt
      ((tok `AND_AND`)
        (ref `sequence_item`))
      `(seq_and 2)`)
    (alt
      ((tok `OR_OR`)
        (ref `sequence_item`))
      `(seq_or 2)`)
    (alt
      ((tok `AMP`)
        (ref `sequence_item`))
      `(seq_bg 2)`)
    (alt
      ((tok `AMP`))
      `(seq_bg _)`))
  (rule
    (name `pipeline`)
    (alt
      ((ref `stage`))
      `1`)
    (alt
      ((ref `stage`)
        (quantified
          (ref `pipe_tail`)
          (one_plus)))
      `(pipeline 1 ...2)`))
  (rule
    (name `pipe_tail`)
    (alt
      ((tok `PIPE`)
        (ref `stage`))
      `2`))
  (rule
    (name `stage`)
    (alt
      ((ref `simple_command`)))
    (alt
      ((ref `subshell`))))
  (rule
    (name `subshell`)
    (alt
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
      ((quantified
          (ref `redirect`)
          (one_plus)))
      `(redirects ...1)`))
  (rule
    (name `simple_command`)
    (alt
      ((ref `leading_word`)
        (quantified
          (ref `part`)
          (zero_plus)))
      `(command _ 1 ...2)`)
    (alt
      ((ref `env_prefix_list`)
        (ref `leading_word`)
        (quantified
          (ref `part`)
          (zero_plus)))
      `(command 1 2 ...3)`))
  (rule
    (name `env_prefix_list`)
    (alt
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      `(env_binds ...1)`))
  (rule
    (name `assigns`)
    (alt
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      `(assigns ...1)`))
  (rule
    (name `assign_prefix`)
    (alt
      ((tok `NAME_EQ`)
        (ref `assign_value`))
      `(env_bind 1 2)`))
  (rule
    (name `assign_value`)
    (alt
      ((ref `word_atom`))
      `(scalar 1)`)
    (alt
      ((tok `LBRACKET`)
        (ref `word_atoms_opt`)
        (tok `RBRACKET`))
      `(list ...2)`))
  (rule
    (name `word_atoms_opt`)
    (alt
      ((quantified
          (ref `word_atom`)
          (zero_plus)))
      `(...1)`))
  (rule
    (name `part`)
    (alt
      ((ref `word_atom`)))
    (alt
      ((ref `redirect`))))
  (rule
    (name `leading_word`)
    (alt
      ((tok `IDENT`))
      `(word 1)`)
    (alt
      ((tok `INTEGER`))
      `(word 1)`)
    (alt
      ((tok `STRING_SQ`))
      `(word 1)`)
    (alt
      ((tok `STRING_DQ`))
      `(word 1)`)
    (alt
      ((tok `VARIABLE`))
      `(var 1)`)
    (alt
      ((tok `VAR_BRACED`))
      `(var_braced 1)`)
    (alt
      ((tok `DOLLAR_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(cmd_subst 2)`)
    (alt
      ((tok `AT_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(list_capture 2)`)
    (alt
      ((tok `PROC_SUB_IN`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(proc_sub_in 2)`)
    (alt
      ((tok `PROC_SUB_OUT`)
        (ref `sequence`)
        (tok `RPAREN`))
      `(proc_sub_out 2)`))
  (rule
    (name `word_atom`)
    (alt
      ((ref `leading_word`)))
    (alt
      ((tok `NAME_EQ`))
      `(word 1)`)
    (alt
      ((tok `ASSIGN`))
      `(word 1)`))
  (rule
    (name `conditional`)
    (alt
      ((tok `IF`)
        (ref `cond_chain`)
        (ref `block_form`))
      `(if 2 3 _)`)
    (alt
      ((tok `IF`)
        (ref `cond_chain`)
        (ref `block_form`)
        (ref `else_part`))
      `(if 2 3 4)`))
  (rule
    (name `cond_chain`)
    (alt
      ((ref `pipeline`))
      `1`)
    (alt
      ((ref `cond_chain`)
        (tok `AND_AND`)
        (ref `pipeline`))
      `(cond_and 1 3)`)
    (alt
      ((ref `cond_chain`)
        (tok `OR_OR`)
        (ref `pipeline`))
      `(cond_or 1 3)`))
  (rule
    (name `else_part`)
    (alt
      ((tok `ELSE`)
        (ref `block_form`))
      `(else 2)`)
    (alt
      ((tok `ELSE`)
        (ref `conditional`))
      `(elif 2)`))
  (rule
    (name `block_form`)
    (alt
      ((tok `LBRACE`)
        (ref `sequence`)
        (tok `RBRACE`))
      `(body 2)`)
    (alt
      ((tok `INDENT`)
        (ref `sequence`)
        (tok `OUTDENT`))
      `(body 2)`))
  (rule
    (name `while_loop`)
    (alt
      ((tok `WHILE`)
        (ref `cond_chain`)
        (ref `block_form`))
      `(while 2 3)`))
  (rule
    (name `for_loop`)
    (alt
      ((tok `FOR`)
        (tok `IDENT`)
        (tok `IN`)
        (ref `word_atoms`)
        (ref `block_form`))
      `(for 2 4 5)`))
  (rule
    (name `match_stmt`)
    (alt
      ((tok `MATCH`)
        (ref `word_atom`)
        (ref `match_block`))
      `(match 2 3)`))
  (rule
    (name `match_block`)
    (alt
      ((tok `LBRACE`)
        (ref `match_arms`)
        (tok `RBRACE`))
      `(match_arms ...2)`)
    (alt
      ((tok `INDENT`)
        (ref `match_arms`)
        (tok `OUTDENT`))
      `(match_arms ...2)`))
  (rule
    (name `match_arms`)
    (alt
      ((ref `match_arm`)
        (quantified
          (ref `match_arm_tail`)
          (zero_plus)))
      `(1 ...2)`))
  (rule
    (name `match_arm_tail`)
    (alt
      ((tok `SEMI`)
        (ref `match_arm`))
      `2`)
    (alt
      ((tok `SEMI`))
      `_`))
  (rule
    (name `match_arm`)
    (alt
      ((ref `word_atoms`)
        (ref `block_form`))
      `(match_arm 1 2)`))
  (rule
    (name `cmd_def`)
    (alt
      ((tok `CMD`)
        (tok `IDENT`)
        (ref `block_form`))
      `(cmd_def 2 3)`))
  (rule
    (name `word_atoms`)
    (alt
      ((quantified
          (ref `word_atom`)
          (one_plus)))
      `(words ...1)`))
  (rule
    (name `redirect`)
    (alt
      ((tok `LT`)
        (ref `word_atom`))
      `(redir_read 2)`)
    (alt
      ((tok `FD_LT`)
        (ref `word_atom`))
      `(redir_read_fd 1 2)`)
    (alt
      ((tok `GT`)
        (ref `word_atom`))
      `(redir_write 2)`)
    (alt
      ((tok `FD_GT`)
        (ref `word_atom`))
      `(redir_write_fd 1 2)`)
    (alt
      ((tok `GT_GT`)
        (ref `word_atom`))
      `(redir_append 2)`)
    (alt
      ((tok `AMP_GT`)
        (ref `word_atom`))
      `(redir_both 2)`)
    (alt
      ((tok `AMP_GT_GT`)
        (ref `word_atom`))
      `(redir_both_append 2)`)
    (alt
      ((tok `FD_DUP_OUT`))
      `(redir_dup_out 1)`)
    (alt
      ((tok `FD_DUP_IN`))
      `(redir_dup_in 1)`)
    (alt
      ((tok `HEREDOC_OPEN`)
        (tok `HEREDOC_BODY`))
      `(redir_heredoc 1 2)`)
    (alt
      ((tok `HEREDOC_OPEN_LIT`)
        (tok `HEREDOC_BODY`))
      `(redir_heredoc_lit 1 2)`)))
