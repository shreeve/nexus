SAMPLE ; Every token and context of M's editor colouring; read, not run
 ;
EN(A,B) ; a label with formals
 N X,Y S X=1,Y="say ""hi""" W X,!
 S X1=2,A=X1_1,%B=X1 ; names with digits and %
 S:A>0 ^G(1,"a")=A+B I X=1 W "one",! E  W "other",!
 Q:'$D(^G(1))  K ^G
 F I=1:1:10 S X=X+I Q:X>20
 . W !,?5,"level one"
 . . W $J(X,6,2),$E("abc",1,2),$P(Y,"^",2)
 S X=$H,Y=$ZH,Z=$T(EN+1^SAMPLE)
 D TAG^SAMPLE,^SAMPLE G EN^SAMPLE
 S X=$$EXT(1)+$$EXT^SAMPLE(2)
 I X?1.3N1"-"2A W "pattern" I X'?.E1"x" W "not"
 S X=12+3.5-.5*1E3/2\3#4**2_"s",Y=007
 I X'=1,X'<2,X'>3,X]Y,X]]Y,X']]Y,X[Y W 1
 S @X=1,X=@Y@(2) I X=1!(Y=2)&'Z W 1
 S X=$O(^$GLOBAL("^G")),Y=$G(^$JOB($J,"X"))
 W X S Y=1 ; X after W is a variable, coloured as XECUTE: a regex sees no parse
1 Q
%Z Q $ZV
EXT(N) Q N*2
