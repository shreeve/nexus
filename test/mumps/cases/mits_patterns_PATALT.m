PATALT ; MITS - pattern alternation and complex patterns
 ;
 ; Pattern alternation: ?(pat1,pat2,pat3) matches if ANY of the
 ; alternatives match. Repcount applies to the whole group.
 ;
 D START^TEST("compliance/patterns/PATALT")
 ;
 ; --- Simple alternation ---
 D RUN^TEST("(N,A) numeric matches",1,"""5""?1(1N,1A)")
 D RUN^TEST("(N,A) alpha matches",1,"""x""?1(1N,1A)")
 D RUN^TEST("(N,A) reject other",0,"""!""?1(1N,1A)")
 ;
 ; --- Repcount over alternation ---
 D RUN^TEST("3(N,A) all alpha",1,"""abc""?3(1N,1A)")
 D RUN^TEST("3(N,A) mixed",1,"""a1b""?3(1N,1A)")
 D RUN^TEST("3(N,A) all numeric",1,"""123""?3(1N,1A)")
 D RUN^TEST("3(N,A) reject punct",0,"""ab!""?3(1N,1A)")
 ;
 ; --- Open-ended .(group) ---
 D RUN^TEST(".(N,A) zero matches",1,"""""?.(1N,1A)")
 D RUN^TEST(".(N,A) many matches",1,"""abc123def""?.(1N,1A)")
 D RUN^TEST(".(N,A) reject single bad",0,"""abc!""?.(1N,1A)")
 ;
 ; --- Three-way alternation ---
 D RUN^TEST("(N,A,P) numeric",1,"""1""?1(1N,1A,1P)")
 D RUN^TEST("(N,A,P) alpha",1,"""x""?1(1N,1A,1P)")
 D RUN^TEST("(N,A,P) punct",1,"""!""?1(1N,1A,1P)")
 D RUN^TEST("(N,A,P) reject control char",0,"$C(0)?1(1N,1A,1P)")
 ;
 ; --- Literal in alternation ---
 D RUN^TEST("(`AB`,2N) literal",1,"""AB""?1(1""AB"",2N)")
 D RUN^TEST("(`AB`,2N) numeric",1,"""47""?1(1""AB"",2N)")
 D RUN^TEST("(`AB`,2N) reject",0,"""XY""?1(1""AB"",2N)")
 ;
 ; --- Range with negation (' before group not standard but '?-prefix is) ---
 D RUN^TEST("'? negation",1,"""abc""'?3N")
 D RUN^TEST("'? on matching pattern",0,"""123""'?3N")
 ;
 ; --- Nested patterns: literal alternation in concatenation ---
 D RUN^TEST("phone-like with optional dash",1,"""555-1234""?3N1(1""-"")4N")
 D RUN^TEST("space-or-dash-separated",1,"""555 1234""?3N1(1""-"",1"" "")4N")
 ;
 D END^TEST("compliance/patterns/PATALT")
 Q
