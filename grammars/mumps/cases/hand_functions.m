FUNCS ;
 S X=$P("a^b^c","^",2),Y=$E(X,1,3),Z=$L(X)
 S X=$S(A=1:"one",A=2:"two",1:"other")
 S X=$O(^G(X)),Y=$O(^G(X),-1),Z=$D(^G),W=$G(^G(1),"dflt")
 S X=$$EXT^RTN(1,.Y),Y=$$LOCAL(),Z=$$^RTN
 S X=$T(LABEL+1^RTN),Y=$TR(X,"ab","AB"),Z=$J(X,10,2)
 S X=$H,Y=$J,Z=$T,A=$IO,B=$ZV
 S X=$NA(^G(1,2)),Y=$QS(X,1),Z=$QL(X),W=$Q(^G)
 S X=$C(65,66),Y=$A("A"),Z=$F(X,"B"),W=$FN(X,",",2)
 S X=^$JOB($J,"x")
 Q
