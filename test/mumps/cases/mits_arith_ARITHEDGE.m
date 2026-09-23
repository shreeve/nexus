ARITHEDGE ; MITS - arithmetic edge cases (boundaries, signs, special values)
 ;
 D START^TEST("compliance/arith/ARITHEDGE")
 ;
 ; --- Sign combinations across all operators ---
 D RUN^TEST("(+,+) +",5,"3+2")
 D RUN^TEST("(+,-) +",1,"3+-2")
 D RUN^TEST("(-,-) +",-5,"-3+-2")
 D RUN^TEST("(+,+) -",1,"3-2")
 D RUN^TEST("(+,-) -",5,"3--2")
 D RUN^TEST("(-,-) -",-1,"-3--2")
 D RUN^TEST("(+,+) *",6,"3*2")
 D RUN^TEST("(+,-) *",-6,"3*-2")
 D RUN^TEST("(-,-) *",6,"-3*-2")
 D RUN^TEST("(+,+) /",1.5,"3/2")
 D RUN^TEST("(+,-) /",-1.5,"3/-2")
 D RUN^TEST("(-,-) /",1.5,"-3/-2")
 ;
 ; --- Integer divide \ sign-of-result rules ---
 D RUN^TEST("\ pos by pos",2,"5\2")
 D RUN^TEST("\ neg by pos truncates toward 0",-2,"-5\2")
 D RUN^TEST("\ pos by neg truncates toward 0",-2,"5\-2")
 D RUN^TEST("\ neg by neg",2,"-5\-2")
 ;
 ; --- Modulo # sign-of-divisor rule ---
 D RUN^TEST("# pos by pos",1,"7#3")
 D RUN^TEST("# neg by pos result is positive",2,"-7#3")
 D RUN^TEST("# pos by neg result is negative",-2,"7#-3")
 D RUN^TEST("# neg by neg",-1,"-7#-3")
 ;
 ; --- Zero in various positions ---
 D RUN^TEST("0+0",0,"0+0")
 D RUN^TEST("0*0",0,"0*0")
 D RUN^TEST("0*5",0,"0*5")
 D RUN^TEST("0/5",0,"0/5")
 D RUN^TEST("0\\ 5",0,"0\5")
 D RUN^TEST("0#5",0,"0#5")
 ;
 ; --- Identities ---
 D RUN^TEST("x+0=x",42,"42+0")
 D RUN^TEST("x-0=x",42,"42-0")
 D RUN^TEST("x*1=x",42,"42*1")
 D RUN^TEST("x/1=x",42,"42/1")
 D RUN^TEST("x*0=0",0,"42*0")
 ;
 ; --- Decimal sign edges ---
 D RUN^TEST(".5+-.5",0,".5+-.5")
 D RUN^TEST("-.5+.5",0,"-.5+.5")
 D RUN^TEST("-.0+0",0,"-.0+0")
 D RUN^TEST(".0001*10000",1,".0001*10000")
 ;
 ; --- Mixed-sign chains (left-to-right MUMPS) ---
 D RUN^TEST("3-1+2",4,"3-1+2")
 D RUN^TEST("3+1-2",2,"3+1-2")
 D RUN^TEST("3-1-2",0,"3-1-2")
 D RUN^TEST("2*3+1",7,"2*3+1")
 D RUN^TEST("2*-3+1",-5,"2*-3+1")
 ;
 ; --- Power operator (** is supported in some MUMPS dialects) ---
 D RUN^TEST("** integer power",16,"2**4")
 D RUN^TEST("** zero exponent",1,"5**0")
 D RUN^TEST("** negative exponent",.25,"2**-2")
 D RUN^TEST("** decimal exponent (sqrt)",2,"4**.5")
 ;
 D END^TEST("compliance/arith/ARITHEDGE")
 Q
