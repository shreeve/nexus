ADD ; MITS — addition tests
 ;
 ; Covers MVTS arithmetic-addition coverage area (I-180-class) plus
 ; em-specific edge cases at the 18-digit canonical-mantissa boundary.
 ;
 D START^TEST("compliance/arith/ADD")
 ;
 ; --- Basic positive integers ---
 D RUN^TEST("add basic positive",3,"1+2")
 D RUN^TEST("add identity left",5,"0+5")
 D RUN^TEST("add identity right",5,"5+0")
 ; MUMPS evaluates left-to-right with NO operator precedence — so
 ; 3+4=4+3 parses as ((3+4)=4)+3 = 3, not the comparison 1.
 ; Tests for the comparison must use explicit parens.
 D RUN^TEST("add commutative",1,"(3+4)=(4+3)")
 D RUN^TEST("add associative",1,"((1+2)+3)=(1+(2+3))")
 ;
 ; --- Negative numbers and signs ---
 D RUN^TEST("add negative",-1,"1+-2")
 D RUN^TEST("add both negative",-3,"-1+-2")
 D RUN^TEST("add cancel to zero",0,"5+-5")
 D RUN^TEST("add neg cancel",0,"-5+5")
 ;
 ; --- Decimal fractions ---
 D RUN^TEST("add fraction simple",1.5,"1+0.5")
 D RUN^TEST("add fraction lossless",.3,".1+.2")
 D RUN^TEST("add fraction negative",.5,"1.5+-1")
 ;
 ; --- Large integers within 18-digit range ---
 D RUN^TEST("add large",1000000,"999999+1")
 D RUN^TEST("add large negative",-1000000,"-999999+-1")
 ;
 ; --- 18-digit boundary (em's canonical-mantissa invariant) ---
 D RUN^TEST("add at 18-digit boundary",1000000000000000000,"999999999999999999+1")
 D RUN^TEST("add crossing 18 digits",1000000000000000000,"999999999999999999+2")
 ;
 ; --- Scientific notation ---
 D RUN^TEST("add scientific small",.011,"1E-2+1E-3")
 D RUN^TEST("add scientific large",2000,"1E3+1E3")
 ;
 ; --- Mixed scale ---
 D RUN^TEST("add big plus small",1000000000.001,"1E9+.001")
 ;
 ; --- Multiple operands (left-to-right) ---
 D RUN^TEST("add three",6,"1+2+3")
 D RUN^TEST("add long chain",55,"1+2+3+4+5+6+7+8+9+10")
 ;
 ; --- Unary operators in addition context ---
 D RUN^TEST("add unary minus",2,"3+-1")
 D RUN^TEST("add double unary",4,"3+--1")
 D RUN^TEST("add triple unary",2,"3+---1")
 ;
 D END^TEST("compliance/arith/ADD")
 Q
