(grammar
  (lang `"mumps"`)
  (conflicts `44`)
  (as
    `ident`
    (as_strict `fn`)
    (as_strict `isv`)
    (as_strict `ssvn`)
    (as_strict `self`)
    (as_strict `cmd`))
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
      ((tok `IDENT`))))
  (rule
    (name `label`)
    (alt
      ((tok `IDENT`)))
    (alt
      ((tok `INTEGER`)))
    (alt
      ((tok `ZDIGITS`))))
  (rule
    (name `PATIND`)
    (alt
      ((tok `QUESAT`))))
  (rule
    (name `COLIND`)
    (alt
      ((tok `QUESAT`))))
  (rule
    (start `routine`)
    (alt
      ((quantified
          (ref `line`)
          (zero_plus)))
      `(routine ...1)`))
  (rule
    (start `commands`)
    (alt
      ((ref `cmds`)
        (group_opt
          ((tok `COMMENT`))))
      `(commands ...1)`))
  (rule
    (start `expr`)
    (alt
      ((ref `expr`))
      `1`))
  (rule
    (start `doarg`)
    (alt
      ((ref `doarg`))
      `1`))
  (rule
    (start `gotoarg`)
    (alt
      ((ref `gotoarg`))
      `1`))
  (rule
    (name `line`)
    (alt
      ((ref `labelline`)
        (group_opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      `1`)
    (alt
      ((ref `cmdline`)
        (group_opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      `1`)
    (alt
      ((group_opt
          ((tok `COMMENT`)))
        (tok `NEWLINE`))
      `_`))
  (rule
    (name `labelline`)
    (alt
      ((ref `label`)
        (group_opt
          ((ref `formallist`)))
        (group_opt
          ((tok `SPACES`)))
        (group_opt
          ((ref `cmds`))))
      `(label 1 formallist:2 cmds:4)`)
    (alt
      ((ref `label`)
        (ref `dotlevel`)
        (group_opt
          ((ref `cmds`))))
      `(label 1 _ dots:2 ...3)`))
  (rule
    (name `formallist`)
    (alt
      ((lit `"("`)
        (group_opt
          ((list_req
              `L`
              (plain `name`))))
        (lit `")"`))
      `2`))
  (rule
    (name `cmdline`)
    (alt
      ((tok `INDENT`)
        (group_opt
          ((ref `dotlevel`)))
        (group_opt
          ((ref `cmds`))))
      `(1 dots:2 ...3)`))
  (rule
    (name `dotlevel`)
    (alt
      ((quantified
          (lit `"."`)
          (one_plus)))
      `1`))
  (rule
    (name `cmd`)
    (alt
      ((ref `set`)))
    (alt
      ((ref `new`)))
    (alt
      ((ref `merge`)))
    (alt
      ((ref `kill`)))
    (alt
      ((ref `if`)))
    (alt
      ((ref `else`)))
    (alt
      ((ref `for`)))
    (alt
      ((ref `do`)))
    (alt
      ((ref `goto`)))
    (alt
      ((ref `quit`)))
    (alt
      ((ref `break`)))
    (alt
      ((ref `hang`)))
    (alt
      ((ref `halt`)))
    (alt
      ((ref `job`)))
    (alt
      ((ref `xecute`)))
    (alt
      ((ref `view`)))
    (alt
      ((ref `open`)))
    (alt
      ((ref `use`)))
    (alt
      ((ref `read`)))
    (alt
      ((ref `write`)))
    (alt
      ((ref `close`)))
    (alt
      ((ref `lock`)))
    (alt
      ((ref `tstart`)))
    (alt
      ((ref `tcommit`)))
    (alt
      ((ref `trollback`)))
    (alt
      ((ref `trestart`)))
    (alt
      ((ref `zwrite`)))
    (alt
      ((ref `zbreak`)))
    (alt
      ((ref `zhalt`)))
    (alt
      ((ref `zkill`))))
  (rule
    (name `cmds`)
    (alt
      ((quantified
          (group
            ((ref `cmd`)
              (skip_q
                (tok `SPACES`)
                (opt))))
          (one_plus)))
      `1`))
  (rule
    (name `postcond`)
    (alt
      ((lit `":"`)
        (ref `expr`))
      `(postcond 2)`))
  (rule
    (name `set`)
    (alt
      ((tok `SET`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `setarg`)))
      `(set 2 ...3)`))
  (rule
    (name `setarg`)
    (alt
      ((lit `"@"`)
        (ref `atom`)
        (lit `"="`)
        (ref `expr`))
      `(@name 2 value:4)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`)
    (alt
      ((ref `glvn`)
        (lit `"="`)
        (ref `expr`))
      `(= 1 3)`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `setglvn`))
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      `(setmulti ...2 value:5)`)
    (alt
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
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (ref `setglvn`)
        (lit `")"`)
        (lit `"="`)
        (ref `expr`))
      `(setfn 2 4 value:7)`)
    (alt
      ((lit `"$"`)
        (ref `name`))
      `(setisv 2)`))
  (rule
    (name `setglvn`)
    (alt
      ((ref `glvn`)))
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
  (rule
    (name `new`)
    (alt
      ((tok `NEW`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `newarg`)))))
      `(new 2 ...3)`))
  (rule
    (name `newarg`)
    (alt
      ((ref `name`)))
    (alt
      ((lit `"$"`)
        (ref `name`))
      `(intrinsic 2)`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `lname`))
        (lit `")"`))
      `(exclusive ...2)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `merge`)
    (alt
      ((tok `MERGE`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `mergearg`)))
      `(merge 2 ...3)`))
  (rule
    (name `mergearg`)
    (alt
      ((ref `glvn`)
        (lit `"="`)
        (ref `glvn`))
      `(= 1 3)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `kill`)
    (alt
      ((tok `KILL`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `killarg`)))))
      `(kill 2 ...3)`))
  (rule
    (name `killarg`)
    (alt
      ((ref `glvn`)))
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `lname`))
        (lit `")"`))
      `(exclusive ...2)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `lname`)
    (alt
      ((ref `name`)))
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
  (rule
    (name `if`)
    (alt
      ((tok `IF`)
        (group_opt
          ((list_req
              `L`
              (plain `expr`)))))
      `(if ...2)`))
  (rule
    (name `else`)
    (alt
      ((tok `ELSE`))
      `(else)`))
  (rule
    (name `for`)
    (alt
      ((tok `FOR`)
        (group_opt
          ((ref `forargs`))))
      `(for ...2)`))
  (rule
    (name `forargs`)
    (alt
      ((ref `lvn`)
        (lit `"="`)
        (list_req
          `L`
          (plain `forparam`)))
      `(1 ...3)`)
    (alt
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
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(range 1 3 5)`)
    (alt
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(range 1 3)`)
    (alt
      ((ref `expr`))))
  (rule
    (name `do`)
    (alt
      ((tok `DO`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `doarg`)))))
      `(do 2 ...3)`))
  (rule
    (name `doarg`)
    (alt
      ((ref `indirrefcmd`)
        (group_opt
          ((ref `actuallist`)))
        (group_opt
          ((ref `postcond`))))
      `(call ref:1 args:2 postcond:3)`)
    (alt
      ((ref `entryref`)
        (group_opt
          ((ref `actuallist`)))
        (group_opt
          ((ref `postcond`))))
      `(call ref:1 args:2 postcond:3)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `goto`)
    (alt
      ((tok `GOTO`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `gotoarg`)))
      `(goto 2 ...3)`))
  (rule
    (name `gotoarg`)
    (alt
      ((ref `indirrefcmd`)
        (group_opt
          ((ref `postcond`))))
      `(ref:1 postcond:2)`)
    (alt
      ((ref `entryref`)
        (group_opt
          ((ref `postcond`))))
      `(ref:1 postcond:2)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `indirref`)
    (alt
      ((lit `"@"`)
        (ref `atom`)
        (group_opt
          ((lit `"+"`)
            (ref `entryoffset`)))
        (group_opt
          ((lit `"^"`)
            (ref `routineref`))))
      `(@ref label:2 offset:4 rtn:6)`))
  (rule
    (name `indirrefcmd`)
    (alt
      ((lit `"@"`)
        (ref `atom`)
        (lit `"+"`)
        (ref `entryoffset`)
        (group_opt
          ((lit `"^"`)
            (ref `routineref`))))
      `(@ref label:2 offset:4 rtn:6)`)
    (alt
      ((lit `"@"`)
        (ref `atom`)
        (lit `"^"`)
        (ref `routineref`))
      `(@ref label:2 rtn:4)`))
  (rule
    (name `quit`)
    (alt
      ((tok `QUIT`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((ref `expr`))))
      `(quit 2 3)`))
  (rule
    (name `break`)
    (alt
      ((tok `BREAK`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `breakarg`)))))
      `(break 2 ...3)`))
  (rule
    (name `breakarg`)
    (alt
      ((ref `expr`)
        (group_opt
          ((ref `postcond`))))
      `(1 2)`))
  (rule
    (name `hang`)
    (alt
      ((tok `HANG`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `expr`)))))
      `(hang 2 ...3)`))
  (rule
    (name `halt`)
    (alt
      ((tok `HALT`)
        (group_opt
          ((ref `postcond`))))
      `(halt 2)`))
  (rule
    (name `job`)
    (alt
      ((tok `JOB`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `jobarg`)))
      `(job 2 ...3)`))
  (rule
    (name `jobarg`)
    (alt
      ((lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `indirrefcmd`)
        (group_opt
          ((ref `actuallist`)))
        (group_opt
          ((ref `jobparams`))))
      `(ref:4 args:5 params:6 env:2)`)
    (alt
      ((lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `entryref`)
        (group_opt
          ((ref `actuallist`)))
        (group_opt
          ((ref `jobparams`))))
      `(ref:4 args:5 params:6 env:2)`)
    (alt
      ((ref `indirrefcmd`)
        (group_opt
          ((ref `actuallist`)))
        (group_opt
          ((ref `jobparams`))))
      `(ref:1 args:2 params:3)`)
    (alt
      ((ref `entryref`)
        (group_opt
          ((ref `actuallist`)))
        (group_opt
          ((ref `jobparams`))))
      `(ref:1 args:2 params:3)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `jobparams`)
    (alt
      ((lit `":"`)
        (group_opt
          ((ref `deviceparams`)))
        (group_opt
          ((ref `timeout`))))
      `(params:2 3)`))
  (rule
    (name `xecute`)
    (alt
      ((tok `XECUTE`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `xecutearg`)))
      `(xecute 2 ...3)`))
  (rule
    (name `xecutearg`)
    (alt
      ((ref `expr`)
        (group_opt
          ((ref `postcond`))))
      `(1 2)`))
  (rule
    (name `view`)
    (alt
      ((tok `VIEW`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `viewarg`)))
      `(view 2 ...3)`))
  (rule
    (name `viewarg`)
    (alt
      ((ref `expr`)
        (group_opt
          ((lit `":"`)
            (list_req
              `L`
              (plain `expr`)))))
      `(1 params:3)`))
  (rule
    (name `open`)
    (alt
      ((tok `OPEN`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `openarg`)))
      `(open 2 ...3)`))
  (rule
    (name `openarg`)
    (alt
      ((ref `expr`)
        (lit `":"`)
        (lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`)
        (lit `":"`)
        (ref `expr`))
      `(1 params:...4 timeout:7)`)
    (alt
      ((ref `expr`)
        (lit `":"`)
        (lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      `(1 params:...4)`)
    (alt
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(1 mode:3 timeout:5)`)
    (alt
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(1 mode:3)`)
    (alt
      ((ref `expr`))
      `(1)`))
  (rule
    (name `use`)
    (alt
      ((tok `USE`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `devicearg`)))
      `(use 2 ...3)`))
  (rule
    (name `read`)
    (alt
      ((tok `READ`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `readarg`)))
      `(read 2 ...3)`))
  (rule
    (name `readarg`)
    (alt
      ((ref `posformat`)))
    (alt
      ((lit `"/"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `(/ 2 ...4)`)
    (alt
      ((lit `"/"`)
        (ref `name`))
      `(/ 2)`)
    (alt
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`)
        (ref `timeout`))
      `(charindir 3 4)`)
    (alt
      ((lit `"*"`)
        (lit `"@"`)
        (ref `atom`)
        (exclude `":"`))
      `(charindir 3)`)
    (alt
      ((lit `"*"`)
        (ref `glvn`)
        (ref `timeout`))
      `(char 2 3)`)
    (alt
      ((lit `"*"`)
        (ref `glvn`)
        (exclude `":"`))
      `(char 2)`)
    (alt
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`)
        (ref `timeout`))
      `(# 1 3 4)`)
    (alt
      ((ref `glvn`)
        (lit `"#"`)
        (ref `expr`)
        (exclude `":"`))
      `(# 1 3)`)
    (alt
      ((ref `glvn`)
        (ref `timeout`))
      `(1 2)`)
    (alt
      ((ref `glvn`)
        (exclude `"#"`)
        (exclude `":"`))
      `1`)
    (alt
      ((tok `STRING`))
      `(prompt 1)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `write`)
    (alt
      ((tok `WRITE`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `writearg`)))))
      `(write 2 ...3)`))
  (rule
    (name `writearg`)
    (alt
      ((ref `posformat`)))
    (alt
      ((lit `"/"`)
        (ref `name`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `(/ 2 ...4)`)
    (alt
      ((lit `"/"`)
        (ref `name`))
      `(/ 2)`)
    (alt
      ((lit `"*"`)
        (ref `expr`))
      `(* 2)`)
    (alt
      ((ref `expr`))))
  (rule
    (name `banghash`)
    (alt
      ((lit `"!"`)))
    (alt
      ((lit `"#"`)))
    (alt
      ((tok `EXCLAIM_WS`)))
    (alt
      ((tok `HASH_WS`))))
  (rule
    (name `tabcol`)
    (alt
      ((lit `"?"`)
        (ref `expr`)
        (quantified
          (tok `PATEND`)
          (opt)))
      `(? 2)`))
  (rule
    (name `posformat`)
    (alt
      ((quantified
          (ref `banghash`)
          (one_plus))
        (group_opt
          ((ref `tabcol`))))
      `(posformat ...1 2)`)
    (alt
      ((ref `tabcol`))
      `1`)
    (alt
      ((tok `COLIND`)
        (ref `atom`))
      `(?@ 2)`))
  (rule
    (name `close`)
    (alt
      ((tok `CLOSE`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `devicearg`)))
      `(close 2 ...3)`))
  (rule
    (name `devicearg`)
    (alt
      ((ref `expr`)
        (lit `":"`)
        (ref `deviceparams`))
      `(1 params:3)`)
    (alt
      ((ref `expr`))
      `(1)`))
  (rule
    (name `deviceparams`)
    (alt
      ((lit `"("`)
        (ref `deviceparamlist`)
        (lit `")"`))
      `2`)
    (alt
      ((ref `deviceparam`))))
  (rule
    (name `deviceparamlist`)
    (alt
      ((ref `deviceparam`)
        (lit `":"`)
        (ref `deviceparamlist`))
      `(1 ...3)`)
    (alt
      ((ref `deviceparam`))
      `(1)`))
  (rule
    (name `deviceparam`)
    (alt
      ((lit `"/"`)
        (ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(attr 2 value:4)`)
    (alt
      ((lit `"/"`)
        (ref `name`))
      `(keyword 2)`)
    (alt
      ((ref `name`)
        (lit `"="`)
        (ref `expr`))
      `(attr 1 value:3)`)
    (alt
      ((ref `expr`))))
  (rule
    (name `timeout`)
    (alt
      ((lit `":"`)
        (ref `expr`))
      `2`))
  (rule
    (name `lock`)
    (alt
      ((tok `LOCK`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `lockarg`)))))
      `(lock 2 ...3)`))
  (rule
    (name `lockarg`)
    (alt
      ((ref `lockref`)
        (group_opt
          ((ref `timeout`))))
      `(lock= 1 2)`)
    (alt
      ((lit `"+"`)
        (ref `lockref`)
        (group_opt
          ((ref `timeout`))))
      `(lock+ 2 timeout:3)`)
    (alt
      ((lit `"-"`)
        (ref `lockref`)
        (group_opt
          ((ref `timeout`))))
      `(lock- 2 timeout:3)`)
    (alt
      ((lit `"+"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `lockref`))
        (lit `")"`)
        (group_opt
          ((ref `timeout`))))
      `(lock+ multi ...3 timeout:5)`)
    (alt
      ((lit `"-"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `lockref`))
        (lit `")"`)
        (group_opt
          ((ref `timeout`))))
      `(lock- multi ...3 timeout:5)`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `lockref`))
        (lit `")"`)
        (group_opt
          ((ref `timeout`))))
      `(lock= multi ...2 timeout:4)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@args 2)`))
  (rule
    (name `lockref`)
    (alt
      ((ref `lvn`)))
    (alt
      ((ref `gvn`))))
  (rule
    (name `tstart`)
    (alt
      ((tok `TSTART`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((ref `tstartargs`))))
      `(tstart 2 ...3)`))
  (rule
    (name `tstartargs`)
    (alt
      ((ref `tstartarg`)
        (group_opt
          ((lit `":"`)
            (ref `tstartparams`))))
      `(1 params:3)`)
    (alt
      ((tok `COLON_WS`)
        (ref `tstartparams`))
      `(params:2)`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
  (rule
    (name `tstartparams`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `tstartparam`))
        (lit `")"`))
      `(...2)`)
    (alt
      ((list_req
          `L`
          (plain `tstartparam`)))))
  (rule
    (name `tstartarg`)
    (alt
      ((lit `"*"`))
      `(*)`)
    (alt
      ((lit `"("`)
        (group_opt
          ((list_req
              `L`
              (plain `lname`))))
        (lit `")"`))
      `(...2)`)
    (alt
      ((ref `lname`))))
  (rule
    (name `tstartparam`)
    (alt
      ((ref `name`)
        (group_opt
          ((lit `"="`)
            (ref `expr`))))
      `(1 3)`))
  (rule
    (name `tcommit`)
    (alt
      ((tok `TCOMMIT`)
        (group_opt
          ((ref `postcond`))))
      `(tcommit 2)`))
  (rule
    (name `trollback`)
    (alt
      ((tok `TROLLBACK`)
        (group_opt
          ((ref `postcond`))))
      `(trollback 2)`))
  (rule
    (name `trestart`)
    (alt
      ((tok `TRESTART`)
        (group_opt
          ((ref `postcond`))))
      `(trestart 2)`))
  (rule
    (name `zwrite`)
    (alt
      ((tok `ZWRITE`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `glvn`)))))
      `(zwrite 2 ...3)`))
  (rule
    (name `zbreak`)
    (alt
      ((tok `ZBREAK`)
        (group_opt
          ((ref `postcond`)))
        (group_opt
          ((list_req
              `L`
              (plain `gotoarg`)))))
      `(zbreak 2 ...3)`))
  (rule
    (name `zhalt`)
    (alt
      ((tok `ZHALT`)
        (group_opt
          ((ref `postcond`)))
        (ref `expr`))
      `(zhalt 2 code:3)`)
    (alt
      ((tok `ZHALT`)
        (group_opt
          ((ref `postcond`))))
      `(zhalt 2)`))
  (rule
    (name `zkill`)
    (alt
      ((tok `ZKILL`)
        (group_opt
          ((ref `postcond`)))
        (list_req
          `L`
          (plain `glvn`)))
      `(zkill 2 ...3)`))
  (rule
    (name `entryref`)
    (alt
      ((ref `label`)
        (group_opt
          ((lit `"+"`)
            (ref `entryoffset`)))
        (group_opt
          ((lit `"^"`)
            (ref `routineref`)))
        (exclude `":"`))
      `(ref 1 3 5)`)
    (alt
      ((lit `"+"`)
        (ref `entryoffset`)
        (lit `"^"`)
        (ref `routineref`)
        (exclude `":"`))
      `(ref _ 2 4)`)
    (alt
      ((lit `"^"`)
        (ref `routineref`)
        (exclude `":"`))
      `(ref _ _ 2)`))
  (rule
    (name `entryoffset`)
    (alt
      ((ref `expr`))))
  (rule
    (name `routineref`)
    (alt
      ((ref `name`)))
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)`))
  (rule
    (name `actuallist`)
    (alt
      ((lit `"("`)
        (group_opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      `2`))
  (rule
    (name `actual`)
    (alt
      ((lit `"."`)
        (ref `lname`))
      `(byref 2)`)
    (alt
      ((ref `expr`))))
  (rule
    (name `expr`)
    (alt
      ((ref `atom`)
        (ref `exprtails`))
      `(expr 1 ...2)`))
  (rule
    (name `exprtails`)
    (alt
      ((ref `exprtail`)
        (ref `exprtails`))
      `(!1 ...2)`)
    (alt_shift () `()`))
  (rule
    (name `exprtail`)
    (alt
      ((ref `binop`)
        (ref `atom`))
      `(~1 2)`)
    (alt
      ((lit `"?"`)
        (ref `pattern`))
      `(? 2)`)
    (alt
      ((lit `"'?"`)
        (ref `pattern`))
      `('? 2)`)
    (alt
      ((tok `PATIND`)
        (ref `atom`))
      `(?@ 2)`)
    (alt
      ((lit `"'?"`)
        (lit `"@"`)
        (ref `atom`))
      `('?@ 3)`))
  (rule
    (name `atom`)
    (alt
      ((lit `"("`)
        (ref `expr`)
        (lit `")"`))
      `2`)
    (alt
      ((ref `unaryop`)
        (ref `atom`))
      `(1 2)`)
    (alt
      ((lit `"@"`)
        (ref `atom`)
        (exclude `"@"`))
      `(@name 2)`)
    (alt
      ((ref `glvn`)))
    (alt
      ((ref `literal`)))
    (alt
      ((ref `fn`))))
  (rule
    (name `unaryop`)
    (alt
      ((lit `"'"`)))
    (alt
      ((lit `"+"`)))
    (alt
      ((lit `"-"`))))
  (rule
    (name `binop`)
    (alt
      ((lit `"_"`)))
    (alt
      ((lit `"+"`)))
    (alt
      ((lit `"-"`)))
    (alt
      ((lit `"*"`)))
    (alt
      ((lit `"/"`)))
    (alt
      ((lit `"\\\\"`)))
    (alt
      ((lit `"#"`)))
    (alt
      ((lit `"**"`)))
    (alt
      ((lit `"="`)))
    (alt
      ((lit `"=="`)))
    (alt
      ((lit `"'="`)))
    (alt
      ((lit `"<"`)))
    (alt
      ((lit `">"`)))
    (alt
      ((lit `"'<"`)))
    (alt
      ((lit `"'>"`)))
    (alt
      ((lit `"<="`)))
    (alt
      ((lit `">="`)))
    (alt
      ((lit `"["`)))
    (alt
      ((lit `"]"`)))
    (alt
      ((lit `"'["`)))
    (alt
      ((lit `"']"`)))
    (alt
      ((lit `"]="`)))
    (alt
      ((lit `"]]"`)))
    (alt
      ((lit `"]]="`)))
    (alt
      ((lit `"&"`)))
    (alt
      ((lit `"!"`)))
    (alt
      ((lit `"'&"`)))
    (alt
      ((lit `"'!"`)))
    (alt
      ((lit `"!!"`))))
  (rule
    (name `pattern`)
    (alt
      ((quantified
          (ref `patatom`)
          (one_plus))
        (tok `PATEND`))
      `1`))
  (rule
    (name `patatom`)
    (alt
      ((ref `repcount`)
        (quantified
          (ref `patcode`)
          (one_plus))
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      `(pat 1 codes:2 capture:4)`)
    (alt
      ((ref `repcount`)
        (quantified
          (ref `patcode`)
          (one_plus)))
      `(pat 1 codes:2)`)
    (alt
      ((ref `patcode`)
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      `(pat 1 capture:3)`)
    (alt
      ((ref `patcode`))
      `(pat 1)`)
    (alt
      ((ref `repcount`)
        (ref `patstr`)
        (lit `"("`)
        (ref `glvn`)
        (lit `")"`))
      `(pat 1 2 capture:4)`)
    (alt
      ((ref `repcount`)
        (ref `patstr`))
      `(pat 1 2)`)
    (alt
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
      ((quantified
          (ref `patatom`)
          (one_plus)))))
  (rule
    (name `repcount`)
    (alt
      ((ref `number`)
        (lit `"."`)
        (ref `number`))
      `(1 3)`)
    (alt
      ((ref `number`)
        (lit `"."`))
      `(1 _)`)
    (alt
      ((ref `number`))
      `(1 1)`)
    (alt
      ((lit `"."`)
        (ref `number`))
      `(_ 2)`)
    (alt
      ((lit `"."`))
      `()`))
  (rule
    (name `patcode`)
    (alt
      ((tok `IDENT`))))
  (rule
    (name `patstr`)
    (alt
      ((group_opt
          ((lit `"'"`)))
        (tok `STRING`))
      `(1 2)`))
  (rule
    (name `glvn`)
    (alt
      ((ref `lvn`)))
    (alt
      ((ref `ssvn`)))
    (alt
      ((ref `gvn`))))
  (rule
    (name `lvn`)
    (alt
      ((ref `rlvn`))))
  (rule
    (name `rlvn`)
    (alt
      ((ref `name`)
        (exclude `"("`))
      `(lvar 1)`)
    (alt
      ((ref `name`)
        (ref `subs`))
      `(lvar 1 subs:2)`)
    (alt
      ((lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      `(@subs 2 4)`))
  (rule
    (name `gvn`)
    (alt
      ((ref `rgvn`)))
    (alt
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (exclude `"@"`))
      `(@gname 3)`))
  (rule
    (name `rgvn`)
    (alt
      ((lit `"^"`)
        (ref `name`)
        (ref `subs`))
      `(gvar 2 subs:3)`)
    (alt
      ((lit `"^"`)
        (ref `name`)
        (exclude `"("`))
      `(gvar 2)`)
    (alt
      ((lit `"^"`)
        (lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `(naked ...3)`)
    (alt
      ((lit `"^"`)
        (lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      `(@subs 3 5)`)
    (alt
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (ref `name`)
        (group_opt
          ((ref `subs`))))
      `(gvar 5 subs:6 env:3)`)
    (alt
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `","`)
        (ref `expr`)
        (lit `"|"`)
        (ref `name`)
        (group_opt
          ((ref `subs`))))
      `(gvar 7 subs:8 env:3 uci:5)`)
    (alt
      ((lit `"^"`)
        (lit `"["`)
        (ref `expr`)
        (lit `"]"`)
        (ref `name`)
        (group_opt
          ((ref `subs`))))
      `(gvar 5 subs:6 env:3)`)
    (alt
      ((lit `"^"`)
        (lit `"["`)
        (ref `expr`)
        (lit `","`)
        (ref `expr`)
        (lit `"]"`)
        (ref `name`)
        (group_opt
          ((ref `subs`))))
      `(gvar 7 subs:8 env:3 uci:5)`))
  (rule
    (name `ssvn`)
    (alt
      ((lit `"^"`)
        (lit `"$"`)
        (lit `"@"`)
        (ref `atom`)
        (lit `"@"`)
        (ref `subs`))
      `(@ssvn 4 6)`)
    (alt
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (lit `"$"`)
        (tok `SSVN`)
        (exclude `"("`))
      `(ssvn ~6 env:3)`)
    (alt
      ((lit `"^"`)
        (lit `"|"`)
        (ref `expr`)
        (lit `"|"`)
        (lit `"$"`)
        (tok `SSVN`)
        (ref `subs`))
      `(ssvn ~6 subs:7 env:3)`)
    (alt
      ((lit `"^"`)
        (lit `"$"`)
        (tok `SSVN`)
        (exclude `"("`))
      `(ssvn ~3)`)
    (alt
      ((lit `"^"`)
        (lit `"$"`)
        (tok `SSVN`)
        (ref `subs`))
      `(ssvn ~3 subs:4)`))
  (rule
    (name `subs`)
    (alt
      ((lit `"("`)
        (list_req
          `L`
          (plain `expr`))
        (lit `")"`))
      `2`))
  (rule
    (name `number`)
    (alt
      ((tok `INTEGER`)))
    (alt
      ((tok `ZDIGITS`)))
    (alt
      ((tok `REAL`))))
  (rule
    (name `literal`)
    (alt
      ((ref `number`))
      `(num 1)`)
    (alt
      ((tok `STRING`))
      `(str 1)`))
  (rule
    (name `fn`)
    (alt
      ((ref `select`)))
    (alt
      ((ref `text`)))
    (alt
      ((ref `justify`)))
    (alt
      ((ref `increment`)))
    (alt
      ((lit `"$"`)
        (lit `"$"`)
        (ref `extrinsicref`))
      `(extrinsic 3)     # extrinsic: $$FOO or $$FOO()`)
    (alt
      ((lit `"$"`)
        (tok `TEXT`)
        (exclude `"("`))
      `(intrinsic ~2)    # $T alone = $TEST ISV`)
    (alt
      ((lit `"$"`)
        (tok `SELECT`)
        (exclude `"("`))
      `(intrinsic ~2)    # $S alone = $STORAGE ISV`)
    (alt
      ((lit `"$"`)
        (tok `JUSTIFY`)
        (exclude `"("`))
      `(intrinsic ~2)    # $J alone = $JOB ISV`)
    (alt
      ((lit `"$"`)
        (tok `INCREMENT`)
        (exclude `"("`))
      `(intrinsic ~2)    # $I alone = $IO ISV`)
    (alt
      ((lit `"$"`)
        (tok `FN`)
        (exclude `"("`))
      `(intrinsic ~2)    # $Q=$QUIT, $TR=$TRESTART, etc.`)
    (alt
      ((lit `"$"`)
        (tok `ISV`))
      `(intrinsic ~2)    # ISVs: $H, $X, $Y, etc.`)
    (alt
      ((lit `"$"`)
        (tok `FN`)
        (lit `"("`)
        (group_opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      `(intrinsic ~2 4)  # function with args`)
    (alt
      ((lit `"$"`)
        (ref `name`)
        (lit `"("`)
        (group_opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      `(intrinsic 2 4)   # unknown function`)
    (alt
      ((lit `"$"`)
        (ref `name`)
        (exclude `"("`))
      `(intrinsic 2)     # unknown ISV (not if ( follows)`))
  (rule
    (name `extrinsicref`)
    (alt
      ((ref `labelref`)
        (lit `"("`)
        (group_opt
          ((list_req
              `L`
              (opt_items_nosep `actual`))))
        (lit `")"`))
      `(1 args:3)        # $$FOO() or $$FOO(a,b)`)
    (alt
      ((ref `labelref`)
        (exclude `"("`))
      `1                 # $$FOO`)
    (alt
      ((lit `"@"`)
        (ref `atom`))
      `(@name 2)          # $$@var (args via @-string only;`))
  (rule
    (name `select`)
    (alt
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
      ((ref `expr`)
        (lit `":"`)
        (ref `expr`))
      `(1 3)`))
  (rule
    (name `text`)
    (alt
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (ref `indirref`)
        (lit `")"`))
      `(text 4)`)
    (alt
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (ref `label`)
        (group_opt
          ((lit `"+"`)
            (ref `expr`)))
        (group_opt
          ((lit `"^"`)
            (ref `routineref`)))
        (lit `")"`))
      `(text 4 6 8)`)
    (alt
      ((lit `"$"`)
        (tok `TEXT`)
        (lit `"("`)
        (lit `"+"`)
        (ref `expr`)
        (group_opt
          ((lit `"^"`)
            (ref `routineref`)))
        (lit `")"`))
      `(text _ 5 7)`)
    (alt
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
      ((lit `"$"`)
        (tok `JUSTIFY`)
        (lit `"("`)
        (group_opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      `(intrinsic ~2 4)`))
  (rule
    (name `increment`)
    (alt
      ((lit `"$"`)
        (tok `INCREMENT`)
        (lit `"("`)
        (group_opt
          ((list_req
              `L`
              (plain `expr`))))
        (lit `")"`))
      `(intrinsic ~2 4)`))
  (rule
    (name `labelref`)
    (alt
      ((ref `label`)
        (lit `"^"`)
        (ref `routineref`))
      `(1 routine:3)`)
    (alt
      ((ref `label`)
        (exclude `"^"`))
      `1`)
    (alt
      ((lit `"^"`)
        (ref `routineref`))
      `(routine:2)`)))
