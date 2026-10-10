ISVS ; MITS - intrinsic special variable tests
 ;
 ; Tests $TEST, $JOB, $STORAGE, $TLEVEL, $HOROLOG, $ZHOROLOG, $ZUT
 ; behavior. Some ISVs (like $H, $JOB) return runtime values; we
 ; assert structural properties rather than literal matches.
 ;
 D START^TEST("compliance/isvs/ISVS")
 ;
 ; --- $TEST / $T ---
 D RUN^TEST("$T after IF true",1,"$$TT^ISVS()")
 D RUN^TEST("$T after IF false",0,"$$TF^ISVS()")
 D RUN^TEST("$T persists across non-IF",1,"$$TP^ISVS()")
 ;
 ; --- $TLEVEL ---
 D RUN^TEST("$TLEVEL = 0 outside transaction",0,"$$TL^ISVS()")
 ;
 ; --- $JOB > 0 (process id) ---
 D RUN^TEST("$JOB > 0",1,"$$JBP^ISVS()")
 D RUN^TEST("$JOB constant within process",1,"$$JBC^ISVS()")
 ;
 ; --- $HOROLOG format ---
 D RUN^TEST("$H has 1 comma",1,"$$HCOMMA^ISVS()")
 D RUN^TEST("$H first piece is positive int",1,"$$HDAYS^ISVS()")
 D RUN^TEST("$H second piece is 0..86399",1,"$$HSEC^ISVS()")
 ;
 ; --- $ZHOROLOG format ---
 D RUN^TEST("$ZH has 3 commas",3,"$$ZHC^ISVS()")
 D RUN^TEST("$ZH us field is 0..999999",1,"$$ZHUS^ISVS()")
 ;
 ; --- $ZUT ---
 D RUN^TEST("$ZUT is positive integer",1,"$$ZUTP^ISVS()")
 D RUN^TEST("$ZUT increases monotonically",1,"$$ZUTM^ISVS()")
 ;
 ; --- $STORAGE > 0 ---
 D RUN^TEST("$STORAGE > 0",1,"$$STG^ISVS()")
 ;
 D END^TEST("compliance/isvs/ISVS")
 Q
 ;
TT() I 1 Q $T
 Q -1
 ;
TF() I 0  ; $T = 0 after a falsy IF
 Q $T
 ;
TP() N x I 1 S x=1
 ; $T set by IF; x=1 is unrelated.
 Q $T
 ;
TL() Q $TLEVEL
 ;
JBP() Q $S($JOB>0:1,1:0)
 ;
JBC() N a,b S a=$JOB
 ; Some computation
 N i F i=1:1:100 S b=i
 S b=$JOB
 Q $S(a=b:1,1:0)
 ;
HCOMMA() Q $L($H,",")-1
 ;
HDAYS() N d S d=$P($H,",",1)
 Q $S(d>0:1,1:0)
 ;
HSEC() N s S s=$P($H,",",2)
 Q $S(s>=0&(s<86400):1,1:0)
 ;
ZHC() Q $L($ZH,",")-1
 ;
ZHUS() N us S us=$P($ZH,",",3)
 Q $S(us>=0&(us<1000000):1,1:0)
 ;
ZUTP() N z S z=$ZUT
 Q $S(z>0:1,1:0)
 ;
ZUTM() N a,b,i S a=$ZUT
 F i=1:1:1000 S b=i
 S b=$ZUT
 Q $S(b>=a:1,1:0)
 ;
STG() Q $S($STORAGE>0:1,1:0)
