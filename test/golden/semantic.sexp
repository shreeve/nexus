(grammar
  (section `lexer`)
  (tokens `tokens` `ident` `integer` `newline` `eq` `plus_eq` `minus_eq` `star_eq` `colon` `comma` `lparen` `rparen` `lbracket` `rbracket` `plus` `minus` `star` `slash` `let` `if` `unless` `then` `else` `return` `for` `ptr` `in` `do` `call` `swap` `with` `pass` `yield` `comment` `eof` `err`)
  (lex_rule `'#' [^\\n]*` _ `comment`)
  (lex_rule `'\\n'` _ `newline`)
  (lex_rule `"+="` _ `plus_eq`)
  (lex_rule `"-="` _ `minus_eq`)
  (lex_rule `"*="` _ `star_eq`)
  (lex_rule `'='` _ `eq`)
  (lex_rule `':'` _ `colon`)
  (lex_rule `','` _ `comma`)
  (lex_rule `'('` _ `lparen`)
  (lex_rule `')'` _ `rparen`)
  (lex_rule `'['` _ `lbracket`)
  (lex_rule `']'` _ `rbracket`)
  (lex_rule `'+'` _ `plus`)
  (lex_rule `'-'` _ `minus`)
  (lex_rule `'*'` _ `star`)
  (lex_rule `'/'` _ `slash`)
  (lex_rule `[0-9]+` _ `integer`)
  (lex_rule `[a-zA-Z_][a-zA-Z0-9_]*` _ `ident`)
  (lex_rule `.` _ `err`)
  (section `parser`)
  (lang `"semantic"`)
  (schema
    (kind_decl
      (kinds `module`)
      (roles
        (role rest `stmts` _ _))
      _
      _)
    (kind_decl
      (kinds `set`)
      (roles
        (role
          _
          `op`
          (type `tag`)
          opt)
        (role
          _
          `target`
          (type `name`)
          _)
        (role _ `value` _ _))
      (sides `eq`)
      _)
    (kind_decl
      (kinds `let`)
      (roles
        (role
          _
          `name`
          (type `leaf`)
          _)
        (role
          _
          `type`
          (type `name`)
          opt)
        (role _ `value` _ _))
      _
      _)
    (kind_decl
      (kinds `if`)
      (roles
        (role
          _
          `kw`
          (type `leaf`)
          _)
        (role _ `cond` _ _)
        (role
          _
          `then`
          (type `node`)
          _)
        (role
          _
          `else`
          (type `node`)
          opt))
      _
      _)
    (kind_decl
      (kinds `for`)
      (roles
        (role
          _
          `mode`
          (type
            (tagset `tag` `ptr`))
          opt)
        (role
          _
          `var`
          (type `leaf`)
          _)
        (role
          _
          `index`
          (type `leaf`)
          opt)
        (role _ `iter` _ _)
        (role _ `body` _ _))
      _
      _)
    (kind_decl
      (kinds `call`)
      (roles
        (role
          _
          `callee`
          (type `leaf`)
          _)
        (role rest `args` _ _))
      _
      _)
    (kind_decl
      (kinds `swap`)
      (roles
        (role
          _
          `a`
          (type `leaf`)
          _)
        (role
          _
          `b`
          (type `leaf`)
          _)
        (role
          _
          `c`
          (type `leaf`)
          _)
        (role
          _
          `d`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `return`)
      (roles
        (role _ `value` _ opt))
      _
      _)
    (kind_decl
      (kinds `yield`)
      (roles
        (role
          _
          `value`
          (type `leaf`)
          opt))
      _
      _)
    (kind_decl
      (kinds `pass`)
      (roles)
      _
      _)
    (kind_decl
      (kinds `array`)
      (roles
        (role rest `items` _ _))
      _
      _)
    (kind_decl
      (kinds `neg`)
      (roles
        (role
          _
          `value`
          (type `num`)
          _))
      _
      _)
    (kind_decl
      (kinds `num`)
      (roles
        (role
          _
          `value`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `name`)
      (roles
        (role
          _
          `id`
          (type `leaf`)
          _))
      _
      _)
    (kind_decl
      (kinds `"+"` `"-"`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `"*"` `"/"`)
      (roles
        (role _ `left` _ _)
        (role _ `right` _ _))
      _
      _)
    (kind_decl
      (kinds `note`)
      (roles
        (role
          _
          `text`
          (type `leaf`)
          _))
      _
      wrapper))
  (tags `flag`)
  (display
    (name_pair `IDENT` `"a name"`)
    (name_pair `"="` `"'='"`))
  (errors
    (name_pair `expr` `"an expression"`))
  (trivia `COMMENT`)
  (repair
    (repair_line `holes` `IDENT`)
    (repair_line `terminator` `NEWLINE`))
  (manifest
    (conflict `shift` `stmt → IF infix THEN stmt` _ `1` `# else binds to the nearest if`)
    (conflict `shift` `stmt → UNLESS infix THEN stmt` _ `1` `# the same for unless`))
  (rule
    (start `program`)
    (alt
      _
      ((ref `stmts`))
      (node
        `module`
        (spread `1`))
      _))
  (rule
    (name `stmts`)
    (alt
      _
      ((ref `stmt`))
      (list
        (pos `1`))
      _)
    (alt
      _
      ((ref `stmts`)
        (tok `NEWLINE`)
        (ref `stmt`))
      (list
        (spread `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `stmts`)
        (tok `NEWLINE`))
      (pos `1`)
      _))
  (rule
    (name `stmt`)
    (alt
      _
      ((label
          `target`
          (ref `name`))
        (label
          `eq`
          (lit `"="`))
        (label
          `value`
          (ref `expr`)))
      (node `set`)
      _)
    (alt
      _
      ((ref `name`)
        (lit `"+="`)
        (ref `expr`))
      (node
        `set`
        (tag `+=`)
        (pos `1`)
        (named
          `value`
          (pos `3`)))
      _)
    (alt
      _
      ((label
          `target`
          (ref `name`))
        (label
          `op`
          (group
            _
            ((lit `"-="`))
            ((lit `"*="`))))
        (label
          `value`
          (ref `expr`)))
      (node `set`)
      _)
    (alt
      _
      ((tok `LET`)
        (tok `IDENT`)
        (lit `"+="`)
        (ref `expr`))
      (node
        `set`
        (named
          `op`
          (tag `+=`))
        (named
          `target`
          (node
            `name`
            (pos `2`)))
        (named
          `value`
          (pos `4`)))
      _)
    (alt
      _
      ((tok `LET`)
        (label
          `name`
          (tok `IDENT`))
        (group
          opt
          ((lit `":"`)
            (label
              `type`
              (ref `name`))))
        (lit `"="`)
        (label
          `value`
          (ref `expr`)))
      (node `let`)
      _)
    (alt
      _
      ((label
          `kw`
          (group
            _
            ((tok `IF`))
            ((tok `UNLESS`))))
        (label
          `cond`
          (ref `expr`))
        (tok `THEN`)
        (label
          `then`
          (ref `stmt`))
        (group
          opt
          ((tok `ELSE`)
            (label
              `else`
              (ref `stmt`)))))
      (node `if`)
      _)
    (alt
      _
      ((tok `FOR`)
        (tok `PTR`)
        (label
          `var`
          (tok `IDENT`))
        (group
          opt
          ((lit `","`)
            (label
              `index`
              (tok `IDENT`))))
        (tok `IN`)
        (label
          `iter`
          (ref `expr`))
        (tok `DO`)
        (label
          `body`
          (ref `stmt`)))
      (node
        `for`
        (named
          `mode`
          (tag `ptr`)))
      _)
    (alt
      _
      ((tok `FOR`)
        (label
          `var`
          (tok `IDENT`))
        (tok `IN`)
        (label
          `iter`
          (ref `expr`))
        (tok `DO`)
        (label
          `body`
          (ref `stmt`)))
      (node
        `for`
        (named
          `mode`
          (null)))
      _)
    (alt
      _
      ((tok `CALL`)
        (label
          `callee`
          (tok `IDENT`))
        (lit `"("`)
        (label
          `args`
          (group
            opt
            ((list_req
                `L`
                (plain `expr`)))))
        (lit `")"`))
      (node `call`)
      _)
    (alt
      _
      ((tok `SWAP`)
        (lit `"("`)
        (tok `IDENT`)
        (lit `","`)
        (tok `IDENT`)
        (lit `")"`)
        (tok `WITH`)
        (lit `"("`)
        (tok `IDENT`)
        (lit `","`)
        (tok `IDENT`)
        (lit `")"`))
      (node
        `swap`
        (pos `3`)
        (pos `5`)
        (pos `9`)
        (pos `11`))
      _)
    (alt
      _
      ((tok `RETURN`)
        (group
          opt
          ((label
              `value`
              (ref `expr`)))))
      (node `return`)
      _)
    (alt
      _
      ((tok `YIELD`)
        (label
          `value`
          (quantified
            (group
              _
              ((tok `IDENT`))
              ((tok `INTEGER`)))
            (opt))))
      (node `yield`)
      _)
    (alt
      _
      ((tok `PASS`)
        (label
          `_`
          (tok `IDENT`)))
      (node `pass`)
      _)
    (alt
      _
      ((tok `PASS`)
        (lit `"("`)
        (tok `IDENT`)
        (lit `")"`))
      (node `pass`)
      `"the name is only a comment"`)
    (alt
      _
      ((ref `expr`))
      (pos `1`)
      _))
  (rule
    (name `name`)
    (alt
      _
      ((tok `IDENT`))
      (node
        `name`
        (pos `1`))
      _))
  (rule
    (name `expr`)
    (alt
      _
      ((at_ref `infix`))
      _
      _))
  (rule
    (name `atom`)
    (alt
      _
      ((ref `name`))
      (pos `1`)
      _)
    (alt
      _
      ((tok `INTEGER`))
      (node
        `num`
        (pos `1`))
      _)
    (alt
      _
      ((lit `"-"`)
        (tok `INTEGER`))
      (node
        `neg`
        (named
          `value`
          (node
            `num`
            (pos `2`))))
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
      ((lit `"["`)
        (group
          opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `"]"`))
      (node
        `array`
        (spread `2`))
      _))
  (infix
    `atom`
    (level
      (infix_op `"+"` `left`)
      (infix_op `"-"` `left`))
    (level
      (infix_op `"*"` `left`)
      (infix_op `"/"` `left`))))
