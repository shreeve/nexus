DO ; MITS - DO command tests
 ;
 ; DO label[+offset]                    no args, scope-NEW
 ; DO label[+offset](arg1,arg2,...)     with args (positional or formal)
 ; DO label[+offset]^routine            cross-routine
 ; DO:cond label                        postconditional
 ; DO @nameindirect                     indirected target
 ;
 D START^TEST("compliance/control/DO")
 ;
 ; --- Basic DO (no args) ---
 D RUN^TEST("DO label sets",42,"$$DOLBL^DO()")
 D RUN^TEST("DO returns to caller",1,"$$DORET^DO()")
 ;
 ; --- DO with args ---
 D RUN^TEST("DO with 1 arg",5,"$$DO1^DO()")
 D RUN^TEST("DO with 3 args",6,"$$DO3^DO()")
 D RUN^TEST("DO with default formal",10,"$$DODEF^DO()")
 ;
 ; --- DO postconditional ---
 D RUN^TEST("DO:1 runs","yes","$$DOPCT^DO()")
 D RUN^TEST("DO:0 skips","no","$$DOPCF^DO()")
 ;
 ; --- Nested DO ---
 D RUN^TEST("DO 2-deep","inner","$$DONEST2^DO()")
 D RUN^TEST("DO 3-deep","leaf","$$DONEST3^DO()")
 ;
 ; --- DO with offset (DO LABEL+1) ---
 D RUN^TEST("DO label+1 starts at offset","second","$$DOOFF^DO()")
 ;
 ; --- DO modifies caller's locals when no NEW used ---
 D RUN^TEST("DO without NEW shares scope","mod","$$DOSHARE^DO()")
 ;
 ; --- DO from inside FOR ---
 D RUN^TEST("DO inside FOR runs each iter",10,"$$DOFOR^DO()")
 ;
 ; --- Argumentless DO (block dot syntax) ---
 D RUN^TEST("argumentless DO with dotted block",6,"$$DOBLOCK^DO()")
 ;
 D END^TEST("compliance/control/DO")
 Q
 ;
DOLBL() N r D LBL1
 Q r
LBL1 N x S r=42
 Q
 ;
DORET() N r S r=0 D LBL2 S r=r+1
 Q r
LBL2 Q
 ;
DO1() N r D ADD1(5)
 Q r
ADD1(a) S r=a
 Q
 ;
DO3() N r D ADD3(1,2,3)
 Q r
ADD3(a,b,c) S r=a+b+c
 Q
 ;
DODEF() N r D ADDDEF(10)
 Q r
ADDDEF(a,b) ; b not passed; treated as undefined (we use $G to default)
 S r=a+$G(b,0)
 Q
 ;
DOPCT() N r S r="no" D:1 SETOK
 Q r
SETOK S r="yes"
 Q
 ;
DOPCF() N r S r="no" D:0 SETOK2
 Q r
SETOK2 S r="yes"
 Q
 ;
DONEST2() N r D LVL1
 Q r
LVL1 D LVL2
 Q
LVL2 S r="inner"
 Q
 ;
DONEST3() N r D L1
 Q r
L1 D L2
 Q
L2 D L3
 Q
L3 S r="leaf"
 Q
 ;
DOOFF() N r D LBLOFF+1
 Q r
LBLOFF S r="first" Q
 S r="second" Q
 ;
DOSHARE() N r S r="orig" D MUT
 Q r
MUT S r="mod"
 Q
 ;
DOFOR() N r,i S r=0
 F i=1:1:10 D INC
 Q r
INC S r=r+1
 Q
 ;
DOBLOCK() N r,i S r=0
 ; Argumentless DO + dotted-block: indented '.' lines form the block
 F i=1:1:3 D
 . S r=r+i
 Q r
