DOMVTS ; MITS - DO command stateful edge cases (from MVTS V1DO)
 ;
 ; Hand-curated DO scenarios that need cross-line state. Auto-mining
 ; couldn't capture these.
 ;
 D START^TEST("compliance/control/DOMVTS")
 ;
 ; --- DO with computed-offset entry ---
 D RUN^TEST("DO LBL+N where N is computed","third","$$T1^DOMVTS()")
 ;
 ; --- Nested DO with implicit args ---
 D RUN^TEST("DO chain through arg-passing",10,"$$T2^DOMVTS()")
 ;
 ; --- DO with postcondition that depends on prior DO's side effect ---
 D RUN^TEST("DO:cond where cond was set by prior DO","yes","$$T3^DOMVTS()")
 ;
 ; --- DO of same label twice — second invocation sees first's effects ---
 D RUN^TEST("DO same label twice cumulative",2,"$$T4^DOMVTS()")
 ;
 ; --- DO+QUIT-with-value through chain ---
 D RUN^TEST("Q expr propagates through DO chain","leaf","$$T5^DOMVTS()")
 ;
 ; --- DO with by-ref arg modifies caller's tree ---
 D RUN^TEST("DO arg-by-ref builds caller's array",6,"$$T6^DOMVTS()") ; sum 1+2+3
 ;
 ; --- Argumentless DO with multiple dotted blocks ---
 D RUN^TEST("argless-DO multi-line block",15,"$$T7^DOMVTS()") ; sum 1..5
 ;
 ; --- Recursion via DO with depth tracking ---
 D RUN^TEST("DO recursion 5 deep accumulates",15,"$$T8^DOMVTS()") ; 5+4+3+2+1
 ;
 D END^TEST("compliance/control/DOMVTS")
 Q
 ;
T1() N r,n S n=2 D LBL+n
 Q r
LBL S r="first" Q
 S r="second" Q
 S r="third" Q
 ;
T2() N a,b,c S a=0
 D ADD1(.a),ADD2(.a),ADD3(.a),ADD4(.a)
 Q a
ADD1(x) S x=x+1 Q
ADD2(x) S x=x+2 Q
ADD3(x) S x=x+3 Q
ADD4(x) S x=x+4 Q
 ;
T3() N r S r="no"
 D SETFLAG
 ; SETFLAG sets $T (or via testflag local pattern)
 D:flag SETOK
 Q r
SETFLAG S flag=1 Q
SETOK S r="yes" Q
 ;
T4() N c S c=0
 D INC4
 D INC4
 Q c
INC4 S c=c+1 Q
 ;
T5() Q $$LEAF()
LEAF() Q "leaf"
 ;
T6() N x D BUILD(.x,3)
 N s,k S s=0,k="" F  S k=$O(x(k)) Q:k=""  S s=s+x(k)
 Q s
BUILD(arr,n) Q:n=0  S arr(n)=n D BUILD(.arr,n-1)
 Q
 ;
T7() N s,i S s=0
 F i=1:1:5 D
 . S s=s+i
 Q s
 ;
T8() N s S s=0
 D REC(5,.s)
 Q s
REC(n,acc) Q:n=0  S acc=acc+n D REC(n-1,.acc)
 Q
