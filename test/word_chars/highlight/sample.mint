START ; Mint: commands, functions, labels and words
 S X=1,Y=TRUE_1 W X_"s",2_Y
 S S=S+1,L=$L(X),E=2_E I 'E Q
 I X=1 W "a ""b""" E  D EN
EN(S,W) Q:S<W  X "W 1"
10 S X=10,D=$D(X),Y=$E(X,1,2)
%Z Q TRUE%
 . W FALSE,X ; a comment
