BOOLEAN ; MITS - boolean / truthiness operator tests
 ;
 ; MUMPS truthiness:
 ;   - any non-zero NUMERIC value coerces to true
 ;   - the empty string and "0" coerce to false
 ;   - non-numeric strings coerce to 0 (per leading()) → false
 ;   - "5abc" coerces to 5 → true
 ;
 ; Logical ops:
 ;   &  AND   ! OR   '  NOT
 ; ALL operators are LEFT-TO-RIGHT, no precedence — use parens.
 ;
 D START^TEST("compliance/operators/BOOLEAN")
 ;
 ; --- Truthiness coercion ---
 D RUN^TEST("nonzero number truthy",1,"'(0=5)") ; 0=5 is 0; '(0) is 1
 D RUN^TEST("zero is falsy",1,"'0")
 D RUN^TEST("empty string is falsy",1,"'""""")
 D RUN^TEST("'0' is falsy",1,"'""0""")
 D RUN^TEST("'5abc' is truthy",1,"'('+""5abc"")") ; +""5abc""=5, '(5)=0, '0=1
 D RUN^TEST("'abc' is falsy",1,"'+""abc""") ; "abc"→0, '0=1
 ;
 ; --- AND ---
 D RUN^TEST("1&1 = 1",1,"1&1")
 D RUN^TEST("1&0 = 0",0,"1&0")
 D RUN^TEST("0&1 = 0",0,"0&1")
 D RUN^TEST("0&0 = 0",0,"0&0")
 D RUN^TEST("nonzero & nonzero = 1",1,"5&7")
 D RUN^TEST("'yes' & 1 (str→0)",0,"""yes""&1") ; "yes"→0
 ;
 ; --- OR ---
 D RUN^TEST("1!0 = 1",1,"1!0")
 D RUN^TEST("0!0 = 0",0,"0!0")
 D RUN^TEST("0!1 = 1",1,"0!1")
 D RUN^TEST("'abc' ! 1 (str→0, then or)",1,"""abc""!1")
 ;
 ; --- NOT ---
 D RUN^TEST("'1 = 0",0,"'1")
 D RUN^TEST("'0 = 1",1,"'0")
 D RUN^TEST("''1 = 1",1,"''1")
 D RUN^TEST("''abc' = 1",1,"'""abc""") ; "abc"→0; '0=1
 ;
 ; --- Combinations (left-to-right, no precedence) ---
 D RUN^TEST("1&0!1 → ((1&0)!1) = 1",1,"1&0!1")
 D RUN^TEST("0!1&0 → ((0!1)&0) = 0",0,"0!1&0")
 D RUN^TEST("'(0&1)",1,"'(0&1)")
 D RUN^TEST("'1&0 → ('1)&0 = 0",0,"'1&0")
 D RUN^TEST("'0&1 → ('0)&1 = 1",1,"'0&1")
 ;
 D END^TEST("compliance/operators/BOOLEAN")
 Q
