FNV2 ; MITS - auto-generated from MVTS via tools/build-mits.pl
 ;
 ; Source: MVTS routines (see tools/mine-mvts.pl for extraction).
 ; To regenerate:
 ;   tools/mine-mvts.pl ../test/compliance/routines | tools/build-mits.pl
 ;
 D START^TEST("compliance/functions/FNV2")
 ;
 D RUN^TEST("II-82  $L(expr1,expr2)=3","33","$L(""AAAA"",""AA"")_$l(""0000000000"",""00000"")")
 D RUN^TEST("II-83  $L(expr1,expr2)=2",22,"$L(""AAAA"",""AAA"")_$L(""0000000000"",""00000000"")")
 ;
 D END^TEST("compliance/functions/FNV2")
 Q
