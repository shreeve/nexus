(grammar
  (lang `"mumps"`)
  (conflicts `44`)
  (as
    `ident`
    _
    (as_entry _ `fn` _)
    (as_entry _ `isv` _)
    (as_entry _ `ssvn` _)
    (as_entry _ `self` _)
    (as_entry _ `cmd` _))
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
    (op_map `"]]="` `"sortsaftereq"`))
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
      ((quantified
          (ref `line`)
          (zero_plus)))
      (node
        `routine`
        (spread `1`))
      _))
  (rule
    (start `commands`)
    (alt
      _
      ((ref `cmds`)
        (group
          opt
          ((tok `COMMENT`))))
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
    (start `doarg`)
    (alt
      _
      ((ref `doarg`))
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
    (name `line`)
    (alt
      _
      ((ref `labelline`)
        (group
          opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      (pos `1`)
      _)
    (alt
      _
      ((ref `cmdline`)
        (group
          opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      (pos `1`)
      _)
    (alt
      _
      ((group
          opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      (null)
      _))
  (rule
    (name `labelline`)
    (alt
      _
      ((ref `label`)
        (group
          opt
          ((ref `formallist`)))
        (group
          opt
          ((tok `SPACES`)))
        (group
          opt
          ((ref `cmds`))))
      (node
        `label`
        (pos `1`)
        (named
          `formallist`
          (pos `2`))
        (named
          `cmds`
          (pos `4`)))
      _)
    (alt
      _
      ((ref `label`)
        (ref `dotlevel`)
        (group
          opt
          ((ref `cmds`))))
      (node
        `label`
        (pos `1`)
        (null)
        (named
          `dots`
          (pos `2`))
        (spread `3`))
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
          ((ref `dotlevel`)))
        (group
          opt
          ((ref `cmds`))))
      (list
        (pos `1`)
        (named
          `dots`
          (pos `2`))
        (spread `3`))
      _))
  (rule
    (name `dotlevel`)
    (alt
      _
      ((quantified
          (lit `"."`)
          (one_plus)))
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
      _))
  (rule
    (name `cmds`)
    (alt
      _
      ((quantified
          (group
            _
            ((ref `cmd`)
              (skip_q
                (tok `SPACES`)
                (opt))))
          (one_plus)))
      (pos `1`)
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
        (list_req
          `L`
          (plain `setarg`)))
      (node
        `set`
        (pos `2`)
        (spread `3`))
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
        `@name`
        (pos `2`)
        (named
          `value`
          (pos `4`)))
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
        (spread `2`)
        (named
          `value`
          (pos `5`)))
      _)
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
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      (node
        `setfn`
        (pos `2`)
        (pos `4`)
        (spread `6`)
        (named
          `value`
          (pos `9`)))
      _)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (ref `setglvn`)
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      (node
        `setfn`
        (pos `2`)
        (pos `4`)
        (named
          `value`
          (pos `7`)))
      _)
    (alt
      _
      ((lit `"$"`)
        (ref `name`))
      (node
        `setisv`
        (pos `2`))
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
      _))
  (rule
    (name `new`)
    (alt
      _
      ((tok `NEW`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `newarg`)))))
      (node
        `new`
        (pos `2`)
        (spread `3`))
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
        (list_req
          `L`
          (plain `mergearg`)))
      (node
        `merge`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `mergearg`)
    (alt
      _
      ((ref `glvn`)
        (lit `"="`)
        (ref `glvn`))
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
    (name `kill`)
    (alt
      _
      ((tok `KILL`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `killarg`)))))
      (node
        `kill`
        (pos `2`)
        (spread `3`))
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
      _
      ((tok `IF`)
        (group
          opt
          ((list_req
              `L`
              (plain `expr`)))))
      (node
        `if`
        (spread `2`))
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
      _
      ((tok `FOR`)
        (group
          opt
          ((ref `forargs`))))
      (node
        `for`
        (spread `2`))
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
      (list
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
        `@name`
        (pos `2`)
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
      _
      ((tok `DO`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `doarg`)))))
      (node
        `do`
        (pos `2`)
        (spread `3`))
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
        (named
          `ref`
          (pos `1`))
        (named
          `args`
          (pos `2`))
        (named
          `postcond`
          (pos `3`)))
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
        (named
          `ref`
          (pos `1`))
        (named
          `args`
          (pos `2`))
        (named
          `postcond`
          (pos `3`)))
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
    (name `goto`)
    (alt
      _
      ((tok `GOTO`)
        (group
          opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `gotoarg`)))
      (node
        `goto`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `gotoarg`)
    (alt
      _
      ((ref `indirrefcmd`)
        (group
          opt
          ((ref `postcond`))))
      (list
        (named
          `ref`
          (pos `1`))
        (named
          `postcond`
          (pos `2`)))
      _)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `postcond`))))
      (list
        (named
          `ref`
          (pos `1`))
        (named
          `postcond`
          (pos `2`)))
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
        (named
          `label`
          (pos `2`))
        (named
          `offset`
          (pos `4`))
        (named
          `rtn`
          (pos `6`)))
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
        (named
          `label`
          (pos `2`))
        (named
          `offset`
          (pos `4`))
        (named
          `rtn`
          (pos `6`)))
      _)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"^"`)
        (ref `routineref`))
      (node
        `@ref`
        (named
          `label`
          (pos `2`))
        (named
          `rtn`
          (pos `4`)))
      _))
  (rule
    (name `quit`)
    (alt
      _
      ((tok `QUIT`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((ref `expr`))))
      (node
        `quit`
        (pos `2`)
        (pos `3`))
      _))
  (rule
    (name `break`)
    (alt
      _
      ((tok `BREAK`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `breakarg`)))))
      (node
        `break`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `breakarg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((ref `postcond`))))
      (list
        (pos `1`)
        (pos `2`))
      _))
  (rule
    (name `hang`)
    (alt
      _
      ((tok `HANG`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `expr`)))))
      (node
        `hang`
        (pos `2`)
        (spread `3`))
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
        (list_req
          `L`
          (plain `jobarg`)))
      (node
        `job`
        (pos `2`)
        (spread `3`))
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
      (list
        (named
          `ref`
          (pos `4`))
        (named
          `args`
          (pos `5`))
        (named
          `params`
          (pos `6`))
        (named
          `env`
          (pos `2`)))
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
      (list
        (named
          `ref`
          (pos `4`))
        (named
          `args`
          (pos `5`))
        (named
          `params`
          (pos `6`))
        (named
          `env`
          (pos `2`)))
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
      (list
        (named
          `ref`
          (pos `1`))
        (named
          `args`
          (pos `2`))
        (named
          `params`
          (pos `3`)))
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
      (list
        (named
          `ref`
          (pos `1`))
        (named
          `args`
          (pos `2`))
        (named
          `params`
          (pos `3`)))
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
      (list
        (named
          `params`
          (pos `2`))
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
        (list_req
          `L`
          (plain `xecutearg`)))
      (node
        `xecute`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `xecutearg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((ref `postcond`))))
      (list
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
        (list_req
          `L`
          (plain `viewarg`)))
      (node
        `view`
        (pos `2`)
        (spread `3`))
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
              (plain `expr`)))))
      (list
        (pos `1`)
        (named
          `params`
          (pos `3`)))
      _))
  (rule
    (name `open`)
    (alt
      _
      ((tok `OPEN`)
        (group
          opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `openarg`)))
      (node
        `open`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `openarg`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`)
        (lit `":"`)
        (ref `expr`))
      (list
        (pos `1`)
        (named
          `params`
          (spread `4`))
        (named
          `timeout`
          (pos `7`)))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      (list
        (pos `1`)
        (named
          `params`
          (spread `4`)))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`))
      (list
        (pos `1`)
        (named
          `mode`
          (pos `3`))
        (named
          `timeout`
          (pos `5`)))
      _)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      (list
        (pos `1`)
        (named
          `mode`
          (pos `3`)))
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
        (list_req
          `L`
          (plain `devicearg`)))
      (node
        `use`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `read`)
    (alt
      _
      ((tok `READ`)
        (group
          opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `readarg`)))
      (node
        `read`
        (pos `2`)
        (spread `3`))
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
        `/`
        (pos `2`)
        (spread `4`))
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      (node
        `/`
        (pos `2`))
      _)
    (alt
      _
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`)
        (ref `timeout`))
      (node
        `charindir`
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`))
      (node
        `charindir`
        (pos `3`))
      _)
    (alt
      _
      ((lit `"*"`)
        (ref `glvn`)
        (ref `timeout`))
      (node
        `char`
        (pos `2`)
        (pos `3`))
      _)
    (alt
      _
      ((lit `"*"`)
        (ref `glvn`))
      (node
        `char`
        (pos `2`))
      _)
    (alt
      _
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`)
        (ref `timeout`))
      (node
        `#`
        (pos `1`)
        (pos `3`)
        (pos `4`))
      _)
    (alt
      _
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`))
      (node
        `#`
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `glvn`)
        (ref `timeout`))
      (list
        (pos `1`)
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
        (ref `atom`))
      (node
        `@args`
        (pos `2`))
      _))
  (rule
    (name `write`)
    (alt
      _
      ((tok `WRITE`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `writearg`)))))
      (node
        `write`
        (pos `2`)
        (spread `3`))
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
        `/`
        (pos `2`)
        (spread `4`))
      _)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      (node
        `/`
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
      _)
    (alt
      _
      ((tok `EXCLAIM_WS`))
      _
      _)
    (alt
      _
      ((tok `HASH_WS`))
      _
      _))
  (rule
    (name `tabcol`)
    (alt
      _
      ((lit `"?"`)
        (ref `expr`)
        (quantified
          (tok `PATEND`)
          (opt)))
      (node
        `?`
        (pos `2`))
      _))
  (rule
    (name `posformat`)
    (alt
      _
      ((quantified
          (ref `banghash`)
          (one_plus))
        (group
          opt
          ((ref `tabcol`))))
      (node
        `posformat`
        (spread `1`)
        (pos `2`))
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
        `?@`
        (pos `2`))
      _))
  (rule
    (name `close`)
    (alt
      _
      ((tok `CLOSE`)
        (group
          opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `devicearg`)))
      (node
        `close`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `devicearg`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `deviceparams`))
      (list
        (pos `1`)
        (named
          `params`
          (pos `3`)))
      _)
    (alt
      _
      ((ref `expr`))
      (list
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
      _
      _))
  (rule
    (name `deviceparamlist`)
    (alt
      _
      ((ref `deviceparam`)
        (lit `":"`)
        (ref `deviceparamlist`))
      (list
        (pos `1`)
        (spread `3`))
      _)
    (alt
      _
      ((ref `deviceparam`))
      (list
        (pos `1`))
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
        (named
          `value`
          (pos `4`)))
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
        (named
          `value`
          (pos `3`)))
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
      _
      ((tok `LOCK`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `lockarg`)))))
      (node
        `lock`
        (pos `2`)
        (spread `3`))
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
        (pos `1`)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"+"`)
        (ref `lockref`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock+`
        (pos `2`)
        (named
          `timeout`
          (pos `3`)))
      _)
    (alt
      _
      ((lit `"-"`)
        (ref `lockref`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock-`
        (pos `2`)
        (named
          `timeout`
          (pos `3`)))
      _)
    (alt
      _
      ((lit `"+"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `lockref`))
        (lit `")"`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock+`
        (tag `multi`)
        (spread `3`)
        (named
          `timeout`
          (pos `5`)))
      _)
    (alt
      _
      ((lit `"-"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `lockref`))
        (lit `")"`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock-`
        (tag `multi`)
        (spread `3`)
        (named
          `timeout`
          (pos `5`)))
      _)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `lockref`))
        (lit `")"`)
        (group
          opt
          ((ref `timeout`))))
      (node
        `lock=`
        (tag `multi`)
        (spread `2`)
        (named
          `timeout`
          (pos `4`)))
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
      _
      ((tok `TSTART`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((ref `tstartargs`))))
      (node
        `tstart`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `tstartargs`)
    (alt
      _
      ((ref `tstartarg`)
        (group
          opt
          ((lit `":"`)
            (ref `tstartparams`))))
      (list
        (pos `1`)
        (named
          `params`
          (pos `3`)))
      _)
    (alt
      _
      ((tok `COLON_WS`)
        (ref `tstartparams`))
      (list
        (named
          `params`
          (pos `2`)))
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
    (name `tstartparams`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `tstartparam`))
        (lit `")"`))
      (list
        (spread `2`))
      _)
    (alt
      _
      ((list_req
          `L`
          (plain `tstartparam`)))
      _
      _))
  (rule
    (name `tstartarg`)
    (alt
      _
      ((lit `"*"`))
      (node `*`)
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
      (list
        (spread `2`))
      _)
    (alt
      _
      ((ref `lname`))
      _
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
      (list
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
      _
      ((tok `ZWRITE`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `glvn`)))))
      (node
        `zwrite`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `zbreak`)
    (alt
      _
      ((tok `ZBREAK`)
        (group
          opt
          ((ref `postcond`)))
        (group
          opt
          ((list_req
              `L`
              (plain `gotoarg`)))))
      (node
        `zbreak`
        (pos `2`)
        (spread `3`))
      _))
  (rule
    (name `zhalt`)
    (alt
      _
      ((tok `ZHALT`)
        (group
          opt
          ((ref `postcond`)))
        (ref `expr`))
      (node
        `zhalt`
        (pos `2`)
        (named
          `code`
          (pos `3`)))
      _)
    (alt
      _
      ((tok `ZHALT`)
        (group
          opt
          ((ref `postcond`))))
      (node
        `zhalt`
        (pos `2`))
      _))
  (rule
    (name `zkill`)
    (alt
      _
      ((tok `ZKILL`)
        (group
          opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `glvn`)))
      (node
        `zkill`
        (pos `2`)
        (spread `3`))
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
      _
      ((ref `atom`)
        (ref `exprtails`))
      (node
        `expr`
        (pos `1`)
        (spread `2`))
      _))
  (rule
    (name `exprtails`)
    (alt
      _
      ((ref `exprtail`)
        (ref `exprtails`))
      (keep
        `1`
        (spread `2`))
      _)
    (alt
      `>`
      ()
      (list)
      _))
  (rule
    (name `exprtail`)
    (alt
      _
      ((ref `binop`)
        (ref `atom`))
      (list
        (symid `1`)
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
      (pos `2`)
      _)
    (alt
      _
      ((ref `unaryop`)
        (ref `atom`))
      (list
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
      _)
    (alt
      _
      ((lit `"!!"`))
      _
      _))
  (rule
    (name `pattern`)
    (alt
      _
      ((quantified
          (ref `patatom`)
          (one_plus))
        (tok `PATEND`))
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
        (pos `1`)
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
        (pos `1`)
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
        (pos `1`)
        (named
          `capture`
          (pos `3`)))
      _)
    (alt
      _
      ((ref `patcode`))
      (node
        `pat`
        (pos `1`))
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
        (pos `1`)
        (pos `2`)
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
        (pos `1`)
        (pos `2`))
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
        (pos `1`)
        (tag `alt`)
        (spread `3`))
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
      (list
        (pos `1`)
        (pos `3`))
      _)
    (alt
      _
      ((ref `number`)
        (lit `"."`))
      (list
        (pos `1`)
        (null))
      _)
    (alt
      _
      ((ref `number`))
      (list
        (pos `1`)
        (pos `1`))
      _)
    (alt
      _
      ((lit `"."`)
        (ref `number`))
      (list
        (null)
        (pos `2`))
      _)
    (alt
      _
      ((lit `"."`))
      (list)
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
      ((ref `rlvn`))
      _
      _))
  (rule
    (name `rlvn`)
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
        (named
          `subs`
          (pos `2`)))
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
        (named
          `subs`
          (pos `3`)))
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
        `@subs`
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
        (named
          `subs`
          (pos `6`))
        (named
          `env`
          (pos `3`)))
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
        (named
          `subs`
          (pos `8`))
        (named
          `env`
          (pos `3`))
        (named
          `uci`
          (pos `5`)))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"["`)
        (ref `expr`)
        (lit `"]"`)
        (ref `name`)
        (group
          opt
          ((ref `subs`))))
      (node
        `gvar`
        (pos `5`)
        (named
          `subs`
          (pos `6`))
        (named
          `env`
          (pos `3`)))
      _)
    (alt
      _
      ((lit `"^"`)
        (lit `"["`)
        (ref `expr`)
        (lit `","`)
        (ref `expr`)
        (lit `"]"`)
        (ref `name`)
        (group
          opt
          ((ref `subs`))))
      (node
        `gvar`
        (pos `7`)
        (named
          `subs`
          (pos `8`))
        (named
          `env`
          (pos `3`))
        (named
          `uci`
          (pos `5`)))
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
        (named
          `env`
          (pos `3`)))
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
        (named
          `subs`
          (pos `7`))
        (named
          `env`
          (pos `3`)))
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
        (named
          `subs`
          (pos `4`)))
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
      (node
        `num`
        (pos `1`))
      _)
    (alt
      _
      ((tok `STRING`))
      (node
        `str`
        (pos `1`))
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
      ((ref `justify`))
      _
      _)
    (alt
      _
      ((ref `increment`))
      _
      _)
    (alt
      _
      ((lit `"$"`)
        (lit `"$"`)
        (ref `extrinsicref`))
      (node
        `extrinsic`
        (pos `3`))
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
        (group
          opt
          ((list_req
              `L`
              (plain `expr`))))
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
        (group
          opt
          ((list_req
              `L`
              (plain `expr`))))
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
      ((ref `labelref`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      (list
        (pos `1`)
        (named
          `args`
          (pos `3`)))
      _)
    (alt
      _
      ((ref `labelref`)
        (exclude `"("`))
      (pos `1`)
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
      (list
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
      _))
  (rule
    (name `justify`)
    (alt
      _
      ((lit `"$"`)
        (tok `JUSTIFY`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      (node
        `intrinsic`
        (symid `2`)
        (pos `4`))
      _))
  (rule
    (name `increment`)
    (alt
      _
      ((lit `"$"`)
        (tok `INCREMENT`)
        (lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      (node
        `intrinsic`
        (symid `2`)
        (pos `4`))
      _))
  (rule
    (name `labelref`)
    (alt
      _
      ((ref `label`)
        (lit `"^"`)
        (ref `routineref`))
      (list
        (pos `1`)
        (named
          `routine`
          (pos `3`)))
      _)
    (alt
      _
      ((ref `label`)
        (exclude `"^"`))
      (pos `1`)
      _)
    (alt
      _
      ((lit `"^"`)
        (ref `routineref`))
      (list
        (named
          `routine`
          (pos `2`)))
      _)))
