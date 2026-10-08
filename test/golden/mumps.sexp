(grammar
  (section `lexer`)
  (state
    `state`
    (assign `beg` `1`)
    (assign `pat` `0`)
    (assign `dep` `0`))
  (tokens `tokens` `ident` `integer` `zdigits` `real` `string` `indent` `sp` `spaces` `patend` `comment` `dot` `caret` `at` `dollar` `lparen` `rparen` `comma` `colon` `pipe` `eq` `plus` `minus` `star` `slash` `backslash` `underscore` `not` `lt` `gt` `question` `lbracket` `rbracket` `exclaim` `hash` `ampersand` `starstar` `noteq` `notlt` `notgt` `notques` `notlbracket` `notrbracket` `notampersand` `notexclaim` `lteq` `gteq` `eqeq` `sortsafter` `followseq` `sortsaftereq` `notsortsafter` `quesat` `newline` `eof` `err`)
  (after
    `after`
    (assign `beg` `0`))
  (lex_rule
    _
    (guards
      `@`
      (guard _ `pat` _ _)
      (guard _ `pre` `>` `0`))
    `patend`
    (lex_action `hold` _)
    (set_action `pat` `0`)
    (set_action `pre` `0`))
  (lex_rule
    _
    (guards
      `@`
      (guard _ `beg` _ _)
      (guard _ `pre` `>` `0`))
    `indent`
    (counted `pre` `counted` `'.'`))
  (lex_rule
    _
    (guards
      `@`
      (guard `!` `beg` _ _)
      (guard _ `pre` `==` `1`))
    `sp`)
  (lex_rule
    _
    (guards
      `@`
      (guard `!` `beg` _ _)
      (guard _ `pre` `>` `1`))
    `spaces`
    (set_action `pre` `0`))
  (lex_rule
    `[\\r]* [\\n]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `newline`
    (set_action `beg` `1`))
  (lex_rule
    `[\\r\\n]`
    (guards
      `@`
      (guard _ `pat` _ _))
    `patend`
    (lex_action `hold` _)
    (set_action `pat` `0`)
    (set_action `dep` `0`))
  (lex_rule `';' [^\\n]*` _ `comment`)
  (lex_rule `'"' ([^"\\n] | '""')* '"'` _ `string`)
  (lex_rule
    `[0-9]+`
    (guards
      `@`
      (guard _ `pat` _ _))
    `integer`)
  (lex_rule
    `[0-9]* '.' [0-9]+ [Ee] [+-]? [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `real`)
  (lex_rule
    `[0-9]+ '.'? [Ee] [+-]? [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `real`)
  (lex_rule
    `[0-9]* '.' [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `real`)
  (lex_rule
    `[0-9]+ '.'`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `real`)
  (lex_rule
    `'0' [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `zdigits`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule
    `'?@'`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `quesat`)
  (lex_rule
    `'?' / [0-9.]+ [Ee] [+-]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`)
  (lex_rule
    `'?' / [0-9.]+ [Ee] [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`)
  (lex_rule
    `'?' / [0-9.]+ [Ee] [0-9]+ [ACELNPUacelnpu"'.(]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`
    (set_action `pat` `1`))
  (lex_rule
    `'?' / [0-9.]+ [ACELNPUacelnpu"(]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`
    (set_action `pat` `1`))
  (lex_rule
    `'?' / [0-9.]+ "'"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`
    (set_action `pat` `1`))
  (lex_rule
    `'?' / [0-9.]+ "'?"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`)
  (lex_rule
    `'?'`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `question`)
  (lex_rule
    `"'?" / [0-9.]+ [Ee] [+-]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`)
  (lex_rule
    `"'?" / [0-9.]+ [Ee] [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`)
  (lex_rule
    `"'?" / [0-9.]+ [Ee] [0-9]+ [ACELNPUacelnpu"'.(]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`
    (set_action `pat` `1`))
  (lex_rule
    `"'?" / [0-9.]+ [ACELNPUacelnpu"(]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`
    (set_action `pat` `1`))
  (lex_rule
    `"'?" / [0-9.]+ "'"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`
    (set_action `pat` `1`))
  (lex_rule
    `"'?" / [0-9.]+ "'?"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`)
  (lex_rule
    `"'?"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notques`)
  (lex_rule
    `"'" / [0-9.]+ [Ee] [+-]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `not`)
  (lex_rule
    `"'" / [0-9.]+ [Ee] [0-9]+`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `not`)
  (lex_rule
    `"'" / [0-9.]+ [Ee] [0-9]+ [ACELNPUacelnpu"'.(]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `not`
    (set_action `pat` `1`))
  (lex_rule
    `"'" / [0-9.]+ [ACELNPUacelnpu"(]`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `not`
    (set_action `pat` `1`))
  (lex_rule
    `"'" / [0-9.]+ "'"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `not`
    (set_action `pat` `1`))
  (lex_rule
    `"'" / [0-9.]+ "'?"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `not`)
  (lex_rule
    `'('`
    (guards
      `@`
      (guard _ `pat` _ _))
    `lparen`
    (step_action `dep` `++`))
  (lex_rule
    `')'`
    (guards
      `@`
      (guard _ `pat` _ _)
      (guard _ `dep` _ _))
    `rparen`
    (step_action `dep` `--`))
  (lex_rule
    `[^0-9.A-Za-z%"('_\\r\\n]`
    (guards
      `@`
      (guard _ `pat` _ _)
      (guard `!` `dep` _ _))
    `patend`
    (lex_action `hold` _)
    (set_action `pat` `0`))
  (lex_rule
    `"'" / [^"]`
    (guards
      `@`
      (guard _ `pat` _ _)
      (guard `!` `dep` _ _))
    `patend`
    (lex_action `hold` _)
    (set_action `pat` `0`))
  (lex_rule
    `'_'`
    (guards
      `@`
      (guard _ `pat` _ _))
    `patend`
    (lex_action `hold` _)
    (set_action `pat` `0`))
  (lex_rule
    `('%' [A-Za-z0-9]* | [A-Za-z])`
    (guards
      `@`
      (guard _ `pat` _ _))
    `ident`)
  (lex_rule
    `[%A-Za-z][A-Za-z0-9]*`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `ident`)
  (lex_rule
    `"]]="`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `sortsaftereq`)
  (lex_rule
    `"']]"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notsortsafter`)
  (lex_rule
    `"'="`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `noteq`)
  (lex_rule
    `"'<"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notlt`)
  (lex_rule
    `"'>"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notgt`)
  (lex_rule
    `"'["`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notlbracket`)
  (lex_rule
    `"']"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notrbracket`)
  (lex_rule
    `"'&"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notampersand`)
  (lex_rule
    `"'!"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `notexclaim`)
  (lex_rule
    `"**"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `starstar`)
  (lex_rule
    `"<="`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `lteq`)
  (lex_rule
    `">="`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `gteq`)
  (lex_rule
    `"=="`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `eqeq`)
  (lex_rule
    `"]]"`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `sortsafter`)
  (lex_rule
    `"]="`
    (guards
      `@`
      (guard `!` `pat` _ _))
    `followseq`)
  (lex_rule `'.'` _ `dot`)
  (lex_rule `'^'` _ `caret`)
  (lex_rule `'@'` _ `at`)
  (lex_rule `'$'` _ `dollar`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `','` _ `comma`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `'|'` _ `pipe`)
  (lex_rule `'='` _ `eq`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'/'` _ `slash`)
  (lex_rule `'\\\\'` _ `backslash`)
  (lex_rule `'_'` _ `underscore`)
  (lex_rule `"'"` _ `not`)
  (lex_rule `'<'` _ `lt`)
  (lex_rule `'>'` _ `gt`)
  (lex_rule `'['` _ `lbracket`)
  (lex_rule `']'` _ `rbracket`)
  (lex_rule `'!'` _ `exclaim`)
  (lex_rule `'#'` _ `hash`)
  (lex_rule `'&'` _ `ampersand`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"mumps"`)
  (manifest
    (conflict `shift` `deviceparam → expr` _ `1` `# USE dev:(x): the parentheses group an expression, the same value as a one-parameter list`)
    (conflict `shift` `patatom → repcount IDENT+` _ `1` `# pattern code letters after a repeat count run as far as they go`)
    (conflict `shift` `lvn → IDENT` _ `1` `# name= after USE dev: is a keyword device parameter`)
    (conflict `shift` `rgvn → "^" "|" expr "|" IDENT` _ `1` `# ( after an extended global name starts its subscripts`)
    (conflict `shift` `rgvn → "^" "|" expr "," expr "|" IDENT` _ `1` `# ( after an extended global name starts its subscripts`)
    (conflict `shift` `extrinsicref → "@" xatom` _ `2` `# ( after $$@X starts its actual list`)
    (conflict `shift` `extrinsicref → "@" xatom "^" routineref` _ `1` `# ( after $$@X^RTN starts its actual list`)
    (conflict `reduce` `actual? → ε` `L(actual?)? → ε` `4` `# an empty () argument list holds one absent actual`))
  (as
    `ident`
    _
    (as_entry _ `fn` _)
    (as_entry _ `sv` _)
    (as_entry _ `isv` _)
    (as_entry _ `ssvn` _)
    (as_entry _ `self` _)
    (as_entry _ `cmd` _))
  (errors
    (name_pair `cmd` `"a command"`)
    (name_pair `expr` `"an expression"`)
    (name_pair `atom` `"an operand"`)
    (name_pair `binop` `"an operator"`)
    (name_pair `glvn` `"a variable"`)
    (name_pair `routineref` `"a routine name"`)
    (name_pair `patatom` `"a pattern"`))
  (display
    (name_pair `IDENT` `"a name"`)
    (name_pair `INTEGER` `"a number"`)
    (name_pair `ZDIGITS` `"a number"`)
    (name_pair `REAL` `"a number"`)
    (name_pair `STRING` `"a string"`)
    (name_pair `SP` `"a space"`)
    (name_pair `SPACES` `"a space"`)
    (name_pair `PATEND` `"the end of the pattern"`)
    (name_pair `COMMENT` `"a comment"`)
    (name_pair `NEWLINE` `"the end of the line"`)
    (name_pair `EOF` `"the end of the line"`)
    (name_pair `INDENT` `"a leading space"`)
    (name_pair `QUESAT` `"\\"?@\\""`)
    (name_pair `FN` `"a function name"`)
    (name_pair `TEXT` `"a function name"`)
    (name_pair `SELECT` `"a function name"`)
    (name_pair `JUSTIFY` `"a function name"`)
    (name_pair `INCREMENT` `"a function name"`)
    (name_pair `ISV` `"a special variable name"`)
    (name_pair `SV` `"a special variable name"`)
    (name_pair `SSVN` `"a structured system variable name"`)
    (name_pair `SET` `"a command"`)
    (name_pair `NEW` `"a command"`)
    (name_pair `MERGE` `"a command"`)
    (name_pair `KILL` `"a command"`)
    (name_pair `IF` `"a command"`)
    (name_pair `ELSE` `"a command"`)
    (name_pair `FOR` `"a command"`)
    (name_pair `DO` `"a command"`)
    (name_pair `GOTO` `"a command"`)
    (name_pair `QUIT` `"a command"`)
    (name_pair `BREAK` `"a command"`)
    (name_pair `HANG` `"a command"`)
    (name_pair `HALT` `"a command"`)
    (name_pair `JOB` `"a command"`)
    (name_pair `XECUTE` `"a command"`)
    (name_pair `VIEW` `"a command"`)
    (name_pair `OPEN` `"a command"`)
    (name_pair `USE` `"a command"`)
    (name_pair `READ` `"a command"`)
    (name_pair `WRITE` `"a command"`)
    (name_pair `CLOSE` `"a command"`)
    (name_pair `LOCK` `"a command"`)
    (name_pair `TSTART` `"a command"`)
    (name_pair `TCOMMIT` `"a command"`)
    (name_pair `TROLLBACK` `"a command"`)
    (name_pair `TRESTART` `"a command"`)
    (name_pair `ZWRITE` `"a command"`)
    (name_pair `ZBREAK` `"a command"`)
    (name_pair `ZHALT` `"a command"`)
    (name_pair `ZKILL` `"a command"`)
    (name_pair `ZSYSTEM` `"a command"`))
  (op
    (op_map `"'="` `"noteq"`)
    (op_map `"'<"` `"notlt"`)
    (op_map `"'>"` `"notgt"`)
    (op_map `"'?"` `"notques"`)
    (op_map `"'["` `"notlbracket"`)
    (op_map `"']"` `"notrbracket"`)
    (op_map `"'&"` `"notampersand"`)
    (op_map `"'!"` `"notexclaim"`)
    (op_map `"=="` `"eqeq"`)
    (op_map `"]]"` `"sortsafter"`)
    (op_map `"]="` `"followseq"`)
    (op_map `"]]="` `"sortsaftereq"`)
    (op_map `"']]"` `"notsortsafter"`))
  (schema
    (kind_decl
      (kinds `routine`)
      (roles
        (role
          rest
          `lines`
          (type `label` `line`)
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
        (role
          _
          `formals`
          (type `group`)
          opt)
        (role
          _
          `dots`
          (type `group`)
          opt)
        (role rest `cmds` _ _))
      _
      _)
    (kind_decl
      (kinds `line`)
      (roles
        (role
          _
          `indent`
          (type `leaf`)
          _)
        (role rest `cmds` _ _))
      _
      _)
    (kind_decl
      (kinds `commands`)
      (roles
        (role rest `cmds` _ _))
      _
      _)
    (kind_decl
      (kinds `set` `new` `kill` `merge` `do` `goto` `break` `hang` `job` `xecute` `view` `open` `use` `read` `write` `close` `lock` `zwrite` `zbreak` `zkill` `zsystem`)
      (roles
        (role
          _
          `pc`
          (type `postcond`)
          opt)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `quit` `zhalt`)
      (roles
        (role
          _
          `pc`
          (type `postcond`)
          opt)
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `halt` `tcommit` `trollback` `trestart`)
      (roles
        (role
          _
          `pc`
          (type `postcond`)
          opt))
      _
      _)
    (kind_decl
      (kinds `tstart`)
      (roles
        (role
          _
          `pc`
          (type `postcond`)
          opt)
        (role _ `vars` _ opt)
        (role
          _
          `params`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `if`)
      (roles
        (role rest `conds` _ _))
      _
      _)
    (kind_decl
      (kinds `else`)
      (roles)
      _
      _)
    (kind_decl
      (kinds `for`)
      (roles
        (role
          _
          `var`
          (type `lvar` `"@subs"` `"@name"`)
          opt)
        (role rest `params` _ _))
      _
      _)
    (kind_decl
      (kinds `postcond`)
      (roles
        (role _ `cond` _ _))
      _
      _)
    (kind_decl
      (kinds `"="`)
      (roles
        (role _ `target` _ _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `setmulti`)
      (roles
        (role _ `value` _ _)
        (role rest `targets` _ _))
      _
      _)
    (kind_decl
      (kinds `setfn`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `target` _ _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `setisv`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `exclusive`)
      (roles
        (role rest `names` _ _))
      _
      _)
    (kind_decl
      (kinds `range`)
      (roles
        (role _ `start` _ _)
        (role _ `inc` _ _)
        (role _ `end` _ opt))
      _
      _)
    (kind_decl
      (kinds `call`)
      (roles
        (role
          _
          `ref`
          (type `ref` `"@ref"`)
          _)
        (role
          _
          `args`
          (type `group`)
          opt)
        (role
          _
          `pc`
          (type `postcond`)
          opt))
      _
      _)
    (kind_decl
      (kinds `ref`)
      (roles
        (role
          _
          `label`
          (type `leaf`)
          opt)
        (role _ `offset` _ opt)
        (role _ `routine` _ opt))
      _
      _)
    (kind_decl
      (kinds `"@ref"`)
      (roles
        (role _ `label` _ _)
        (role _ `offset` _ opt)
        (role _ `routine` _ opt))
      _
      _)
    (kind_decl
      (kinds `arg`)
      (roles
        (role _ `value` _ _)
        (role
          _
          `pc`
          (type `postcond`)
          opt))
      _
      _)
    (kind_decl
      (kinds `jobarg`)
      (roles
        (role
          _
          `ref`
          (type `ref` `"@ref"`)
          _)
        (role
          _
          `args`
          (type `group`)
          opt)
        (role
          _
          `params`
          (type `jobparams`)
          opt)
        (role _ `env` _ opt))
      _
      _)
    (kind_decl
      (kinds `jobparams`)
      (roles
        (role
          _
          `params`
          (type `group`)
          opt)
        (role _ `timeout` _ opt))
      _
      _)
    (kind_decl
      (kinds `viewarg`)
      (roles
        (role _ `value` _ _)
        (role
          _
          `params`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `openarg`)
      (roles
        (role _ `device` _ _)
        (role
          _
          `params`
          (type `group`)
          opt)
        (role _ `timeout` _ opt)
        (role _ `mnemonic` _ opt))
      _
      _)
    (kind_decl
      (kinds `devicearg`)
      (roles
        (role _ `device` _ _)
        (role
          _
          `params`
          (type `group`)
          opt)
        (role _ `mnemonic` _ opt))
      _
      _)
    (kind_decl
      (kinds `attr`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `keyword`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `input`)
      (roles
        (role _ `target` _ _)
        (role _ `count` _ opt)
        (role _ `timeout` _ opt))
      _
      _)
    (kind_decl
      (kinds `char`)
      (roles
        (role _ `target` _ _)
        (role _ `timeout` _ opt))
      _
      _)
    (kind_decl
      (kinds `charindir`)
      (roles
        (role _ `expr` _ _)
        (role _ `timeout` _ opt))
      _
      _)
    (kind_decl
      (kinds `prompt`)
      (roles
        (role
          _
          `text`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `control`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `"*"`)
      (roles
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `tab`)
      (roles
        (role _ `column` _ _))
      _
      _)
    (kind_decl
      (kinds `posformat`)
      (roles
        (role
          _
          `tab`
          (type `tab`)
          opt)
        (role
          rest
          `marks`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `"lock="` `"lock+"` `"lock-"`)
      (roles
        (role _ `timeout` _ opt)
        (role rest `refs` _ _))
      _
      _)
    (kind_decl
      (kinds `vars`)
      (roles
        (role rest `names` _ _))
      _
      _)
    (kind_decl
      (kinds `all`)
      (roles)
      _
      _)
    (kind_decl
      (kinds `prefix` `gprefix`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `span`)
      (roles
        (role _ `start` _ opt)
        (role _ `end` _ opt))
      _
      _)
    (kind_decl
      (kinds `zwarg`)
      (roles
        (role _ `ref` _ _)
        (role rest `suffixes` _ _))
      _
      _)
    (kind_decl
      (kinds `depth` `limit`)
      (roles
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `test`)
      (roles
        (role
          _
          `op`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `param`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `byref`)
      (roles
        (role _ `name` _ _))
      _
      _)
    (kind_decl
      (kinds `expr`)
      (roles
        (role _ `first` _ _)
        (role rest `tails` _ _))
      _
      _)
    (kind_decl
      (kinds `binop`)
      (roles
        (role
          _
          `op`
          (type `leaf`)
          _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `"?"` `"'?"`)
      (roles
        (role
          _
          `pattern`
          (type `group`)
          _))
      _
      _)
    (kind_decl
      (kinds `"?@"` `"'?@"`)
      (roles
        (role _ `expr` _ _))
      _
      _)
    (kind_decl
      (kinds `unary`)
      (roles
        (role
          _
          `op`
          (type `leaf`)
          _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `lvar`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `subs`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `gvar`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `subs`
          (type `group`)
          opt)
        (role _ `env` _ opt)
        (role _ `uci` _ opt))
      _
      _)
    (kind_decl
      (kinds `naked`)
      (roles
        (role rest `subs` _ _))
      _
      _)
    (kind_decl
      (kinds `ssvn`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `subs`
          (type `group`)
          opt)
        (role _ `env` _ opt))
      _
      _)
    (kind_decl
      (kinds `"@name"` `"@args"` `"@gname"`)
      (roles
        (role _ `expr` _ _))
      _
      _)
    (kind_decl
      (kinds `"@subs"` `"@gsubs"` `"@ssvn"`)
      (roles
        (role _ `expr` _ _)
        (role
          _
          `subs`
          (type `group`)
          _))
      _
      _)
    (kind_decl
      (kinds `intrinsic`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `args`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `extrinsic`)
      (roles
        (role _ `label` _ opt)
        (role _ `routine` _ opt)
        (role
          _
          `args`
          (type `group`)
          opt))
      _
      _)
    (kind_decl
      (kinds `select`)
      (roles
        (role
          rest
          `cases`
          (type `case`)
          _))
      _
      _)
    (kind_decl
      (kinds `case`)
      (roles
        (role _ `cond` _ _)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `text`)
      (roles
        (role _ `label` _ opt)
        (role _ `offset` _ opt)
        (role _ `routine` _ opt))
      _
      _)
    (kind_decl
      (kinds `pat`)
      (roles
        (role
          _
          `count`
          (type `count`)
          opt)
        (role
          _
          `codes`
          (type `group`)
          opt)
        (role
          _
          `text`
          (type `group`)
          opt)
        (role _ `capture` _ opt)
        (role
          rest
          `alts`
          (type `group`)
          _))
      _
      _)
    (kind_decl
      (kinds `count`)
      (roles
        (role
          _
          `min`
          (type `leaf`)
          opt)
        (role
          _
          `max`
          (type `leaf`)
          opt))
      _
      _))
  (rule
    (name `name`)
    (alt
      _
      ((tok `IDENT`))
      _
      _))
  (rule
    (name `label`)
    (alt
      _
      ((tok `IDENT`))
      _
      _)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `ZDIGITS`))
      _
      _))
  (rule
    (name `PATIND`)
    (alt
      _
      ((tok `QUESAT`))
      _
      _))
  (rule
    (name `COLIND`)
    (alt
      _
      ((tok `QUESAT`))
      _
      _))
  (rule
    (start `routine`)
    (alt
      _
      ((ref `lines`))
      (node
        `routine`
        (spread `1`))
      _))
  (rule
    (name `lines`)
    (alt
      _
      ((quantified
          (ref `line`)
          (opt)))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `lines`)
        (skip
          (tok `NEWLINE`))
        (quantified
          (ref `line`)
          (opt)))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (start `commands`)
    (alt
      _
      ((ref `cmds`)
        (group
          opt
          ((skip
              (tok `COMMENT`)))))
      (node
        `commands`
        (spread `1`))
      _))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)
      _))
  (rule
    (start `gotoarg`)
    (alt
      _
      ((ref `gotoarg`))
      (pos `1`)
      _))
  (rule
    (start `command`)
    (alt
      _
      ((ref `cmd`))
      (node
        `commands`
        (pos `1`))
      _))
  (rule
    (name `line`)
    (alt
      _
      ((ref `labelline`)
        (group
          opt
          ((skip
              (tok `COMMENT`)))))
      (pos `1`)
      _)
    (alt
      _
      ((ref `cmdline`)
        (group
          opt
          ((skip
              (tok `COMMENT`)))))
      (pos `1`)
      _)
    (alt
      _
      ((skip
          (tok `COMMENT`)))
      (null)
      _))
  (rule
    (name `labelline`)
    (alt
      _
      ((ref `label`)
        (group
          opt
          ((ref `formallist`))))
      (node
        `label`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `label`)
        (group
          opt
          ((ref `formallist`)))
        (skip
          (ref `sep`))
        (group
          opt
          ((ref `cmds`))))
      (node
        `label`
        (pos `1`)
        (pos `2`)
        (null)
        (spread `4`))
      _)
    (alt
      _
      ((ref `label`)
        (skip
          (ref `sep`))
        (ref `dotlevel`)
        (group
          opt
          ((ref `cmds`))))
      (node
        `label`
        (pos `1`)
        (null)
        (pos `3`)
        (spread `4`))
      _))
  (rule
    (name `formallist`)
    (alt
      _
      ((lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `name`))))
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `cmdline`)
    (alt
      _
      ((tok `INDENT`)
        (group
          opt
          ((ref `cmds`))))
      (node
        `line`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `dotlevel`)
    (alt
      _
      ((quantified
          (ref `dot`)
          (one_plus)))
      (pos `1`)
      _))
  (rule
    (name `dot`)
    (alt
      _
      ((lit `"."`)
        (group
          opt
          ((skip
              (ref `sep`)))))
      (pos `1`)
      _))
  (rule
    (name `cmd`)
    (alt
      _
      ((ref `set`))
      _
      _)
    (alt
      _
      ((ref `new`))
      _
      _)
    (alt
      _
      ((ref `merge`))
      _
      _)
    (alt
      _
      ((ref `kill`))
      _
      _)
    (alt
      _
      ((ref `if`))
      _
      _)
    (alt
      _
      ((ref `else`))
      _
      _)
    (alt
      _
      ((ref `for`))
      _
      _)
    (alt
      _
      ((ref `do`))
      _
      _)
    (alt
      _
      ((ref `goto`))
      _
      _)
    (alt
      _
      ((ref `quit`))
      _
      _)
    (alt
      _
      ((ref `break`))
      _
      _)
    (alt
      _
      ((ref `hang`))
      _
      _)
    (alt
      _
      ((ref `halt`))
      _
      _)
    (alt
      _
      ((ref `job`))
      _
      _)
    (alt
      _
      ((ref `xecute`))
      _
      _)
    (alt
      _
      ((ref `view`))
      _
      _)
    (alt
      _
      ((ref `open`))
      _
      _)
    (alt
      _
      ((ref `use`))
      _
      _)
    (alt
      _
      ((ref `read`))
      _
      _)
    (alt
      _
      ((ref `write`))
      _
      _)
    (alt
      _
      ((ref `close`))
      _
      _)
    (alt
      _
      ((ref `lock`))
      _
      _)
    (alt
      _
      ((ref `tstart`))
      _
      _)
    (alt
      _
      ((ref `tcommit`))
      _
      _)
    (alt
      _
      ((ref `trollback`))
      _
      _)
    (alt
      _
      ((ref `trestart`))
      _
      _)
    (alt
      _
      ((ref `zwrite`))
      _
      _)
    (alt
      _
      ((ref `zbreak`))
      _
      _)
    (alt
      _
      ((ref `zhalt`))
      _
      _)
    (alt
      _
      ((ref `zkill`))
      _
      _)
    (alt
      _
      ((ref `zsystem`))
      _
      _))
  (rule
    (name `cmds`)
    (alt
      _
      ((ref `cmdseq`)
        (group
          opt
          ((skip
              (ref `sep`)))))
      (pos `1`)
      _))
  (rule
    (name `cmdseq`)
    (alt
      _
      ((ref `cmd`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `cmdseq`)
        (skip
          (ref `sep`))
        (ref `cmd`))
      (list
        (spread `1`)
        (pos `3`))
      _))
  (rule
    (name `sep`)
    (alt
      _
      ((tok `SP`))
      _
      _)
    (alt
      _
      ((tok `SPACES`))
      _
      _))
  (rule
    (name `postcond`)
    (alt
      _
      ((lit `":"`)
        (ref `expr`))
      (node
        `postcond`
        (pos `2`))
      _))
  (rule
    (name `set`)
    (alt
      _
      ((tok `SET`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `setarg`)))
      (node
        `set`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `setarg`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"="`)
        (ref `expr`))
      (node
        `=`
        (node
          `@name`
          (pos `2`))
        (pos `4`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _)
    (alt
      _
      ((ref `glvn`)
        (lit `"="`)
        (ref `expr`))
      (node
        `=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `setglvn`))
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      (node
        `setmulti`
        (pos `5`)
        (spread `2`))
      _)
    (alt
      _
      ((ref `setfn`)
        (lit `"="`)
        (ref `expr`))
      (node
        `=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `SV`)
        (lit `"="`)
        (ref `expr`))
      (node
        `=`
        (node
          `setisv`
          (pos `2`))
        (pos `4`))
      _))
  (rule
    (name `setglvn`)
    (alt
      _
      ((ref `glvn`))
      _
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@name`
        (pos `2`))
      _)
    (alt
      _
      ((ref `setfn`))
      _
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `SV`))
      (node
        `setisv`
        (pos `2`))
      _))
  (rule
    (name `setfn`)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (ref `setglvn`)
        (lit `","`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `setfn`
        (pos `2`)
        (pos `4`)
        (spread `6`))
      _)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (ref `setglvn`)
        (lit `")"`))
      (node
        `setfn`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `new`)
    (alt
      `>`
      ((tok `NEW`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `new`
        (pos `2`))
      _)
    (alt
      _
      ((tok `NEW`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `newarg`)))))
      (node
        `new`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `newarg`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((lit `"$"`)
        (ref `name`))
      (node
        `intrinsic`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `lname`))
        (lit `")"`))
      (node
        `exclusive`
        (spread `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `merge`)
    (alt
      _
      ((tok `MERGE`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `mergearg`)))
      (node
        `merge`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `mergearg`)
    (alt
      _
      ((ref `mglvn`)
        (lit `"="`)
        (ref `mglvn`))
      (node
        `=`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `mglvn`)
    (alt
      _
      ((ref `glvn`))
      _
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@name`
        (pos `2`))
      _))
  (rule
    (name `kill`)
    (alt
      `>`
      ((tok `KILL`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `kill`
        (pos `2`))
      _)
    (alt
      _
      ((tok `KILL`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `killarg`)))))
      (node
        `kill`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `killarg`)
    (alt
      _
      ((ref `glvn`))
      _
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `lname`))
        (lit `")"`))
      (node
        `exclusive`
        (spread `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `lname`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@name`
        (pos `2`))
      _))
  (rule
    (name `if`)
    (alt
      `>`
      ((tok `IF`))
      (node `if`)
      _)
    (alt
      _
      ((tok `IF`)
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `expr`)))))
      (node
        `if`
        (spread `3`))
      _))
  (rule
    (name `else`)
    (alt
      _
      ((tok `ELSE`))
      (node `else`)
      _))
  (rule
    (name `for`)
    (alt
      `>`
      ((tok `FOR`))
      (node `for`)
      _)
    (alt
      _
      ((tok `FOR`)
        (skip
          (tok `SP`)))
      (node `for`)
      _)
    (alt
      _
      ((tok `FOR`)
        (skip
          (tok `SP`))
        (ref `forargs`))
      (pos `3`)
      _))
  (rule
    (name `forargs`)
    (alt
      _
      ((ref `lvn`)
        (lit `"="`)
        (list_req
          `L`
          (plain `forparam`)))
      (node
        `for`
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"="`)
        (list_req
          `L`
          (plain `forparam`)))
      (node
        `for`
        (node
          `@name`
          (pos `2`))
        (spread `4`))
      _))
  (rule
    (name `forparam`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`))
      (node
        `range`
        (pos `1`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      (node
        `range`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `do`)
    (alt
      `>`
      ((tok `DO`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `do`
        (pos `2`))
      _)
    (alt
      _
      ((tok `DO`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `doarg`)))))
      (node
        `do`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `doarg`)
    (alt
      _
      ((ref `indirrefcmd`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `postcond`))))
      (node
        `call`
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `postcond`))))
      (node
        `call`
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (ref `postcond`))
      (node
        `call`
        (node
          `@ref`
          (pos `2`))
        (null)
        (pos `3`))
      _))
  (rule
    (name `goto`)
    (alt
      _
      ((tok `GOTO`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `gotoarg`)))
      (node
        `goto`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `gotoarg`)
    (alt
      _
      ((ref `indirrefcmd`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `call`
        (pos `1`)
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `call`
        (pos `1`)
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (ref `postcond`))
      (node
        `call`
        (node
          `@ref`
          (pos `2`))
        (null)
        (pos `3`))
      _))
  (rule
    (name `indirref`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (group
          opt
          ((lit `"+"`)
            (ref `entryoffset`)))
        (group
          opt
          ((lit `"^"`)
            (ref `routineref`))))
      (node
        `@ref`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _))
  (rule
    (name `indirrefcmd`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"+"`)
        (ref `entryoffset`)
        (group
          opt
          ((lit `"^"`)
            (ref `routineref`))))
      (node
        `@ref`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"^"`)
        (ref `routineref`))
      (node
        `@ref`
        (pos `2`)
        (null)
        (pos `4`))
      _))
  (rule
    (name `quit`)
    (alt
      `>`
      ((tok `QUIT`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `quit`
        (pos `2`))
      _)
    (alt
      _
      ((tok `QUIT`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((ref `expr`))))
      (node
        `quit`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `break`)
    (alt
      `>`
      ((tok `BREAK`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `break`
        (pos `2`))
      _)
    (alt
      _
      ((tok `BREAK`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `breakarg`)))))
      (node
        `break`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `breakarg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `arg`
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `hang`)
    (alt
      `>`
      ((tok `HANG`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `hang`
        (pos `2`))
      _)
    (alt
      _
      ((tok `HANG`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `expr`)))))
      (node
        `hang`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `halt`)
    (alt
      _
      ((tok `HALT`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `halt`
        (pos `2`))
      _))
  (rule
    (name `job`)
    (alt
      _
      ((tok `JOB`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `jobarg`)))
      (node
        `job`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `jobarg`)
    (alt
      _
      ((lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `indirrefcmd`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `jobparams`))))
      (node
        `jobarg`
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `entryref`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `jobparams`))))
      (node
        `jobarg`
        (pos `4`)
        (pos `5`)
        (pos `6`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `indirrefcmd`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `jobparams`))))
      (node
        `jobarg`
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `jobparams`))))
      (node
        `jobarg`
        (pos `1`)
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `jobparams`)
    (alt
      _
      ((lit `":"`)
        (group
          opt
          ((ref `deviceparams`)))
        (group
          opt
          ((ref `timeout`))))
      (node
        `jobparams`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `xecute`)
    (alt
      _
      ((tok `XECUTE`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `xecutearg`)))
      (node
        `xecute`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `xecutearg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `arg`
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `view`)
    (alt
      _
      ((tok `VIEW`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `viewarg`)))
      (node
        `view`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `viewarg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((lit `":"`)
            (list_req
              `L`
              (sep_items `expr` `":"`)))))
      (node
        `viewarg`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `open`)
    (alt
      _
      ((tok `OPEN`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `openarg`)))
      (node
        `open`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `openarg`)
    (alt
      _
      ((ref `expr`))
      (node
        `openarg`
        (pos `1`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `openparams`))
      (node
        `openarg`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `openparams`)
        (lit `":"`)
        (ref `expr`))
      (node
        `openarg`
        (pos `1`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (lit `":"`)
        (ref `expr`))
      (node
        `openarg`
        (pos `1`)
        (null)
        (pos `4`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (group
          opt
          ((ref `openparams`)))
        (lit `":"`)
        (group
          opt
          ((ref `expr`)))
        (lit `":"`)
        (ref `expr`))
      (node
        `openarg`
        (pos `1`)
        (pos `3`)
        (pos `5`)
        (pos `7`))
      _))
  (rule
    (name `openparams`)
    (alt
      _
      ((lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `expr`))
      (list
        (pos `1`))
      _))
  (rule
    (name `use`)
    (alt
      _
      ((tok `USE`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `devicearg`)))
      (node
        `use`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `read`)
    (alt
      _
      ((tok `READ`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `readarg`)))
      (node
        `read`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `readarg`)
    (alt
      _
      ((ref `posformat`))
      _
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `control`
        (pos `2`)
        (spread `4`))
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      (node
        `control`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `charindir`
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"*"`)
        (ref `glvn`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `char`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `input`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((ref `glvn`)
        (ref `timeout`))
      (node
        `input`
        (pos `1`)
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((ref `glvn`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `STRING`))
      (node
        `prompt`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"#"`)
        (ref `expr`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `input`
        (node
          `@name`
          (pos `2`))
        (pos `4`)
        (pos `5`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (ref `timeout`))
      (node
        `input`
        (node
          `@name`
          (pos `2`))
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `write`)
    (alt
      `>`
      ((tok `WRITE`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `write`
        (pos `2`))
      _)
    (alt
      _
      ((tok `WRITE`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `writearg`)))))
      (node
        `write`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `writearg`)
    (alt
      _
      ((ref `posformat`))
      _
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `control`
        (pos `2`)
        (spread `4`))
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      (node
        `control`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"*"`)
        (ref `expr`))
      (node
        `*`
        (pos `2`))
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `banghash`)
    (alt
      _
      ((lit `"!"`))
      _
      _)
    (alt
      _
      ((lit `"#"`))
      _
      _))
  (rule
    (name `tabcol`)
    (alt
      _
      ((lit `"?"`)
        (ref `expr`)
        (group
          opt
          ((skip
              (tok `PATEND`)))))
      (node
        `tab`
        (pos `2`))
      _))
  (rule
    (name `posformat`)
    (alt
      _
      ((quantified
          (ref `banghash`)
          (one_plus)))
      (node
        `posformat`
        (named
          `marks`
          (spread `1`)))
      _)
    (alt
      _
      ((quantified
          (ref `banghash`)
          (one_plus))
        (ref `tabcol`))
      (node
        `posformat`
        (named
          `tab`
          (pos `2`))
        (named
          `marks`
          (spread `1`)))
      _)
    (alt
      _
      ((ref `tabcol`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `COLIND`)
        (ref `atom`))
      (node
        `tab`
        (node
          `@name`
          (pos `2`)))
      _))
  (rule
    (name `close`)
    (alt
      _
      ((tok `CLOSE`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `devicearg`)))
      (node
        `close`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `devicearg`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `deviceparams`))
      (node
        `devicearg`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (group
          opt
          ((ref `deviceparams`)))
        (lit `":"`)
        (ref `expr`))
      (node
        `devicearg`
        (pos `1`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `expr`))
      (node
        `devicearg`
        (pos `1`))
      _))
  (rule
    (name `deviceparams`)
    (alt
      _
      ((lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `deviceparam`))
      (list
        (pos `1`))
      _))
  (rule
    (name `deviceparamlist`)
    (alt
      _
      ((list_req
          `L`
          (opt_items `deviceparam` `":"`)))
      _
      _))
  (rule
    (name `deviceparam`)
    (alt
      _
      ((lit `"/"`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      (node
        `attr`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      (node
        `keyword`
        (pos `2`))
      _)
    (alt
      _
      ((ref `name`)
        (lit `"="`)
        (ref `expr`))
      (node
        `attr`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `timeout`)
    (alt
      _
      ((lit `":"`)
        (ref `expr`))
      (pos `2`)
      _))
  (rule
    (name `lock`)
    (alt
      `>`
      ((tok `LOCK`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `lock`
        (pos `2`))
      _)
    (alt
      _
      ((tok `LOCK`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `lockarg`)))))
      (node
        `lock`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `lockarg`)
    (alt
      _
      ((ref `lockref`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock=`
        (pos `2`)
        (pos `1`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (ref `timeout`))
      (node
        `lock=`
        (pos `3`)
        (node
          `@name`
          (pos `2`)))
      _)
    (alt
      _
      ((lit `"+"`)
        (ref `lockname`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock+`
        (pos `3`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"-"`)
        (ref `lockname`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock-`
        (pos `3`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"+"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `lockname`))
        (lit `")"`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock+`
        (pos `5`)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"-"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `lockname`))
        (lit `")"`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock-`
        (pos `5`)
        (spread `3`))
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `lockname`))
        (lit `")"`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock=`
        (pos `4`)
        (spread `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `lockname`)
    (alt
      _
      ((ref `lockref`))
      _
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@name`
        (pos `2`))
      _))
  (rule
    (name `lockref`)
    (alt
      _
      ((ref `lvn`))
      _
      _)
    (alt
      _
      ((ref `gvn`))
      _
      _))
  (rule
    (name `tstart`)
    (alt
      `>`
      ((tok `TSTART`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `tstart`
        (pos `2`))
      _)
    (alt
      _
      ((tok `TSTART`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`)))
      (node
        `tstart`
        (pos `2`))
      _)
    (alt
      _
      ((tok `TSTART`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (ref `tstartarg`)
        (group
          opt
          ((lit `":"`)
            (ref `tstartparams`))))
      (node
        `tstart`
        (pos `2`)
        (pos `4`)
        (pos `6`))
      _)
    (alt
      _
      ((tok `TSTART`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (lit `":"`)
        (ref `tstartparams`))
      (node
        `tstart`
        (pos `2`)
        (null)
        (pos `5`))
      _))
  (rule
    (name `tstartparams`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (sep_items `tstartparam` `":"`))
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `tstartparam`))
      (list
        (pos `1`))
      _))
  (rule
    (name `tstartarg`)
    (alt
      _
      ((lit `"*"`))
      (node `all`)
      _)
    (alt
      _
      ((lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `lname`))))
        (lit `")"`))
      (node
        `vars`
        (spread `2`))
      _)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@name`
        (pos `2`))
      _))
  (rule
    (name `tstartparam`)
    (alt
      _
      ((ref `name`)
        (group
          opt
          ((lit `"="`)
            (ref `expr`))))
      (node
        `param`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `tcommit`)
    (alt
      _
      ((tok `TCOMMIT`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `tcommit`
        (pos `2`))
      _))
  (rule
    (name `trollback`)
    (alt
      _
      ((tok `TROLLBACK`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `trollback`
        (pos `2`))
      _))
  (rule
    (name `trestart`)
    (alt
      _
      ((tok `TRESTART`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `trestart`
        (pos `2`))
      _))
  (rule
    (name `zwrite`)
    (alt
      `>`
      ((tok `ZWRITE`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `zwrite`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ZWRITE`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `zwarg`)))))
      (node
        `zwrite`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `zwarg`)
    (alt
      _
      ((ref `zwref`))
      _
      _)
    (alt
      _
      ((ref `zwref`)
        (quantified
          (ref `zwsuffix`)
          (one_plus)))
      (node
        `zwarg`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `zwref`)
    (alt
      _
      ((ref `name`))
      (node
        `lvar`
        (pos `1`))
      _)
    (alt
      _
      ((ref `name`)
        (ref `zwsubs`))
      (node
        `lvar`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((ref `name`)
        (lit `"*"`))
      (node
        `prefix`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"*"`))
      (node `all`)
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `zwsubs`))
      (node
        `@subs`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _)
    (alt
      _
      ((ref `ssvn`))
      _
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `name`))
      (node
        `gvar`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `name`)
        (ref `zwsubs`))
      (node
        `gvar`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `name`)
        (lit `"*"`))
      (node
        `gprefix`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `naked`
        (spread `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      (node
        `@gsubs`
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`))
      (node
        `@gname`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `name`)
        (group
          opt
          ((ref `zwsubs`))))
      (node
        `gvar`
        (pos `5`)
        (pos `6`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `","`)
        (ref `expr`)
        (lit `"|"`)
        (ref `name`)
        (group
          opt
          ((ref `zwsubs`))))
      (node
        `gvar`
        (pos `7`)
        (pos `8`)
        (pos `3`)
        (pos `5`))
      _))
  (rule
    (name `zwsubs`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (opt_items_nosep `zwsub`))
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `zwsub`)
    (alt
      _
      ((ref `expr`))
      _
      _)
    (alt
      _
      ((lit `"*"`))
      (node `all`)
      _)
    (alt
      _
      ((group
          opt
          ((ref `expr`)))
        (lit `":"`)
        (group
          opt
          ((ref `expr`))))
      (node
        `span`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `zwtest`))
      _
      _))
  (rule
    (name `zwtest`)
    (alt
      _
      ((ref `zwrel`)
        (ref `atom`))
      (node
        `test`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"?"`)
        (ref `pattern`))
      (node
        `?`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"'?"`)
        (ref `pattern`))
      (node
        `'?`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PATIND`)
        (ref `atom`))
      (node
        `?@`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"'?"`)
        (lit `"@"`)
        (ref `atom`))
      (node
        `'?@`
        (pos `3`))
      _))
  (rule
    (name `zwrel`)
    (alt
      _
      ((lit `"="`))
      _
      _)
    (alt
      _
      ((lit `"'="`))
      _
      _)
    (alt
      _
      ((lit `"<"`))
      _
      _)
    (alt
      _
      ((lit `">"`))
      _
      _)
    (alt
      _
      ((lit `"'<"`))
      _
      _)
    (alt
      _
      ((lit `"'>"`))
      _
      _)
    (alt
      _
      ((lit `"<="`))
      _
      _)
    (alt
      _
      ((lit `">="`))
      _
      _)
    (alt
      _
      ((lit `"["`))
      _
      _)
    (alt
      _
      ((lit `"'["`))
      _
      _)
    (alt
      _
      ((lit `"]"`))
      _
      _)
    (alt
      _
      ((lit `"']"`))
      _
      _)
    (alt
      _
      ((lit `"]="`))
      _
      _)
    (alt
      _
      ((lit `"]]"`))
      _
      _)
    (alt
      _
      ((lit `"]]="`))
      _
      _)
    (alt
      _
      ((lit `"']]"`))
      _
      _))
  (rule
    (name `zwsuffix`)
    (alt
      _
      ((lit `"/"`)
        (ref `atom`))
      (node
        `depth`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"#"`)
        (ref `atom`))
      (node
        `limit`
        (pos `2`))
      _)
    (alt
      _
      ((ref `zwtest`))
      _
      _))
  (rule
    (name `zbreak`)
    (alt
      `>`
      ((tok `ZBREAK`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `zbreak`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ZBREAK`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `gotoarg`)))))
      (node
        `zbreak`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `zhalt`)
    (alt
      `>`
      ((tok `ZHALT`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `zhalt`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ZHALT`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((ref `expr`))))
      (node
        `zhalt`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `zkill`)
    (alt
      _
      ((tok `ZKILL`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (list_req
          `L`
          (plain `glvn`)))
      (node
        `zkill`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `zsystem`)
    (alt
      `>`
      ((tok `ZSYSTEM`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `zsystem`
        (pos `2`))
      _)
    (alt
      _
      ((tok `ZSYSTEM`)
        (group
          opt
          ((ref `postcond`)))
        (skip
          (tok `SP`))
        (group
          opt
          ((list_req
              `L`
              (plain `expr`)))))
      (node
        `zsystem`
        (pos `2`)
        (spread `4`))
      _))
  (rule
    (name `entryref`)
    (alt
      _
      ((ref `label`)
        (group
          opt
          ((lit `"+"`)
            (ref `entryoffset`)))
        (group
          opt
          ((lit `"^"`)
            (ref `routineref`))))
      (node
        `ref`
        (pos `1`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((lit `"+"`)
        (ref `entryoffset`)
        (lit `"^"`)
        (ref `routineref`))
      (node
        `ref`
        (null)
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `routineref`))
      (node
        `ref`
        (null)
        (null)
        (pos `2`))
      _))
  (rule
    (name `entryoffset`)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `routineref`)
    (alt
      _
      ((ref `name`))
      _
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      (node
        `@name`
        (pos `2`))
      _))
  (rule
    (name `xatom`)
    (alt
      _
      ((ref `name`))
      (node
        `lvar`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (pos `2`)
      _)
    (alt
      _
      ((ref `literal`))
      _
      _)
    (alt
      _
      ((ref `fn`))
      _
      _))
  (rule
    (name `actuallist`)
    (alt
      _
      ((lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `actual`)
    (alt
      _
      ((lit `"."`)
        (ref `lname`))
      (node
        `byref`
        (pos `2`))
      _)
    (alt
      _
      ((ref `expr`))
      _
      _))
  (rule
    (name `expr`)
    (alt
      `>`
      ((ref `atom`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `atom`)
        (quantified
          (ref `exprtail`)
          (one_plus)))
      (node
        `expr`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `exprtail`)
    (alt
      _
      ((ref `binop`)
        (ref `atom`))
      (node
        `binop`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"?"`)
        (ref `pattern`))
      (node
        `?`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"'?"`)
        (ref `pattern`))
      (node
        `'?`
        (pos `2`))
      _)
    (alt
      _
      ((tok `PATIND`)
        (ref `atom`))
      (node
        `?@`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"'?"`)
        (lit `"@"`)
        (ref `atom`))
      (node
        `'?@`
        (pos `3`))
      _))
  (rule
    (name `atom`)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      (node
        `expr`
        (pos `2`))
      _)
    (alt
      _
      ((ref `unaryop`)
        (ref `atom`))
      (node
        `unary`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (exclude `"@"`))
      (node
        `@name`
        (pos `2`))
      _)
    (alt
      _
      ((ref `glvn`))
      _
      _)
    (alt
      _
      ((ref `literal`))
      _
      _)
    (alt
      _
      ((ref `fn`))
      _
      _))
  (rule
    (name `unaryop`)
    (alt
      _
      ((lit `"'"`))
      _
      _)
    (alt
      _
      ((lit `"+"`))
      _
      _)
    (alt
      _
      ((lit `"-"`))
      _
      _))
  (rule
    (name `binop`)
    (alt
      _
      ((lit `"_"`))
      _
      _)
    (alt
      _
      ((lit `"+"`))
      _
      _)
    (alt
      _
      ((lit `"-"`))
      _
      _)
    (alt
      _
      ((lit `"*"`))
      _
      _)
    (alt
      _
      ((lit `"/"`))
      _
      _)
    (alt
      _
      ((lit `"\\\\"`))
      _
      _)
    (alt
      _
      ((lit `"#"`))
      _
      _)
    (alt
      _
      ((lit `"**"`))
      _
      _)
    (alt
      _
      ((lit `"="`))
      _
      _)
    (alt
      _
      ((lit `"=="`))
      _
      _)
    (alt
      _
      ((lit `"'="`))
      _
      _)
    (alt
      _
      ((lit `"<"`))
      _
      _)
    (alt
      _
      ((lit `">"`))
      _
      _)
    (alt
      _
      ((lit `"'<"`))
      _
      _)
    (alt
      _
      ((lit `"'>"`))
      _
      _)
    (alt
      _
      ((lit `"<="`))
      _
      _)
    (alt
      _
      ((lit `">="`))
      _
      _)
    (alt
      _
      ((lit `"["`))
      _
      _)
    (alt
      _
      ((lit `"]"`))
      _
      _)
    (alt
      _
      ((lit `"'["`))
      _
      _)
    (alt
      _
      ((lit `"']"`))
      _
      _)
    (alt
      _
      ((lit `"]="`))
      _
      _)
    (alt
      _
      ((lit `"]]"`))
      _
      _)
    (alt
      _
      ((lit `"]]="`))
      _
      _)
    (alt
      _
      ((lit `"']]"`))
      _
      _)
    (alt
      _
      ((lit `"&"`))
      _
      _)
    (alt
      _
      ((lit `"!"`))
      _
      _)
    (alt
      _
      ((lit `"'&"`))
      _
      _)
    (alt
      _
      ((lit `"'!"`))
      _
      _))
  (rule
    (name `pattern`)
    (alt
      _
      ((quantified
          (ref `patatom`)
          (one_plus))
        (skip
          (tok `PATEND`)))
      (pos `1`)
      _))
  (rule
    (name `patatom`)
    (alt
      _
      ((ref `repcount`)
        (quantified
          (ref `patcode`)
          (one_plus))
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      (node
        `pat`
        (named
          `count`
          (pos `1`))
        (named
          `codes`
          (pos `2`))
        (named
          `capture`
          (pos `4`)))
      _)
    (alt
      _
      ((ref `repcount`)
        (quantified
          (ref `patcode`)
          (one_plus)))
      (node
        `pat`
        (named
          `count`
          (pos `1`))
        (named
          `codes`
          (pos `2`)))
      _)
    (alt
      _
      ((ref `patcode`)
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      (node
        `pat`
        (named
          `codes`
          (list
            (pos `1`)))
        (named
          `capture`
          (pos `3`)))
      _)
    (alt
      _
      ((ref `patcode`))
      (node
        `pat`
        (named
          `codes`
          (list
            (pos `1`))))
      _)
    (alt
      _
      ((ref `repcount`)
        (ref `patstr`)
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      (node
        `pat`
        (named
          `count`
          (pos `1`))
        (named
          `text`
          (pos `2`))
        (named
          `capture`
          (pos `4`)))
      _)
    (alt
      _
      ((ref `repcount`)
        (ref `patstr`))
      (node
        `pat`
        (named
          `count`
          (pos `1`))
        (named
          `text`
          (pos `2`)))
      _)
    (alt
      _
      ((ref `repcount`)
        (lit `"("`)
        (list_req
          `L`
          (plain `patgrp`))
        (lit `")"`))
      (node
        `pat`
        (named
          `count`
          (pos `1`))
        (named
          `alts`
          (spread `3`)))
      _))
  (rule
    (name `patgrp`)
    (alt
      _
      ((quantified
          (ref `patatom`)
          (one_plus)))
      _
      _))
  (rule
    (name `repcount`)
    (alt
      _
      ((ref `number`)
        (lit `"."`)
        (ref `number`))
      (node
        `count`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `number`)
        (lit `"."`))
      (node
        `count`
        (pos `1`)
        (null))
      _)
    (alt
      _
      ((ref `number`))
      (node
        `count`
        (pos `1`)
        (pos `1`))
      _)
    (alt
      _
      ((lit `"."`)
        (ref `number`))
      (node
        `count`
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"."`))
      (node `count`)
      _))
  (rule
    (name `patcode`)
    (alt
      _
      ((tok `IDENT`))
      _
      _))
  (rule
    (name `patstr`)
    (alt
      _
      ((group
          opt
          ((lit `"'"`)))
        (tok `STRING`))
      (list
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `glvn`)
    (alt
      _
      ((ref `lvn`))
      _
      _)
    (alt
      _
      ((ref `ssvn`))
      _
      _)
    (alt
      _
      ((ref `gvn`))
      _
      _))
  (rule
    (name `lvn`)
    (alt
      _
      ((ref `name`)
        (exclude `"("`))
      (node
        `lvar`
        (pos `1`))
      _)
    (alt
      _
      ((ref `name`)
        (ref `subs`))
      (node
        `lvar`
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      (node
        `@subs`
        (pos `2`)
        (pos `4`))
      _))
  (rule
    (name `gvn`)
    (alt
      _
      ((ref `rgvn`))
      _
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (exclude `"@"`))
      (node
        `@gname`
        (pos `3`))
      _))
  (rule
    (name `rgvn`)
    (alt
      _
      ((lit `"^"`)
        (ref `name`)
        (ref `subs`))
      (node
        `gvar`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `name`)
        (exclude `"("`))
      (node
        `gvar`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `naked`
        (spread `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      (node
        `@gsubs`
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `name`)
        (group
          opt
          ((ref `subs`))))
      (node
        `gvar`
        (pos `5`)
        (pos `6`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `","`)
        (ref `expr`)
        (lit `"|"`)
        (ref `name`)
        (group
          opt
          ((ref `subs`))))
      (node
        `gvar`
        (pos `7`)
        (pos `8`)
        (pos `3`)
        (pos `5`))
      _))
  (rule
    (name `ssvn`)
    (alt
      _
      ((lit `"^"`)
        (lit `"$"`)
        (lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      (node
        `@ssvn`
        (pos `4`)
        (pos `6`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (lit `"$"`)
        (tok `SSVN`)
        (exclude `"("`))
      (node
        `ssvn`
        (symid `6`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (lit `"$"`)
        (tok `SSVN`)
        (ref `subs`))
      (node
        `ssvn`
        (symid `6`)
        (pos `7`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"$"`)
        (tok `SSVN`)
        (exclude `"("`))
      (node
        `ssvn`
        (symid `3`))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"$"`)
        (tok `SSVN`)
        (ref `subs`))
      (node
        `ssvn`
        (symid `3`)
        (pos `4`))
      _))
  (rule
    (name `subs`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (pos `2`)
      _))
  (rule
    (name `number`)
    (alt
      _
      ((tok `INTEGER`))
      _
      _)
    (alt
      _
      ((tok `ZDIGITS`))
      _
      _)
    (alt
      _
      ((tok `REAL`))
      _
      _))
  (rule
    (name `literal`)
    (alt
      _
      ((ref `number`))
      _
      _)
    (alt
      _
      ((tok `STRING`))
      _
      _))
  (rule
    (name `fn`)
    (alt
      _
      ((ref `select`))
      _
      _)
    (alt
      _
      ((ref `text`))
      _
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `JUSTIFY`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `intrinsic`
        (symid `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `INCREMENT`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `intrinsic`
        (symid `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"$"`)
        (lit `"$"`)
        (ref `extrinsicref`))
      (pos `3`)
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (exclude `"("`))
      (node
        `intrinsic`
        (symid `2`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `SELECT`)
        (exclude `"("`))
      (node
        `intrinsic`
        (symid `2`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `JUSTIFY`)
        (exclude `"("`))
      (node
        `intrinsic`
        (symid `2`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `INCREMENT`)
        (exclude `"("`))
      (node
        `intrinsic`
        (symid `2`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `FN`)
        (exclude `"("`))
      (node
        `intrinsic`
        (symid `2`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `ISV`))
      (node
        `intrinsic`
        (symid `2`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `FN`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `intrinsic`
        (symid `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      (node
        `intrinsic`
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (exclude `"("`))
      (node
        `intrinsic`
        (pos `2`))
      _))
  (rule
    (name `extrinsicref`)
    (alt
      _
      ((ref `label`)
        (lit `"^"`)
        (ref `routineref`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      (node
        `extrinsic`
        (pos `1`)
        (pos `3`)
        (pos `5`))
      _)
    (alt
      _
      ((ref `label`)
        (lit `"^"`)
        (ref `routineref`)
        (exclude `"("`))
      (node
        `extrinsic`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `label`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      (node
        `extrinsic`
        (pos `1`)
        (null)
        (pos `3`))
      _)
    (alt
      _
      ((ref `label`)
        (exclude `"^"`)
        (exclude `"("`))
      (node
        `extrinsic`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `routineref`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      (node
        `extrinsic`
        (null)
        (pos `2`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `routineref`)
        (exclude `"("`))
      (node
        `extrinsic`
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `xatom`)
        (group
          opt
          ((lit `"^"`)
            (ref `routineref`)))
        (group
          opt
          ((ref `actuallist`))))
      (node
        `extrinsic`
        (node
          `@name`
          (pos `2`))
        (pos `4`)
        (pos `5`))
      _))
  (rule
    (name `select`)
    (alt
      _
      ((lit `"$"`)
        (tok `SELECT`)
        (lit `"("`)
        (list_req
          `L`
          (plain `selectarg`))
        (lit `")"`))
      (node
        `select`
        (spread `4`))
      _))
  (rule
    (name `selectarg`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      (node
        `case`
        (pos `1`)
        (pos `3`))
      _))
  (rule
    (name `text`)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (ref `indirref`)
        (lit `")"`))
      (node
        `text`
        (pos `4`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (ref `label`)
        (group
          opt
          ((lit `"+"`)
            (ref `expr`)))
        (group
          opt
          ((lit `"^"`)
            (ref `routineref`)))
        (lit `")"`))
      (node
        `text`
        (pos `4`)
        (pos `6`)
        (pos `8`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (lit `"+"`)
        (ref `expr`)
        (group
          opt
          ((lit `"^"`)
            (ref `routineref`)))
        (lit `")"`))
      (node
        `text`
        (null)
        (pos `5`)
        (pos `7`))
      _)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (lit `"^"`)
        (ref `routineref`)
        (lit `")"`))
      (node
        `text`
        (null)
        (null)
        (pos `5`))
      _)))
