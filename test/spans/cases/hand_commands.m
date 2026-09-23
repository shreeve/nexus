CMDS ;
 S X=1,Y(1,2)="a",^G(X)=Y(1,2)
 S $P(X,"^",2)=5,(A,B,C)=0
 W !,"Hello",?10,X,#
 W:X>0 "pos" W:'X "zero"
 K X,Y K  K (A,B)
 N I,J N (K)
 F I=1:1:10 S J=I
 F  Q:X  S X=1
 F I=1,2,3:1:5,"a" W I
 I X=1 W "one"
 E  W "other"
 D LABEL,LABEL^RTN,^RTN,LABEL+2^RTN,@X,LBL(1,.Y)
 G LABEL:X=1,END
 X "S Y=2"
 L +^G(1):5 L -^G(1) L
 M A=B,^G=A
 O 51:"R":10 U 51 C 51
 R X:10,!,"Prompt: ",Y#5,*Z
 H 1 H
 J LABEL^RTN
 TS  TC  TRO
 Q:X=2 X
 s x=1 w x q
END Q
