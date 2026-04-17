(grammar
  (lang "slash")
  (conflicts 16)
  (as
    ident
    (as_strict cmd))
  (rule
    (name name)
    (alt
      ((tok IDENT))))
  (rule
    (name cmd_name)
    (alt
      ((tok IDENT))))
  (rule
    (start program)
    (alt
      ((quantified
          (ref line)
          (zero_plus)))
      (program ...1)))
  (rule
    (start oneline)
    (alt
      ((ref stmt))
      1))
  (rule
    (name line)
    (alt
      ((ref stmt)
        (group_opt
          ((tok COMMENT)))
        (tok NEWLINE))
      1)
    (alt
      ((group_opt
          ((tok COMMENT)))
        (tok NEWLINE))
      _))
  (rule
    (name stmt)
    (alt
      ((lit "=")
        (ref expr))
      (display 2))
    (alt
      ((tok IDENT)
        (lit "=")
        (lit "-"))
      (unset 1))
    (alt
      ((tok IDENT)
        (lit "=")
        (ref list_literal))
      (assign_argv 1 3))
    (alt
      ((tok IDENT)
        (lit "+=")
        (ref list_literal))
      (append_argv 1 3))
    (alt
      ((tok IDENT)
        (lit "=")
        (ref assign_rhs))
      (assign 1 3))
    (alt
      ((ref cmd_def))
      1)
    (alt
      ((ref key_def))
      1)
    (alt
      ((ref set_stmt))
      1)
    (alt
      ((ref if_stmt))
      1)
    (alt
      ((ref unless_stmt))
      1)
    (alt
      ((ref for_stmt))
      1)
    (alt
      ((ref while_stmt))
      1)
    (alt
      ((ref until_stmt))
      1)
    (alt
      ((ref try_stmt))
      1)
    (alt_reduce
      ((ref cmdlist))
      1))
  (rule
    (name cmdlist)
    (alt
      ((ref and_or)
        (lit ";")
        (ref cmdlist))
      (seq 1 3))
    (alt
      ((ref and_or)
        (lit "&")
        (ref cmdlist))
      (bg 1 3))
    (alt
      ((ref and_or)
        (lit "&"))
      (bg 1))
    (alt_shift
      ((ref and_or))
      1))
  (rule
    (name and_or)
    (alt
      ((ref and_or)
        (lit "&&")
        (ref pipeline))
      (and 1 3))
    (alt
      ((ref and_or)
        (tok AND)
        (ref pipeline))
      (and 1 3))
    (alt
      ((ref and_or)
        (lit "||")
        (ref pipeline))
      (or 1 3))
    (alt
      ((ref and_or)
        (tok OR)
        (ref pipeline))
      (or 1 3))
    (alt
      ((ref and_or)
        (tok XOR)
        (ref pipeline))
      (xor 1 3))
    (alt
      ((ref pipeline))))
  (rule
    (name pipeline)
    (alt
      ((ref command)
        (lit "|&")
        (ref pipeline))
      (pipe_err 1 3))
    (alt
      ((ref command)
        (lit "|")
        (ref pipeline))
      (pipe 1 3))
    (alt
      ((ref command))))
  (rule
    (name command)
    (alt
      ((lit "!")
        (ref command))
      (not 2))
    (alt
      ((tok NOT)
        (ref command))
      (not 2))
    (alt
      ((lit "(")
        (ref cmdlist)
        (lit ")"))
      (subshell 2))
    (alt
      ((tok TEST)
        (tok FLAG)
        (ref word))
      (test 2 3))
    (alt
      ((tok EXIT)
        (group_opt
          ((tok INTEGER))))
      (exit 2))
    (alt
      ((tok BREAK))
      (break))
    (alt
      ((tok CONTINUE))
      (continue))
    (alt
      ((tok SHIFT)
        (tok INTEGER))
      (shift 2))
    (alt
      ((tok SHIFT))
      (shift))
    (alt
      ((tok SOURCE)
        (ref word))
      (source 2))
    (alt
      ((tok EXEC)
        (ref simple_cmd))
      (exec 2))
    (alt
      ((ref simple_cmd))))
  (rule
    (name simple_cmd)
    (alt
      ((ref cmd_name)
        (quantified
          (ref cmd_arg)
          (zero_plus))
        (group_opt
          ((ref heredoc))))
      (cmd 1 ...2 3)))
  (rule
    (name cmd_arg)
    (alt
      ((ref argument)))
    (alt
      ((ref redirect))))
  (rule
    (name word)
    (alt_reduce
      ((tok IDENT)))
    (alt_reduce
      ((tok STRING_SQ)))
    (alt_reduce
      ((tok STRING_DQ)))
    (alt_reduce
      ((tok INTEGER)))
    (alt_reduce
      ((tok REAL)))
    (alt_reduce
      ((tok VARIABLE)))
    (alt_reduce
      ((tok VAR_BRACED)))
    (alt_reduce
      ((tok FLAG))))
  (rule
    (name argument)
    (alt
      ((tok IDENT)))
    (alt
      ((tok STRING_SQ)))
    (alt
      ((tok STRING_DQ)))
    (alt
      ((tok INTEGER)))
    (alt
      ((tok REAL)))
    (alt
      ((tok VARIABLE)))
    (alt
      ((tok VAR_BRACED)))
    (alt
      ((tok FLAG)))
    (alt
      ((tok REGEX)))
    (alt
      ((lit "-")))
    (alt
      ((ref proc_sub)))
    (alt
      ((ref subshell_capture))))
  (rule
    (name proc_sub)
    (alt
      ((lit "<(")
        (ref pipeline)
        (lit ")"))
      (procsub_in 2))
    (alt
      ((lit ">(")
        (ref pipeline)
        (lit ")"))
      (procsub_out 2)))
  (rule
    (name subshell_capture)
    (alt
      ((tok DOLLAR_PAREN)
        (ref pipeline)
        (lit ")"))
      (capture 2)))
  (rule
    (name redirect)
    (alt
      ((lit ">")
        (ref word))
      (redir_out 2))
    (alt
      ((lit ">>")
        (ref word))
      (redir_append 2))
    (alt
      ((lit "<")
        (ref word))
      (redir_in 2))
    (alt
      ((lit "2>")
        (ref word))
      (redir_err 2))
    (alt
      ((lit "2>>")
        (ref word))
      (redir_err_app 2))
    (alt
      ((lit "&>")
        (ref word))
      (redir_both 2))
    (alt
      ((lit "2>&1"))
      (redir_dup))
    (alt
      ((tok REDIR_FD_DUP))
      (redir_fd_dup 1))
    (alt
      ((tok REDIR_FD_OUT)
        (ref word))
      (redir_fd_out 1 2))
    (alt
      ((tok REDIR_FD_IN)
        (ref word))
      (redir_fd_in 1 2))
    (alt
      ((lit "<<<")
        (ref word))
      (herestring 2)))
  (rule
    (name heredoc)
    (alt
      ((tok HEREDOC_SQ)
        (quantified
          (tok HEREDOC_BODY)
          (zero_plus))
        (tok HEREDOC_SQ))
      (heredoc_literal ...2))
    (alt
      ((tok HEREDOC_DQ)
        (quantified
          (tok HEREDOC_BODY)
          (zero_plus))
        (tok HEREDOC_DQ))
      (heredoc_interp ...2))
    (alt
      ((tok HEREDOC_BT)
        (quantified
          (tok HEREDOC_BODY)
          (zero_plus))
        (tok HEREDOC_END))
      (heredoc_lang 1 ...2)))
  (rule
    (name if_stmt)
    (alt
      ((tok IF)
        (ref condition)
        (ref block)
        (quantified
          (ref else_clause)
          (opt)))
      (if 2 3 4)))
  (rule
    (name unless_stmt)
    (alt
      ((tok UNLESS)
        (ref condition)
        (ref block))
      (unless 2 3)))
  (rule
    (name else_clause)
    (alt
      ((tok ELSE)
        (ref if_stmt))
      2)
    (alt
      ((tok ELSE)
        (ref block))
      (else 2)))
  (rule
    (name condition)
    (alt
      ((ref comparison)))
    (alt_shift
      ((ref cmdlist))
      1))
  (rule
    (name comparison)
    (alt
      ((ref cmp_term)
        (tok AND)
        (ref comparison))
      (and 1 3))
    (alt
      ((ref cmp_term)
        (tok OR)
        (ref comparison))
      (or 1 3))
    (alt
      ((ref cmp_term))))
  (rule
    (name cmp_term)
    (alt
      ((ref expr)
        (lit "==")
        (ref expr))
      (eq 1 3))
    (alt
      ((ref expr)
        (lit "!=")
        (ref expr))
      (ne 1 3))
    (alt
      ((ref expr)
        (lit "<")
        (ref expr))
      (lt 1 3))
    (alt
      ((ref expr)
        (lit ">")
        (ref expr))
      (gt 1 3))
    (alt
      ((ref expr)
        (lit "<=")
        (ref expr))
      (le 1 3))
    (alt
      ((ref expr)
        (lit ">=")
        (ref expr))
      (ge 1 3))
    (alt
      ((ref expr)
        (lit "=~")
        (tok REGEX))
      (match 1 3))
    (alt
      ((ref expr)
        (lit "!~")
        (tok REGEX))
      (nomatch 1 3))
    (alt
      ((ref expr)
        (lit "=~")
        (ref expr))
      (match 1 3))
    (alt
      ((ref expr)
        (lit "!~")
        (ref expr))
      (nomatch 1 3))
    (alt
      ((tok NOT)
        (ref cmp_term))
      (not 2))
    (alt
      ((lit "(")
        (ref comparison)
        (lit ")"))
      2))
  (rule
    (name for_stmt)
    (alt
      ((tok FOR)
        (ref name)
        (tok IN)
        (ref wordlist)
        (ref block))
      (for 2 4 5)))
  (rule
    (name while_stmt)
    (alt
      ((tok WHILE)
        (ref condition)
        (ref block))
      (while 2 3)))
  (rule
    (name until_stmt)
    (alt
      ((tok UNTIL)
        (ref condition)
        (ref block))
      (until 2 3)))
  (rule
    (name wordlist)
    (alt
      ((quantified
          (ref word)
          (one_plus)))
      (list ...1)))
  (rule
    (name try_stmt)
    (alt
      ((tok TRY)
        (ref try_subject)
        (ref try_block))
      (try 2 3)))
  (rule
    (name try_block)
    (alt
      ((lit "{")
        (quantified
          (ref try_bitem)
          (one_plus))
        (lit "}"))
      (...2))
    (alt
      ((tok INDENT)
        (quantified
          (ref try_iline)
          (one_plus))
        (tok OUTDENT))
      (...2)))
  (rule
    (name try_bitem)
    (alt
      ((ref try_arm))
      1)
    (alt
      ((tok NEWLINE))
      _)
    (alt
      ((tok COMMENT))
      _))
  (rule
    (name try_iline)
    (alt
      ((ref try_arm)
        (group_opt
          ((tok COMMENT)))
        (tok NEWLINE))
      1)
    (alt
      ((group_opt
          ((tok COMMENT)))
        (tok NEWLINE))
      _))
  (rule
    (name try_arm)
    (alt
      ((tok REGEX)
        (ref block))
      (arm 1 2))
    (alt
      ((tok STRING_DQ)
        (ref block))
      (arm 1 2))
    (alt
      ((tok STRING_SQ)
        (ref block))
      (arm 1 2))
    (alt
      ((ref word)
        (ref block))
      (arm 1 2))
    (alt
      ((tok ELSE)
        (ref block))
      (arm_else 2)))
  (rule
    (name block)
    (alt
      ((lit "{")
        (quantified
          (ref brace_item)
          (zero_plus))
        (lit "}"))
      (block ...2))
    (alt
      ((tok INDENT)
        (quantified
          (ref line)
          (zero_plus))
        (tok OUTDENT))
      (block ...2)))
  (rule
    (name brace_item)
    (alt
      ((ref stmt))
      1)
    (alt
      ((tok NEWLINE))
      _)
    (alt
      ((tok COMMENT))
      _))
  (rule
    (name cmd_def)
    (alt
      ((tok CMD)
        (tok MISSING)
        (quantified
          (ref params)
          (opt))
        (ref block))
      (cmd_missing 3 4))
    (alt
      ((tok CMD)
        (tok MISSING)
        (quantified
          (ref params)
          (opt))
        (ref stmt))
      (cmd_missing 3 4))
    (alt
      ((tok CMD)
        (tok MISSING)
        (lit "-"))
      (cmd_missing_del))
    (alt_shift
      ((tok CMD)
        (tok MISSING))
      (cmd_missing_show))
    (alt
      ((tok CMD)
        (ref name)
        (quantified
          (ref params)
          (opt))
        (ref block))
      (cmd_def 2 3 4))
    (alt
      ((tok CMD)
        (ref name)
        (quantified
          (ref params)
          (opt))
        (ref stmt))
      (cmd_def 2 3 4))
    (alt
      ((tok CMD)
        (ref name)
        (lit "-"))
      (cmd_del 2))
    (alt_shift
      ((tok CMD)
        (ref name))
      (cmd_show 2))
    (alt_shift
      ((tok CMD))
      (cmd_list)))
  (rule
    (name params)
    (alt
      ((tok LPAREN_TIGHT)
        (list_req
          L
          (plain name))
        (lit ")"))
      2))
  (rule
    (name key_def)
    (alt
      ((tok KEY)
        (ref key_combo)
        (ref cmdlist))
      (key 2 3))
    (alt
      ((tok KEY)
        (ref key_combo)
        (tok STRING_SQ))
      (key 2 3))
    (alt
      ((tok KEY)
        (ref key_combo)
        (tok STRING_DQ))
      (key 2 3))
    (alt
      ((tok KEY)
        (ref key_combo)
        (lit "-"))
      (key_del 2))
    (alt_shift
      ((tok KEY))
      (key_list)))
  (rule
    (name key_combo)
    (alt
      ((tok IDENT)
        (lit "="))
      (key_combo_eq 1))
    (alt
      ((tok IDENT)))
    (alt
      ((tok STRING_SQ)))
    (alt
      ((tok STRING_DQ)))
    (alt
      ((tok INTEGER)))
    (alt
      ((tok REAL)))
    (alt
      ((tok VARIABLE)))
    (alt
      ((tok VAR_BRACED)))
    (alt
      ((tok FLAG))))
  (rule
    (name set_stmt)
    (alt
      ((tok SET)
        (ref name)
        (lit "-"))
      (set_reset 2))
    (alt
      ((tok SET)
        (ref name)
        (ref word))
      (set 2 3))
    (alt_shift
      ((tok SET)
        (ref name))
      (set_show 2))
    (alt_shift
      ((tok SET))
      (set_list)))
  (rule
    (name expr)
    (alt
      ((ref coalesce))))
  (rule
    (name coalesce)
    (alt
      ((ref sum)
        (lit "??")
        (ref coalesce))
      (default 1 3))
    (alt
      ((ref sum))))
  (rule
    (name sum)
    (alt
      ((ref sum)
        (lit "+")
        (ref term))
      (add 1 3))
    (alt
      ((ref sum)
        (lit "-")
        (ref term))
      (sub 1 3))
    (alt
      ((ref term))))
  (rule
    (name term)
    (alt
      ((ref term)
        (lit "*")
        (ref factor))
      (mul 1 3))
    (alt
      ((ref term)
        (lit "/")
        (ref factor))
      (div 1 3))
    (alt
      ((ref term)
        (lit "%")
        (ref factor))
      (mod 1 3))
    (alt
      ((ref factor))))
  (rule
    (name factor)
    (alt
      ((ref base)
        (lit "**")
        (ref factor))
      (pow 1 3))
    (alt
      ((ref base))))
  (rule
    (name base)
    (alt
      ((lit "(")
        (ref expr)
        (lit ")"))
      2)
    (alt
      ((lit "-")
        (ref base))
      (neg 2))
    (alt
      ((lit "+")
        (ref base))
      2)
    (alt
      ((ref atom))))
  (rule
    (name atom)
    (alt
      ((tok VARIABLE)))
    (alt
      ((tok VAR_BRACED)))
    (alt
      ((tok INTEGER)))
    (alt
      ((tok REAL)))
    (alt
      ((tok STRING_DQ)))
    (alt
      ((tok STRING_SQ)))
    (alt
      ((ref subshell_capture))))
  (rule
    (name shift_value)
    (alt
      ((tok SHIFT))
      (shift_value)))
  (rule
    (name bare_value)
    (alt
      ((tok IDENT))))
  (rule
    (name assign_rhs)
    (alt
      ((ref shift_value)))
    (alt
      ((ref bare_value)))
    (alt
      ((ref expr))))
  (rule
    (name try_subject)
    (alt
      ((ref shift_value)))
    (alt
      ((ref bare_value)))
    (alt
      ((ref expr))))
  (rule
    (name list_literal)
    (alt
      ((tok LIST_START)
        (quantified
          (ref list_item)
          (zero_plus))
        (lit "]"))
      (list ...2)))
  (rule
    (name list_item)
    (alt
      ((tok IDENT)))
    (alt
      ((tok STRING_SQ)))
    (alt
      ((tok STRING_DQ)))
    (alt
      ((tok INTEGER)))
    (alt
      ((tok REAL)))
    (alt
      ((tok VARIABLE)))
    (alt
      ((tok VAR_BRACED)))
    (alt
      ((tok FLAG)))
    (alt
      ((tok REGEX)))
    (alt
      ((lit "-")))
    (alt
      ((ref subshell_capture)))))
