(grammar
  (lang `"mumps"`)
  (conflicts `44`)
  (as
    `ident`
    (as_entry _ `fn`)
    (as_entry _ `isv`)
    (as_entry _ `ssvn`)
    (as_entry _ `self`)
    (as_entry _ `cmd`))
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
      ((tok `IDENT`))))
  (rule
    (name `label`)
    (alt
      _
      ((tok `IDENT`)))
    (alt
      _
      ((tok `INTEGER`)))
    (alt
      _
      ((tok `ZDIGITS`))))
  (rule
    (name `PATIND`)
    (alt
      _
      ((tok `QUESAT`))))
  (rule
    (name `COLIND`)
    (alt
      _
      ((tok `QUESAT`))))
  (rule
    (start `routine`)
    (alt
      _
      ((quantified
          (ref `line`)
          (zero_plus)))
      `(routine ...1)`))
  (rule
    (start `commands`)
    (alt
      _
      ((ref `cmds`)
        (group
          opt
          ((tok `COMMENT`))))
      `(commands ...1)`))
  (rule
    (start `expr`)
    (alt
      _
      ((ref `expr`))
      `1`))
  (rule
    (start `doarg`)
    (alt
      _
      ((ref `doarg`))
      `1`))
  (rule
    (start `gotoarg`)
    (alt
      _
      ((ref `gotoarg`))
      `1`))
  (rule
    (name `line`)
    (alt
      _
      ((ref `labelline`)
        (group
          opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((ref `cmdline`)
        (group
          opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      `1`)
    (alt
      _
      ((group
          opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      `_`))
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
      `(label 1 formallist:2 cmds:4)`)
    (alt
      _
      ((ref `label`)
        (ref `dotlevel`)
        (group
          opt
          ((ref `cmds`))))
      `(label 1 _ dots:2 ...3)`))
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
      `2`))
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
      `(1 dots:2 ...3)`))
  (rule
    (name `dotlevel`)
    (alt
      _
      ((quantified
          (lit `"."`)
          (one_plus)))
      `1`))
  (rule
    (name `cmd`)
    (alt
      _
      ((ref `set`)))
    (alt
      _
      ((ref `new`)))
    (alt
      _
      ((ref `merge`)))
    (alt
      _
      ((ref `kill`)))
    (alt
      _
      ((ref `if`)))
    (alt
      _
      ((ref `else`)))
    (alt
      _
      ((ref `for`)))
    (alt
      _
      ((ref `do`)))
    (alt
      _
      ((ref `goto`)))
    (alt
      _
      ((ref `quit`)))
    (alt
      _
      ((ref `break`)))
    (alt
      _
      ((ref `hang`)))
    (alt
      _
      ((ref `halt`)))
    (alt
      _
      ((ref `job`)))
    (alt
      _
      ((ref `xecute`)))
    (alt
      _
      ((ref `view`)))
    (alt
      _
      ((ref `open`)))
    (alt
      _
      ((ref `use`)))
    (alt
      _
      ((ref `read`)))
    (alt
      _
      ((ref `write`)))
    (alt
      _
      ((ref `close`)))
    (alt
      _
      ((ref `lock`)))
    (alt
      _
      ((ref `tstart`)))
    (alt
      _
      ((ref `tcommit`)))
    (alt
      _
      ((ref `trollback`)))
    (alt
      _
      ((ref `trestart`)))
    (alt
      _
      ((ref `zwrite`)))
    (alt
      _
      ((ref `zbreak`)))
    (alt
      _
      ((ref `zhalt`)))
    (alt
      _
      ((ref `zkill`))))
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
      `1`))
  (rule
    (name `postcond`)
    (alt
      _
      ((lit `":"`)
        (ref `expr`))
      `(postcond 2)`))
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
      `(set 2 ...3)`))
  (rule
    (name `setarg`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"="`)
        (ref `expr`))
      `(@name 2 value:4)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`)
    (alt
      _
      ((ref `glvn`)
        (lit `"="`)
        (ref `expr`))
      `(= 1 3)`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `setglvn`))
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      `(setmulti ...2 value:5)`)
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
      `(setfn 2 4 ...6 value:9)`)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (ref `setglvn`)
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      `(setfn 2 4 value:7)`)
    (alt
      _
      ((lit `"$"`)
        (ref `name`))
      `(setisv 2)`))
  (rule
    (name `setglvn`)
    (alt
      _
      ((ref `glvn`)))
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
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
      `(new 2 ...3)`))
  (rule
    (name `newarg`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((lit `"$"`)
        (ref `name`))
      `(intrinsic 2)`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `lname`))
        (lit `")"`))
      `(exclusive ...2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
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
      `(merge 2 ...3)`))
  (rule
    (name `mergearg`)
    (alt
      _
      ((ref `glvn`)
        (lit `"="`)
        (ref `glvn`))
      `(= 1 3)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
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
      `(kill 2 ...3)`))
  (rule
    (name `killarg`)
    (alt
      _
      ((ref `glvn`)))
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `lname`))
        (lit `")"`))
      `(exclusive ...2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `lname`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
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
      `(if ...2)`))
  (rule
    (name `else`)
    (alt
      _
      ((tok `ELSE`))
      `(else)`))
  (rule
    (name `for`)
    (alt
      _
      ((tok `FOR`)
        (group
          opt
          ((ref `forargs`))))
      `(for ...2)`))
  (rule
    (name `forargs`)
    (alt
      _
      ((ref `lvn`)
        (lit `"="`)
        (list_req
          `L`
          (plain `forparam`)))
      `(1 ...3)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"="`)
        (list_req
          `L`
          (plain `forparam`)))
      `(@name 2 ...4)`))
  (rule
    (name `forparam`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(range 1 3 5)`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(range 1 3)`)
    (alt
      _
      ((ref `expr`))))
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
      `(do 2 ...3)`))
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
      `(call ref:1 args:2 postcond:3)`)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `postcond`))))
      `(call ref:1 args:2 postcond:3)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
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
      `(goto 2 ...3)`))
  (rule
    (name `gotoarg`)
    (alt
      _
      ((ref `indirrefcmd`)
        (group
          opt
          ((ref `postcond`))))
      `(ref:1 postcond:2)`)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `postcond`))))
      `(ref:1 postcond:2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
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
      `(@ref label:2 offset:4 rtn:6)`))
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
      `(@ref label:2 offset:4 rtn:6)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"^"`)
        (ref `routineref`))
      `(@ref label:2 rtn:4)`))
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
      `(quit 2 3)`))
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
      `(break 2 ...3)`))
  (rule
    (name `breakarg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((ref `postcond`))))
      `(1 2)`))
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
      `(hang 2 ...3)`))
  (rule
    (name `halt`)
    (alt
      _
      ((tok `HALT`)
        (group
          opt
          ((ref `postcond`))))
      `(halt 2)`))
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
      `(job 2 ...3)`))
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
      `(ref:4 args:5 params:6 env:2)`)
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
      `(ref:4 args:5 params:6 env:2)`)
    (alt
      _
      ((ref `indirrefcmd`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `jobparams`))))
      `(ref:1 args:2 params:3)`)
    (alt
      _
      ((ref `entryref`)
        (group
          opt
          ((ref `actuallist`)))
        (group
          opt
          ((ref `jobparams`))))
      `(ref:1 args:2 params:3)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
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
      `(params:2 3)`))
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
      `(xecute 2 ...3)`))
  (rule
    (name `xecutearg`)
    (alt
      _
      ((ref `expr`)
        (group
          opt
          ((ref `postcond`))))
      `(1 2)`))
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
      `(view 2 ...3)`))
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
      `(1 params:3)`))
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
      `(open 2 ...3)`))
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
      `(1 params:...4 timeout:7)`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      `(1 params:...4)`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(1 mode:3 timeout:5)`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(1 mode:3)`)
    (alt
      _
      ((ref `expr`))
      `(1)`))
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
      `(use 2 ...3)`))
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
      `(read 2 ...3)`))
  (rule
    (name `readarg`)
    (alt
      _
      ((ref `posformat`)))
    (alt
      _
      ((lit `"/"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `(/ 2 ...4)`)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      `(/ 2)`)
    (alt
      _
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`)
        (ref `timeout`))
      `(charindir 3 4)`)
    (alt
      _
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`)
        (exclude `":"`))
      `(charindir 3)`)
    (alt
      _
      ((lit `"*"`)
        (ref `glvn`)
        (ref `timeout`))
      `(char 2 3)`)
    (alt
      _
      ((lit `"*"`)
        (ref `glvn`)
        (exclude `":"`))
      `(char 2)`)
    (alt
      _
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`)
        (ref `timeout`))
      `(# 1 3 4)`)
    (alt
      _
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`)
        (exclude `":"`))
      `(# 1 3)`)
    (alt
      _
      ((ref `glvn`)
        (ref `timeout`))
      `(1 2)`)
    (alt
      _
      ((ref `glvn`)
        (exclude `"#"`)
        (exclude `":"`))
      `1`)
    (alt
      _
      ((tok `STRING`))
      `(prompt 1)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
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
      `(write 2 ...3)`))
  (rule
    (name `writearg`)
    (alt
      _
      ((ref `posformat`)))
    (alt
      _
      ((lit `"/"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `(/ 2 ...4)`)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      `(/ 2)`)
    (alt
      _
      ((lit `"*"`)
        (ref `expr`))
      `(* 2)`)
    (alt
      _
      ((ref `expr`))))
  (rule
    (name `banghash`)
    (alt
      _
      ((lit `"!"`)))
    (alt
      _
      ((lit `"#"`)))
    (alt
      _
      ((tok `EXCLAIM_WS`)))
    (alt
      _
      ((tok `HASH_WS`))))
  (rule
    (name `tabcol`)
    (alt
      _
      ((lit `"?"`)
        (ref `expr`)
        (quantified
          (tok `PATEND`)
          (opt)))
      `(? 2)`))
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
      `(posformat ...1 2)`)
    (alt
      _
      ((ref `tabcol`))
      `1`)
    (alt
      _
      ((tok `COLIND`)
        (ref `atom`))
      `(?@ 2)`))
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
      `(close 2 ...3)`))
  (rule
    (name `devicearg`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `deviceparams`))
      `(1 params:3)`)
    (alt
      _
      ((ref `expr`))
      `(1)`))
  (rule
    (name `deviceparams`)
    (alt
      _
      ((lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      `2`)
    (alt
      _
      ((ref `deviceparam`))))
  (rule
    (name `deviceparamlist`)
    (alt
      _
      ((ref `deviceparam`)
        (lit `":"`)
        (ref `deviceparamlist`))
      `(1 ...3)`)
    (alt
      _
      ((ref `deviceparam`))
      `(1)`))
  (rule
    (name `deviceparam`)
    (alt
      _
      ((lit `"/"`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(attr 2 value:4)`)
    (alt
      _
      ((lit `"/"`)
        (ref `name`))
      `(keyword 2)`)
    (alt
      _
      ((ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(attr 1 value:3)`)
    (alt
      _
      ((ref `expr`))))
  (rule
    (name `timeout`)
    (alt
      _
      ((lit `":"`)
        (ref `expr`))
      `2`))
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
      `(lock 2 ...3)`))
  (rule
    (name `lockarg`)
    (alt
      _
      ((ref `lockref`)
        (group
          opt
          ((ref `timeout`))))
      `(lock= 1 2)`)
    (alt
      _
      ((lit `"+"`)
        (ref `lockref`)
        (group
          opt
          ((ref `timeout`))))
      `(lock+ 2 timeout:3)`)
    (alt
      _
      ((lit `"-"`)
        (ref `lockref`)
        (group
          opt
          ((ref `timeout`))))
      `(lock- 2 timeout:3)`)
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
      `(lock+ multi ...3 timeout:5)`)
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
      `(lock- multi ...3 timeout:5)`)
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
      `(lock= multi ...2 timeout:4)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `lockref`)
    (alt
      _
      ((ref `lvn`)))
    (alt
      _
      ((ref `gvn`))))
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
      `(tstart 2 ...3)`))
  (rule
    (name `tstartargs`)
    (alt
      _
      ((ref `tstartarg`)
        (group
          opt
          ((lit `":"`)
            (ref `tstartparams`))))
      `(1 params:3)`)
    (alt
      _
      ((tok `COLON_WS`)
        (ref `tstartparams`))
      `(params:2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
  (rule
    (name `tstartparams`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `tstartparam`))
        (lit `")"`))
      `(...2)`)
    (alt
      _
      ((list_req
          `L`
          (plain `tstartparam`)))))
  (rule
    (name `tstartarg`)
    (alt
      _
      ((lit `"*"`))
      `(*)`)
    (alt
      _
      ((lit `"("`)
        (group
          opt
          ((list_req
              `L`
              (plain `lname`))))
        (lit `")"`))
      `(...2)`)
    (alt
      _
      ((ref `lname`))))
  (rule
    (name `tstartparam`)
    (alt
      _
      ((ref `name`)
        (group
          opt
          ((lit `"="`)
            (ref `expr`))))
      `(1 3)`))
  (rule
    (name `tcommit`)
    (alt
      _
      ((tok `TCOMMIT`)
        (group
          opt
          ((ref `postcond`))))
      `(tcommit 2)`))
  (rule
    (name `trollback`)
    (alt
      _
      ((tok `TROLLBACK`)
        (group
          opt
          ((ref `postcond`))))
      `(trollback 2)`))
  (rule
    (name `trestart`)
    (alt
      _
      ((tok `TRESTART`)
        (group
          opt
          ((ref `postcond`))))
      `(trestart 2)`))
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
      `(zwrite 2 ...3)`))
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
      `(zbreak 2 ...3)`))
  (rule
    (name `zhalt`)
    (alt
      _
      ((tok `ZHALT`)
        (group
          opt
          ((ref `postcond`)))
        (ref `expr`))
      `(zhalt 2 code:3)`)
    (alt
      _
      ((tok `ZHALT`)
        (group
          opt
          ((ref `postcond`))))
      `(zhalt 2)`))
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
      `(zkill 2 ...3)`))
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
            (ref `routineref`)))
        (exclude `":"`))
      `(ref 1 3 5)`)
    (alt
      _
      ((lit `"+"`)
        (ref `entryoffset`)
        (lit `"^"`)
        (ref `routineref`)
        (exclude `":"`))
      `(ref _ 2 4)`)
    (alt
      _
      ((lit `"^"`)
        (ref `routineref`)
        (exclude `":"`))
      `(ref _ _ 2)`))
  (rule
    (name `entryoffset`)
    (alt
      _
      ((ref `expr`))))
  (rule
    (name `routineref`)
    (alt
      _
      ((ref `name`)))
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
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
      `2`))
  (rule
    (name `actual`)
    (alt
      _
      ((lit `"."`)
        (ref `lname`))
      `(byref 2)`)
    (alt
      _
      ((ref `expr`))))
  (rule
    (name `expr`)
    (alt
      _
      ((ref `atom`)
        (ref `exprtails`))
      `(expr 1 ...2)`))
  (rule
    (name `exprtails`)
    (alt
      _
      ((ref `exprtail`)
        (ref `exprtails`))
      `(!1 ...2)`)
    (alt shift () `()`))
  (rule
    (name `exprtail`)
    (alt
      _
      ((ref `binop`)
        (ref `atom`))
      `(~1 2)`)
    (alt
      _
      ((lit `"?"`)
        (ref `pattern`))
      `(? 2)`)
    (alt
      _
      ((lit `"'?"`)
        (ref `pattern`))
      `('? 2)`)
    (alt
      _
      ((tok `PATIND`)
        (ref `atom`))
      `(?@ 2)`)
    (alt
      _
      ((lit `"'?"`)
        (lit `"@"`)
        (ref `atom`))
      `('?@ 3)`))
  (rule
    (name `atom`)
    (alt
      _
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      `2`)
    (alt
      _
      ((ref `unaryop`)
        (ref `atom`))
      `(1 2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (exclude `"@"`))
      `(@name 2)`)
    (alt
      _
      ((ref `glvn`)))
    (alt
      _
      ((ref `literal`)))
    (alt
      _
      ((ref `fn`))))
  (rule
    (name `unaryop`)
    (alt
      _
      ((lit `"'"`)))
    (alt
      _
      ((lit `"+"`)))
    (alt
      _
      ((lit `"-"`))))
  (rule
    (name `binop`)
    (alt
      _
      ((lit `"_"`)))
    (alt
      _
      ((lit `"+"`)))
    (alt
      _
      ((lit `"-"`)))
    (alt
      _
      ((lit `"*"`)))
    (alt
      _
      ((lit `"/"`)))
    (alt
      _
      ((lit `"\\\\"`)))
    (alt
      _
      ((lit `"#"`)))
    (alt
      _
      ((lit `"**"`)))
    (alt
      _
      ((lit `"="`)))
    (alt
      _
      ((lit `"=="`)))
    (alt
      _
      ((lit `"'="`)))
    (alt
      _
      ((lit `"<"`)))
    (alt
      _
      ((lit `">"`)))
    (alt
      _
      ((lit `"'<"`)))
    (alt
      _
      ((lit `"'>"`)))
    (alt
      _
      ((lit `"<="`)))
    (alt
      _
      ((lit `">="`)))
    (alt
      _
      ((lit `"["`)))
    (alt
      _
      ((lit `"]"`)))
    (alt
      _
      ((lit `"'["`)))
    (alt
      _
      ((lit `"']"`)))
    (alt
      _
      ((lit `"]="`)))
    (alt
      _
      ((lit `"]]"`)))
    (alt
      _
      ((lit `"]]="`)))
    (alt
      _
      ((lit `"&"`)))
    (alt
      _
      ((lit `"!"`)))
    (alt
      _
      ((lit `"'&"`)))
    (alt
      _
      ((lit `"'!"`)))
    (alt
      _
      ((lit `"!!"`))))
  (rule
    (name `pattern`)
    (alt
      _
      ((quantified
          (ref `patatom`)
          (one_plus))
        (tok `PATEND`))
      `1`))
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
      `(pat 1 codes:2 capture:4)`)
    (alt
      _
      ((ref `repcount`)
        (quantified
          (ref `patcode`)
          (one_plus)))
      `(pat 1 codes:2)`)
    (alt
      _
      ((ref `patcode`)
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      `(pat 1 capture:3)`)
    (alt
      _
      ((ref `patcode`))
      `(pat 1)`)
    (alt
      _
      ((ref `repcount`)
        (ref `patstr`)
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      `(pat 1 2 capture:4)`)
    (alt
      _
      ((ref `repcount`)
        (ref `patstr`))
      `(pat 1 2)`)
    (alt
      _
      ((ref `repcount`)
        (lit `"("`)
        (list_req
          `L`
          (plain `patgrp`))
        (lit `")"`))
      `(pat 1 alt ...3)`))
  (rule
    (name `patgrp`)
    (alt
      _
      ((quantified
          (ref `patatom`)
          (one_plus)))))
  (rule
    (name `repcount`)
    (alt
      _
      ((ref `number`)
        (lit `"."`)
        (ref `number`))
      `(1 3)`)
    (alt
      _
      ((ref `number`)
        (lit `"."`))
      `(1 _)`)
    (alt
      _
      ((ref `number`))
      `(1 1)`)
    (alt
      _
      ((lit `"."`)
        (ref `number`))
      `(_ 2)`)
    (alt
      _
      ((lit `"."`))
      `()`))
  (rule
    (name `patcode`)
    (alt
      _
      ((tok `IDENT`))))
  (rule
    (name `patstr`)
    (alt
      _
      ((group
          opt
          ((lit `"'"`)))
        (tok `STRING`))
      `(1 2)`))
  (rule
    (name `glvn`)
    (alt
      _
      ((ref `lvn`)))
    (alt
      _
      ((ref `ssvn`)))
    (alt
      _
      ((ref `gvn`))))
  (rule
    (name `lvn`)
    (alt
      _
      ((ref `rlvn`))))
  (rule
    (name `rlvn`)
    (alt
      _
      ((ref `name`)
        (exclude `"("`))
      `(lvar 1)`)
    (alt
      _
      ((ref `name`)
        (ref `subs`))
      `(lvar 1 subs:2)`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      `(@subs 2 4)`))
  (rule
    (name `gvn`)
    (alt
      _
      ((ref `rgvn`)))
    (alt
      _
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (exclude `"@"`))
      `(@gname 3)`))
  (rule
    (name `rgvn`)
    (alt
      _
      ((lit `"^"`)
        (ref `name`)
        (ref `subs`))
      `(gvar 2 subs:3)`)
    (alt
      _
      ((lit `"^"`)
        (ref `name`)
        (exclude `"("`))
      `(gvar 2)`)
    (alt
      _
      ((lit `"^"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `(naked ...3)`)
    (alt
      _
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      `(@subs 3 5)`)
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
      `(gvar 5 subs:6 env:3)`)
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
      `(gvar 7 subs:8 env:3 uci:5)`)
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
      `(gvar 5 subs:6 env:3)`)
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
      `(gvar 7 subs:8 env:3 uci:5)`))
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
      `(@ssvn 4 6)`)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (lit `"$"`)
        (tok `SSVN`)
        (exclude `"("`))
      `(ssvn ~6 env:3)`)
    (alt
      _
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (lit `"$"`)
        (tok `SSVN`)
        (ref `subs`))
      `(ssvn ~6 subs:7 env:3)`)
    (alt
      _
      ((lit `"^"`)
        (lit `"$"`)
        (tok `SSVN`)
        (exclude `"("`))
      `(ssvn ~3)`)
    (alt
      _
      ((lit `"^"`)
        (lit `"$"`)
        (tok `SSVN`)
        (ref `subs`))
      `(ssvn ~3 subs:4)`))
  (rule
    (name `subs`)
    (alt
      _
      ((lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `2`))
  (rule
    (name `number`)
    (alt
      _
      ((tok `INTEGER`)))
    (alt
      _
      ((tok `ZDIGITS`)))
    (alt
      _
      ((tok `REAL`))))
  (rule
    (name `literal`)
    (alt
      _
      ((ref `number`))
      `(num 1)`)
    (alt
      _
      ((tok `STRING`))
      `(str 1)`))
  (rule
    (name `fn`)
    (alt
      _
      ((ref `select`)))
    (alt
      _
      ((ref `text`)))
    (alt
      _
      ((ref `justify`)))
    (alt
      _
      ((ref `increment`)))
    (alt
      _
      ((lit `"$"`)
        (lit `"$"`)
        (ref `extrinsicref`))
      `(extrinsic 3)     # extrinsic: $$FOO or $$FOO()`)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (exclude `"("`))
      `(intrinsic ~2)    # $T alone = $TEST ISV`)
    (alt
      _
      ((lit `"$"`)
        (tok `SELECT`)
        (exclude `"("`))
      `(intrinsic ~2)    # $S alone = $STORAGE ISV`)
    (alt
      _
      ((lit `"$"`)
        (tok `JUSTIFY`)
        (exclude `"("`))
      `(intrinsic ~2)    # $J alone = $JOB ISV`)
    (alt
      _
      ((lit `"$"`)
        (tok `INCREMENT`)
        (exclude `"("`))
      `(intrinsic ~2)    # $I alone = $IO ISV`)
    (alt
      _
      ((lit `"$"`)
        (tok `FN`)
        (exclude `"("`))
      `(intrinsic ~2)    # $Q=$QUIT, $TR=$TRESTART, etc.`)
    (alt
      _
      ((lit `"$"`)
        (tok `ISV`))
      `(intrinsic ~2)    # ISVs: $H, $X, $Y, etc.`)
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
      `(intrinsic ~2 4)  # function with args`)
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
      `(intrinsic 2 4)   # unknown function`)
    (alt
      _
      ((lit `"$"`)
        (ref `name`)
        (exclude `"("`))
      `(intrinsic 2)     # unknown ISV (not if ( follows)`))
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
      `(1 args:3)        # $$FOO() or $$FOO(a,b)`)
    (alt
      _
      ((ref `labelref`)
        (exclude `"("`))
      `1                 # $$FOO`)
    (alt
      _
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)          # $$@var (args via @-string only;`))
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
      `(select ...4)`))
  (rule
    (name `selectarg`)
    (alt
      _
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(1 3)`))
  (rule
    (name `text`)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (ref `indirref`)
        (lit `")"`))
      `(text 4)`)
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
      `(text 4 6 8)`)
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
      `(text _ 5 7)`)
    (alt
      _
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (lit `"^"`)
        (ref `routineref`)
        (lit `")"`))
      `(text _ _ 5)`))
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
      `(intrinsic ~2 4)`))
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
      `(intrinsic ~2 4)`))
  (rule
    (name `labelref`)
    (alt
      _
      ((ref `label`)
        (lit `"^"`)
        (ref `routineref`))
      `(1 routine:3)`)
    (alt
      _
      ((ref `label`)
        (exclude `"^"`))
      `1`)
    (alt
      _
      ((lit `"^"`)
        (ref `routineref`))
      `(routine:2)`)))
