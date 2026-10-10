ALIAS ; MITS - alias / pass-by-reference tests
 ;
 ; em implements pass-by-reference via the caller-side dot syntax:
 ;
 ;   D LBL(.var)         caller passes alias to var
 ;   LBL(p) ... S p=42   callee writes through alias; caller's var = 42
 ;
 ; The formal parameter on the callee side has no special syntax — the
 ; engine determines alias vs by-value from whether the caller used a
 ; leading `.`. Mutations through an alias are visible to the caller
 ; after return.
 ;
 D START^TEST("compliance/locals/ALIAS")
 ;
 ; --- Basic alias: callee mutates caller's variable ---
 D RUN^TEST("alias mutation visible","mutated","$$BASIC^ALIAS()")
 D RUN^TEST("alias preserves value if no write",42,"$$READONLY^ALIAS()")
 ;
 ; --- Without alias (pass-by-value), caller's variable is unchanged ---
 D RUN^TEST("by-value: caller unchanged","orig","$$BYVAL^ALIAS()")
 ;
 ; --- Alias on subscripted variable (subtree) ---
 D RUN^TEST("alias subtree mutation",1,"$$SUBTREE^ALIAS()")
 ;
 ; --- Multiple alias args swap ---
 D RUN^TEST("two aliases swap",1,"$$DOSWAP^ALIAS()")
 ;
 ; --- Alias propagates writes to multiple caller vars ---
 D RUN^TEST("alias multi-write",6,"$$MULTI^ALIAS()") ; 1+2+3
 ;
 ; --- Read access through alias ---
 D RUN^TEST("alias read",100,"$$READ^ALIAS()")
 ;
 D END^TEST("compliance/locals/ALIAS")
 Q
 ;
BASIC() N x S x="orig" D MUT(.x)
 Q x
MUT(p) S p="mutated"
 Q
 ;
READONLY() N x S x=42 D NOMUT(.x)
 Q x
NOMUT(p) N v S v=p  ; just read
 Q
 ;
BYVAL() N x S x="orig" D MUT2(x)  ; no leading dot
 Q x
MUT2(p) S p="mutated"
 Q
 ;
SUBTREE() N x S x("a")=0 D INCSUB(.x)
 Q x("a")
INCSUB(p) S p("a")=p("a")+1
 Q
 ;
DOSWAP() N a,b S a=1,b=2 D DSWAP(.a,.b)
 ; After: a=2, b=1
 Q b
DSWAP(p,q) N t S t=p,p=q,q=t
 Q
 ;
MULTI() N a,b,c D ASSIGN3(.a,.b,.c)
 Q a+b+c
ASSIGN3(p,q,r) S p=1,q=2,r=3
 Q
 ;
READ() N x S x=100 N r D READIT(.x,.r)
 Q r
READIT(src,out) S out=src
 Q
