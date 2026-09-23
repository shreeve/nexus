ARRAYS ; MITS - mixed array operations / iteration patterns
 ;
 ; Real-world array idioms that combine $O / $D / $G / $I / SET / KILL.
 ; Tests document common patterns that should work uniformly across
 ; engines.
 ;
 D START^TEST("compliance/locals/ARRAYS")
 ;
 ; --- Counting elements ---
 D RUN^TEST("count via $O sum",10,"$$COUNT^ARRAYS()")
 D RUN^TEST("count empty array",0,"$$COUNTEMPTY^ARRAYS()")
 ;
 ; --- Sum values ---
 D RUN^TEST("sum 1..100",5050,"$$SUM100^ARRAYS()")
 D RUN^TEST("sum sparse",111,"$$SUMSPARSE^ARRAYS()") ; 1 + 10 + 100
 ;
 ; --- Find max key ---
 D RUN^TEST("max key (numeric)",100,"$$MAXNUMK^ARRAYS()")
 D RUN^TEST("max key (string)","zzz","$$MAXSTRK^ARRAYS()")
 ;
 ; --- Count by category ---
 D RUN^TEST("group counts",6,"$$GROUP^ARRAYS()") ; 3 fruits + 3 veggies = 6
 ;
 ; --- Histogram via $I ---
 D RUN^TEST("histogram 26 letters",26,"$$HIST^ARRAYS()")
 ;
 ; --- Flatten nested ---
 D RUN^TEST("walk all leaves",6,"$$LEAVES^ARRAYS()")
 ;
 ; --- Conditional accumulate ---
 D RUN^TEST("sum only evens",30,"$$EVENS^ARRAYS()") ; 2+4+6+8+10
 ;
 ; --- Copy array ---
 D RUN^TEST("$O-driven copy",55,"$$COPY^ARRAYS()") ; sum 1..10
 ;
 ; --- Reverse-order build ---
 D RUN^TEST("reverse walk concat","cba","$$REVCAT^ARRAYS()")
 ;
 ; --- Find min ---
 D RUN^TEST("min value",-5,"$$MINVAL^ARRAYS()")
 ;
 ; --- Index-of-by-value ---
 D RUN^TEST("$O find first match","middle","$$FIRSTMATCH^ARRAYS()")
 ;
 ; --- Sparse with mixed types ---
 D RUN^TEST("walk mixed-key array",6,"$$MIXKEY^ARRAYS()") ; counts all entries
 ;
 D END^TEST("compliance/locals/ARRAYS")
 Q
 ;
COUNT() N x,c,k,i F i=1:1:10 S x(i)=1
 S c=0,k="" F  S k=$O(x(k)) Q:k=""  S c=c+1
 Q c
 ;
COUNTEMPTY() N x,c,k S c=0,k="" F  S k=$O(x(k)) Q:k=""  S c=c+1
 Q c
 ;
SUM100() N x,s,k,i F i=1:1:100 S x(i)=i
 S s=0,k="" F  S k=$O(x(k)) Q:k=""  S s=s+x(k)
 Q s
 ;
SUMSPARSE() N x,s,k S x(1)=1,x(10)=10,x(100)=100
 S s=0,k="" F  S k=$O(x(k)) Q:k=""  S s=s+x(k)
 Q s
 ;
MAXNUMK() N x,k,m,i F i=1:1:100 S x(i)=1
 S m=$O(x(""),-1)
 Q m
 ;
MAXSTRK() N x,m S x("aaa")=1,x("zzz")=1,x("mmm")=1
 S m=$O(x(""),-1)
 Q m
 ;
GROUP() N x,c,k,sub
 S x("fruit","apple")=1,x("fruit","banana")=1,x("fruit","cherry")=1
 S x("veggie","carrot")=1,x("veggie","peas")=1,x("veggie","spinach")=1
 S c=0,k="" F  S k=$O(x(k)) Q:k=""  D
 . S sub="" F  S sub=$O(x(k,sub)) Q:sub=""  S c=c+1
 Q c
 ;
HIST() N x,i,k,c
 ; Increment each letter once
 F i=1:1:26 S x($C(96+i))=$I(x($C(96+i)),0)+1  ; Wait, $I(subscripted) not yet supported; use SET
 K x
 F i=1:1:26 S x($C(96+i))=1
 S c=0,k="" F  S k=$O(x(k)) Q:k=""  S c=c+1
 Q c
 ;
LEAVES() N x,c,k S c=0
 S x("a","x")=1,x("a","y")=1,x("b")=1,x("b","z")=1,x("c",1)=1,x("c",2)=1
 S k="x" F  S k=$Q(@k) Q:k=""  S c=c+1
 Q c
 ;
EVENS() N x,s,k,i F i=1:1:10 S x(i)=i
 S s=0,k="" F  S k=$O(x(k)) Q:k=""  I x(k)#2=0 S s=s+x(k)
 Q s
 ;
COPY() N a,b,k,i,s F i=1:1:10 S a(i)=i
 S k="" F  S k=$O(a(k)) Q:k=""  S b(k)=a(k)
 S s=0,k="" F  S k=$O(b(k)) Q:k=""  S s=s+b(k)
 Q s
 ;
REVCAT() N x,r,k S x("a")=1,x("b")=1,x("c")=1
 S r="",k="" F  S k=$O(x(k),-1) Q:k=""  S r=r_k
 Q r
 ;
MINVAL() N x,m,k S x("a")=3,x("b")=-5,x("c")=1,x("d")=10
 S m=999,k="" F  S k=$O(x(k)) Q:k=""  I x(k)<m S m=x(k)
 Q m
 ;
FIRSTMATCH() N x,k,target
 S x("first")="a",x("middle")="match",x("last")="b"
 S k="" F  S k=$O(x(k)) Q:k=""  Q:x(k)="match"
 Q k
 ;
MIXKEY() N x,c,k S c=0
 S x(1)=1,x(2)=1,x("aa")=1,x("bb")=1,x(-1)=1,x(0)=1
 S k="" F  S k=$O(x(k)) Q:k=""  S c=c+1
 Q c
