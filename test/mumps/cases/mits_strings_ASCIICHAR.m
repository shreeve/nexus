ASCIICHAR ; MITS - auto-generated from MVTS via tools/build-mits.pl
 ;
 ; Source: MVTS routines (see tools/mine-mvts.pl for extraction).
 ; To regenerate:
 ;   tools/mine-mvts.pl ../test/compliance/routines | tools/build-mits.pl
 ;
 D START^TEST("compliance/strings/ASCIICHAR")
 ;
 D RUN^TEST("I-4 Integer interpretation of intexpr, while intexpr is numeric ","EF","$CHAR(0.0069E+4,35.2*2.001)")
 D RUN^TEST("I-5 Integer interpretation of intexpr, while intexpr contains bi"," AB","$C(15+15+2,+""66ABC""--2-3,""6""_""6"")")
 D RUN^TEST("I-10 expr is string literal, and $L(expr)>0",42,"$A(""*|^=09876"")")
 D RUN^TEST("I-11 expr is numeric literal, and $L(expr)=1 i.e. expr is a digit",50,"$A(02)")
 D RUN^TEST("I-13 expr is numeric literal, and $L(expr)>1,expr<=0",48,"$A(.00E3)")
 D RUN^TEST("I-16 expr1 is non-integer numeric literal, and greater than zero",53,"$A(034.95165E2,00.04000E+2)")
 D RUN^TEST("I-17 expr1 is non-integer numeric literal, and less than zero",46,"$A(-00.000034567000E+008,6000E-3)")
 D RUN^TEST("I-18 expr1 is integer numeric literal, and greater than zero","52","$A(00000234650.0000,2+1)")
 D RUN^TEST("I-20/21.2 intexpr2 is greater than $L(expr1)","-1","$A(1,2)")
 ;
 D END^TEST("compliance/strings/ASCIICHAR")
 Q
