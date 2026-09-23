(grammar
  (section `lexer`)
  (state
    `state`
    (assign `paren` `0`)
    (assign `brace` `0`)
    (assign `bracket` `0`))
  (tokens `tokens` `ident` `integer` `string_sq` `string_dq` `variable` `var_braced` `dollar_paren` `at_paren` `proc_sub_in` `proc_sub_out` `lparen` `rparen` `lbrace` `rbrace` `lbracket` `rbracket` `semi` `and_and` `or_or` `amp` `pipe` `lt` `gt` `gt_gt` `amp_gt` `amp_gt_gt` `fd_lt` `fd_gt` `fd_dup_out` `fd_dup_in` `heredoc_open` `heredoc_open_lit` `heredoc_body` `str_open` `str_body` `assign` `name_eq` `indent` `outdent` `comment` `err` `eof`)
  (lex_rule `"&&"` _ `and_and`)
  (lex_rule `"||"` _ `or_or`)
  (lex_rule `"&>>"` _ `amp_gt_gt`)
  (lex_rule `"&>"` _ `amp_gt`)
  (lex_rule `">>"` _ `gt_gt`)
  (lex_rule `'<' '<' "'" [A-Za-z_] [A-Za-z0-9_]* "'"` _ `heredoc_open_lit`)
  (lex_rule `'<' '<' [A-Za-z_] [A-Za-z0-9_]*` _ `heredoc_open`)
  (lex_rule
    `"<("`
    _
    `proc_sub_in`
    (step_action `paren` `++`))
  (lex_rule
    `">("`
    _
    `proc_sub_out`
    (step_action `paren` `++`))
  (lex_rule `[0-9]+ '>' '&' [0-9]+` _ `fd_dup_out`)
  (lex_rule `[0-9]+ '<' '&' [0-9]+` _ `fd_dup_in`)
  (lex_rule `[0-9]+ '>'` _ `fd_gt`)
  (lex_rule `[0-9]+ '<'` _ `fd_lt`)
  (lex_rule `">"` _ `gt`)
  (lex_rule `"<"` _ `lt`)
  (lex_rule `"|"` _ `pipe`)
  (lex_rule `";"` _ `semi`)
  (lex_rule `"&"` _ `amp`)
  (lex_rule `"="` _ `assign`)
  (lex_rule
    `"("`
    _
    `lparen`
    (step_action `paren` `++`))
  (lex_rule
    `")"`
    _
    `rparen`
    (step_action `paren` `--`))
  (lex_rule
    `"{"`
    _
    `lbrace`
    (step_action `brace` `++`))
  (lex_rule
    `"}"`
    _
    `rbrace`
    (step_action `brace` `--`))
  (lex_rule
    `"["`
    _
    `lbracket`
    (step_action `bracket` `++`))
  (lex_rule
    `"]"`
    _
    `rbracket`
    (step_action `bracket` `--`))
  (lex_rule `"'" ([^'\\n] | "''")* "'"` _ `string_sq`)
  (lex_rule `'"' ([^"\\\\\\n] | "\\\\" .)* '"'` _ `string_dq`)
  (lex_rule `'$' '{' [^}\\n]+ '}'` _ `var_braced`)
  (lex_rule `'$' [A-Za-z_] [A-Za-z0-9_]*` _ `variable`)
  (lex_rule `'$' [0-9]` _ `variable`)
  (lex_rule `'$' '?'` _ `variable`)
  (lex_rule `'$' '#'` _ `variable`)
  (lex_rule `'$' '!'` _ `variable`)
  (lex_rule `'$' '@'` _ `variable`)
  (lex_rule `'$' '*'` _ `variable`)
  (lex_rule `'$' '$'` _ `variable`)
  (lex_rule
    `"$("`
    _
    `dollar_paren`
    (step_action `paren` `++`))
  (lex_rule
    `"@("`
    _
    `at_paren`
    (step_action `paren` `++`))
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `"\\r\\n"` _ `semi`)
  (lex_rule `'\\n'` _ `semi`)
  (lex_rule `'\\r'` _ `semi`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `[A-Za-z_./\\-+~@%!*?:,^][A-Za-z0-9_./\\-+~@%!*?:,^]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"slash"`)
  (as
    `ident`
    _
    (as_entry perm `keyword` _))
  (rule
    (start `program`)
    (alt
      _
      ((ref `sequence`))
      (pos `1`)
      _))
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
        (spread `2`))
      _))
  (rule
    (name `sequence_item`)
    (alt
      _
      ((ref `pipeline`))
      _
      _)
    (alt
      _
      ((ref `conditional`))
      _
      _)
    (alt
      _
      ((ref `while_loop`))
      _
      _)
    (alt
      _
      ((ref `for_loop`))
      _
      _)
    (alt
      _
      ((ref `match_stmt`))
      _
      _)
    (alt
      _
      ((ref `block_stmt`))
      _
      _)
    (alt
      _
      ((ref `assigns`))
      _
      _)
    (alt
      _
      ((ref `cmd_def`))
      _
      _)
    (alt
      _
      ((ref `str_def`))
      _
      _))
  (rule
    (name `sequence_tail`)
    (alt
      _
      ((tok `SEMI`)
        (ref `sequence_item`))
      (node
        `seq_always`
        (pos `2`))
      _)
    (alt
      _
      ((tok `SEMI`))
      (node
        `seq_always`
        (null))
      _)
    (alt
      _
      ((tok `AND_AND`)
        (ref `sequence_item`))
      (node
        `seq_and`
        (pos `2`))
      _)
    (alt
      _
      ((tok `OR_OR`)
        (ref `sequence_item`))
      (node
        `seq_or`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP`)
        (ref `sequence_item`))
      (node
        `seq_bg`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP`))
      (node
        `seq_bg`
        (null))
      _))
  (rule
    (name `pipeline`)
    (alt
      _
      ((ref `stage`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `stage`)
        (quantified
          (ref `pipe_tail`)
          (one_plus)))
      (node
        `pipeline`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `pipe_tail`)
    (alt
      _
      ((tok `PIPE`)
        (ref `stage`))
      (pos `2`)
      _))
  (rule
    (name `stage`)
    (alt
      _
      ((ref `simple_command`))
      _
      _)
    (alt
      _
      ((ref `subshell`))
      _
      _))
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
        (pos `4`))
      _))
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
        (pos `4`))
      _))
  (rule
    (name `redirect_list`)
    (alt
      _
      ((quantified
          (ref `redirect`)
          (one_plus)))
      (node
        `redirects`
        (spread `1`))
      _))
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
        (spread `2`))
      _)
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
        (spread `3`))
      _))
  (rule
    (name `env_prefix_list`)
    (alt
      _
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      (node
        `env_binds`
        (spread `1`))
      _))
  (rule
    (name `assigns`)
    (alt
      _
      ((quantified
          (ref `assign_prefix`)
          (one_plus)))
      (node
        `assigns`
        (spread `1`))
      _))
  (rule
    (name `assign_prefix`)
    (alt
      _
      ((tok `NAME_EQ`)
        (ref `assign_value`))
      (node
        `env_bind`
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `assign_value`)
    (alt
      _
      ((ref `word_atom`))
      (node
        `scalar`
        (pos `1`))
      _)
    (alt
      _
      ((tok `LBRACKET`)
        (ref `word_atoms_opt`)
        (tok `RBRACKET`))
      (node
        `list`
        (spread `2`))
      _))
  (rule
    (name `word_atoms_opt`)
    (alt
      _
      ((quantified
          (ref `word_atom`)
          (zero_plus)))
      (list
        (spread `1`))
      _))
  (rule
    (name `part`)
    (alt
      _
      ((ref `word_atom`))
      _
      _)
    (alt
      _
      ((ref `redirect`))
      _
      _))
  (rule
    (name `leading_word`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `word`
        (pos `1`))
      _)
    (alt
      _
      ((tok `INTEGER`))
      (node
        `word`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STRING_SQ`))
      (node
        `word`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STRING_DQ`))
      (node
        `word`
        (pos `1`))
      _)
    (alt
      _
      ((tok `VARIABLE`))
      (node
        `var`
        (pos `1`))
      _)
    (alt
      _
      ((tok `VAR_BRACED`))
      (node
        `var_braced`
        (pos `1`))
      _)
    (alt
      _
      ((tok `DOLLAR_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `cmd_subst`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AT_PAREN`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `list_capture`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PROC_SUB_IN`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `proc_sub_in`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PROC_SUB_OUT`)
        (ref `sequence`)
        (tok `RPAREN`))
      (node
        `proc_sub_out`
        (pos `2`))
      _))
  (rule
    (name `word_atom`)
    (alt
      _
      ((ref `leading_word`))
      _
      _)
    (alt
      _
      ((tok `NAME_EQ`))
      (node
        `word`
        (pos `1`))
      _)
    (alt
      _
      ((tok `ASSIGN`))
      (node
        `word`
        (pos `1`))
      _))
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
        (null))
      _)
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
        (pos `4`))
      _))
  (rule
    (name `cond_chain`)
    (alt
      _
      ((ref `pipeline`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `cond_chain`)
        (tok `AND_AND`)
        (ref `pipeline`))
      (node
        `cond_and`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `cond_chain`)
        (tok `OR_OR`)
        (ref `pipeline`))
      (node
        `cond_or`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `else_part`)
    (alt
      _
      ((tok `ELSE`)
        (ref `block_form`))
      (node
        `else`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ELSE`)
        (ref `conditional`))
      (node
        `elif`
        (pos `2`))
      _))
  (rule
    (name `block_form`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `sequence`)
        (tok `RBRACE`))
      (node
        `body`
        (pos `2`))
      _)
    (alt
      _
      ((tok `INDENT`)
        (ref `sequence`)
        (tok `OUTDENT`))
      (node
        `body`
        (pos `2`))
      _))
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
        (pos `3`))
      _))
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
        (pos `5`))
      _))
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
        (pos `3`))
      _))
  (rule
    (name `match_block`)
    (alt
      _
      ((tok `LBRACE`)
        (ref `match_arms`)
        (tok `RBRACE`))
      (node
        `match_arms`
        (spread `2`))
      _)
    (alt
      _
      ((tok `INDENT`)
        (ref `match_arms`)
        (tok `OUTDENT`))
      (node
        `match_arms`
        (spread `2`))
      _))
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
        (spread `2`))
      _))
  (rule
    (name `match_arm_tail`)
    (alt
      _
      ((tok `SEMI`)
        (ref `match_arm`))
      (pos `2`)
      _)
    (alt
      _
      ((tok `SEMI`))
      (null)
      _))
  (rule
    (name `match_arm`)
    (alt
      _
      ((ref `word_atoms`)
        (ref `block_form`))
      (node
        `match_arm`
        (pos `1`)
        (pos `2`))
      _))
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
        (pos `3`))
      _))
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
        (pos `3`))
      _))
  (rule
    (name `word_atoms`)
    (alt
      _
      ((quantified
          (ref `word_atom`)
          (one_plus)))
      (node
        `words`
        (spread `1`))
      _))
  (rule
    (name `redirect`)
    (alt
      _
      ((tok `LT`)
        (ref `word_atom`))
      (node
        `redir_read`
        (pos `2`))
      _)
    (alt
      _
      ((tok `FD_LT`)
        (ref `word_atom`))
      (node
        `redir_read_fd`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((tok `GT`)
        (ref `word_atom`))
      (node
        `redir_write`
        (pos `2`))
      _)
    (alt
      _
      ((tok `FD_GT`)
        (ref `word_atom`))
      (node
        `redir_write_fd`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((tok `GT_GT`)
        (ref `word_atom`))
      (node
        `redir_append`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP_GT`)
        (ref `word_atom`))
      (node
        `redir_both`
        (pos `2`))
      _)
    (alt
      _
      ((tok `AMP_GT_GT`)
        (ref `word_atom`))
      (node
        `redir_both_append`
        (pos `2`))
      _)
    (alt
      _
      ((tok `FD_DUP_OUT`))
      (node
        `redir_dup_out`
        (pos `1`))
      _)
    (alt
      _
      ((tok `FD_DUP_IN`))
      (node
        `redir_dup_in`
        (pos `1`))
      _)
    (alt
      _
      ((tok `HEREDOC_OPEN`)
        (tok `HEREDOC_BODY`))
      (node
        `redir_heredoc`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((tok `HEREDOC_OPEN_LIT`)
        (tok `HEREDOC_BODY`))
      (node
        `redir_heredoc_lit`
        (pos `1`)
        (pos `2`))
      _)))
