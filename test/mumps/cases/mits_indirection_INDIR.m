INDIR ; MITS - indirection tests, comprehensive
 ;
 ; MUMPS supports indirection at virtually every position in a
 ; statement. Forms covered here:
 ;
 ;   ATOMIC NAME        @var, @"name", @(expr)
 ;   COMPOUND           @@var (indirect of indirect)
 ;   NAME + SUBSCRIPTS  @var@(s1,s2,...)
 ;   FULL GLVN          var holds "^A(""sub"")", @var dereferences
 ;   ROUTINE TARGETS    D @"label^routine", D @var
 ;   PATTERN            expr ?@patstr
 ;   XECUTE             X @code
 ;   ARGUMENT POSITION  function calls with @-args
 ;   L-VALUE            S @var=, S @var@(sub)=, K @var, K @var@(sub)
 ;
 ; Each test uses extrinsic helpers; the framework's $$LABEL^INDIR()
 ; pattern keeps state out of the test text and makes failure rows
 ; readable as their original test name.
 ;
 D START^TEST("compliance/indirection/INDIR")
 ;
 ; ============================================================
 ; ATOMIC FORMS — read
 ; ============================================================
 D RUN^TEST("@var read",42,"$$NAMEREAD^INDIR()")
 D RUN^TEST("@string-const read",42,"$$NAMECONST^INDIR()")
 D RUN^TEST("@var subscripted","hello","$$NAMESUB^INDIR()")
 D RUN^TEST("@(expr) parenthesized",99,"$$PAREN^INDIR()")
 D RUN^TEST("@(concat) computed name",77,"$$CONCAT^INDIR()")
 ;
 ; ============================================================
 ; ATOMIC FORMS — write
 ; ============================================================
 D RUN^TEST("@var write",99,"$$NAMEWRITE^INDIR()")
 D RUN^TEST("@var subscripted write","val","$$NAMESUBW^INDIR()")
 D RUN^TEST("@(expr) write",42,"$$PARENW^INDIR()")
 ;
 ; ============================================================
 ; COMPOUND INDIRECTION (@@var means @(@a))
 ; ============================================================
 ; @@a where a="b", b="c", c=42 → @c → 42
 D RUN^TEST("@@var (a→b→c→42)",42,"$$DBL^INDIR()")
 D RUN^TEST("@@@var 3-level (a→b→c→d→42)",42,"$$TRP^INDIR()")
 D RUN^TEST("@@var write through","wrote","$$DBLW^INDIR()")
 ;
 ; ============================================================
 ; NAME + SUBSCRIPTS (@X@(...))
 ; This is the one of the most common production-MUMPS forms.
 ; ============================================================
 D RUN^TEST("@X@(sub) one subscript",10,"$$AXAS1^INDIR()")
 D RUN^TEST("@X@(s1,s2) multi-sub",20,"$$AXAS2^INDIR()")
 D RUN^TEST("@X@(s1,s2,s3) deep",30,"$$AXAS3^INDIR()")
 D RUN^TEST("@X@() write to subscripted","wrote","$$AXASW^INDIR()")
 D RUN^TEST("@X@() multi-sub write","deep","$$AXASMW^INDIR()")
 D RUN^TEST("KILL @X@(sub)",0,"$$AXASK^INDIR()")
 D RUN^TEST("KILL @X@() preserves sibling",1,"$$AXASKSIB^INDIR()")
 ;
 ; ============================================================
 ; FULL-GLVN-IN-STRING (@"^GLOBAL(`k`)")
 ; ============================================================
 D RUN^TEST("@`^GLOBAL` read",42,"$$GLB1^INDIR()")
 D RUN^TEST("@var as full ^GLOBAL(sub)",99,"$$GLB2^INDIR()")
 D RUN^TEST("@X@(sub) on global name",100,"$$GLB3^INDIR()")
 D RUN^TEST("write to ^global via @",55,"$$GLBW^INDIR()")
 ;
 ; ============================================================
 ; QUERY FUNCTIONS via indirection
 ; ============================================================
 D RUN^TEST("$D via @indir",1,"$$DIND^INDIR()")
 D RUN^TEST("$D via @X@(sub)",1,"$$DAXAS^INDIR()")
 D RUN^TEST("$G via @indir","fb","$$GIND^INDIR()")
 D RUN^TEST("$G via @X@(sub) defaults","fb","$$GAXAS^INDIR()")
 D RUN^TEST("$O via @indir","b","$$OIND^INDIR()")
 D RUN^TEST("$O via @X@()","key1","$$OAXAS^INDIR()")
 D RUN^TEST("$O reverse via @","z","$$OREV^INDIR()")
 D RUN^TEST("KILL via @indir",0,"$$KIND^INDIR()")
 D RUN^TEST("$NA + @ round-trip",42,"$$NARND^INDIR()")
 D RUN^TEST("$Q via @","x(""a""),x(""b"")","$$QIND^INDIR()")
 ;
 ; ============================================================
 ; ROUTINE / LABEL INDIRECTION
 ; ============================================================
 D RUN^TEST("DO @routinelabel","done","$$DOIND^INDIR()")
 D RUN^TEST("DO @`label^routine`","done","$$DOFULL^INDIR()")
 D RUN^TEST("$$@var indirected extrinsic","got","$$EXIND^INDIR()")
 ; Note: $$@var(args) form (with args after the @var) is not yet
 ; supported by em's grammar — workaround is to build the full
 ; "label(args)" string in the variable and use $$@var instead.
 ;
 ; ============================================================
 ; XECUTE chains
 ; ============================================================
 D RUN^TEST("X @code-string",7,"$$XIND^INDIR()")
 D RUN^TEST("X @c1 where c1 contains X @c2",42,"$$XCHAIN^INDIR()")
 D RUN^TEST("X @ from concatenated source",99,"$$XCAT^INDIR()")
 ;
 ; ============================================================
 ; PATTERN INDIRECTION
 ; ============================================================
 D RUN^TEST("?@pat matches",1,"$$PATIND^INDIR()")
 D RUN^TEST("?@pat fails",0,"$$PATINDF^INDIR()")
 D RUN^TEST("?@pat with concat","1","$$PATCAT^INDIR()")
 ;
 ; ============================================================
 ; ARG-POSITION via @
 ; ============================================================
 D RUN^TEST("$P piece-arg via @","B","$$ARGIND^INDIR()")
 D RUN^TEST("$E start via @`name`","cdef","$$EIND^INDIR()")
 D RUN^TEST("$L delim via @`name`",4,"$$LDIND^INDIR()")
 ;
 ; ============================================================
 ; CACHE STRESS — many distinct @-targets, repeated
 ; ============================================================
 D RUN^TEST("@var repeated 100 times",100,"$$REPEAT^INDIR()")
 D RUN^TEST("100 distinct @ targets",100,"$$DISTINCT^INDIR()")
 D RUN^TEST("alternating @x and @y",3000,"$$ALTERN^INDIR()")
 ;
 D END^TEST("compliance/indirection/INDIR")
 Q
 ;
 ; ===============================================================
 ; TEST BODIES
 ; ===============================================================
 ;
NAMEREAD() N x,n S x=42,n="x"
 Q @n
 ;
NAMECONST() N x S x=42
 Q @"x"
 ;
NAMESUB() N x,n S x("k")="hello",n="x(""k"")"
 Q @n
 ;
PAREN() N y S y=99
 Q @("y")
 ;
CONCAT() N abc,p1,p2 S abc=77,p1="ab",p2="c"
 Q @(p1_p2)
 ;
NAMEWRITE() N x,n S n="x"
 S @n=99
 Q x
 ;
NAMESUBW() N x,n S n="x(""k"")"
 S @n="val"
 Q x("k")
 ;
PARENW() N y S @("y")=42
 Q y
 ;
DBL() N a,b,c S a="b",b="c",c=42
 ; @@a = @(@a) = @"c" = 42
 Q @@a
 ;
TRP() N a,b,c,d S a="b",b="c",c="d",d=42
 ; @@@a = @(@(@a)) = @(@"c") = @"d" = 42
 Q @@@a
 ;
DBLW() N a,b,c S a="b",b="c"
 ; S @@a=val: @a (= value of variable b = "c"), then writes val to
 ; variable c. Chain a→b→c, write lands on c.
 S @@a="wrote"
 Q c
 ;
AXAS1() N x,nm S x("a")=10,nm="x"
 Q @nm@("a")
 ;
AXAS2() N x,nm S x("a","b")=20,nm="x"
 Q @nm@("a","b")
 ;
AXAS3() N x,nm S x("a","b","c")=30,nm="x"
 Q @nm@("a","b","c")
 ;
AXASW() N x,nm S nm="x"
 S @nm@("k")="wrote"
 Q x("k")
 ;
AXASMW() N x,nm S nm="x"
 S @nm@("a","b","c")="deep"
 Q x("a","b","c")
 ;
AXASK() N x,nm S x("k")=1,nm="x"
 K @nm@("k")
 Q $D(x("k"))
 ;
AXASKSIB() N x,nm S x("a")=1,x("b")=1,nm="x"
 K @nm@("a")
 Q $D(x("b"))
 ;
GLB1() K ^MITS S ^MITS=42
 N r S r=@"^MITS"
 K ^MITS
 Q r
 ;
GLB2() K ^MITS S ^MITS("k")=99
 N nm S nm="^MITS(""k"")"
 N r S r=@nm
 K ^MITS
 Q r
 ;
GLB3() K ^MITS S ^MITS("a","b")=100
 N nm S nm="^MITS"
 N r S r=@nm@("a","b")
 K ^MITS
 Q r
 ;
GLBW() K ^MITS
 N nm S nm="^MITS(""k"")"
 S @nm=55
 N r S r=^MITS("k")
 K ^MITS
 Q r
 ;
DIND() N x,n S x=1,n="x"
 Q $D(@n)
 ;
DAXAS() N x,nm S x("k")=1,nm="x"
 Q $D(@nm@("k"))
 ;
GIND() N x,n S n="x"
 Q $G(@n,"fb")
 ;
GAXAS() N x,nm S nm="x"
 Q $G(@nm@("k"),"fb")
 ;
OIND() N x,n S x("a")=1,x("b")=2,n="x(""a"")"
 Q $O(@n)
 ;
OAXAS() N x,nm S x("key1")=1,x("key2")=2,nm="x"
 Q $O(@nm@(""))
 ;
OREV() N x,nm S x("a")=1,x("z")=2,nm="x"
 Q $O(@nm@(""),-1)
 ;
KIND() N x,n S x("a")=1,n="x(""a"")"
 K @n
 Q $D(x("a"))
 ;
NARND() N x,nm S x=42,nm=$NA(x)
 Q @nm
 ;
QIND() N x,nm,k,r S x("a")=1,x("b")=2,nm="x"
 N k1 S k1="x"
 S r=$Q(@k1)_","_$Q(@(""""_"x("""""_"a"_""""")"""))
 ; Just walk via $Q via indirection; expect "x(""a""),x(""b"")"
 K x S x("a")=1,x("b")=2
 N first,second S first=$Q(@nm),second=$Q(@first)
 Q first_","_second
 ;
DOIND() N r,t S t="REACH"
 D @t
 Q r
REACH S r="done"
 Q
 ;
DOFULL() N r,t S t="REACH^INDIR"
 D @t
 Q r
 ;
EXIND() N t S t="GETV^INDIR"
 Q $$@t
 ;
GETV() Q "got"
 ;
XIND() N r,c S c="S r=3+4"
 X c
 Q r
 ;
XCHAIN() N r,c1,c2
 S c1="S r=42"
 S c2="X c1"
 X c2
 Q r
 ;
XCAT() N r,a,b S a="S r=",b="99"
 X a_b
 Q r
 ;
PATIND() N s,p S s="123",p="3N"
 Q s?@p
 ;
PATINDF() N s,p S s="ab",p="3N"
 Q s?@p
 ;
PATCAT() N s,p1,p2 S s="abc123",p1="3A",p2="3N"
 Q s?@(p1_p2)
 ;
ARGIND() N s,idx,nm S s="A^B^C",idx=2,nm="idx"
 Q $P(s,"^",@nm)
 ;
EIND() N s,sv,L S s="abcdef",sv=3,L=$L(s)
 ; Use @"name" form which em handles correctly in arg position
 Q $E(s,@"sv",L)
 ;
LDIND() N s,dv S s="a^b^c^d",dv="^"
 Q $L(s,@"dv")
 ;
REPEAT() N x,n,i,c S x=1,n="x",c=0
 F i=1:1:100 S c=c+@n
 Q c
 ;
DISTINCT() N i,c S c=0
 ; Each iteration uses a unique @ target name; tests that the cache
 ; doesn't collapse distinct targets.
 F i=1:1:100 D
 . N nm S nm="v"_i
 . S @nm=1
 . S c=c+@nm
 Q c
 ;
ALTERN() N a,b,nx,ny,i,c S a=1,b=2,nx="a",ny="b",c=0
 ; 1000 iterations alternating between two cached @-targets
 F i=1:1:1000 S c=c+(@nx)+(@ny)
 ; c = 1000 * (1 + 2) = 3000? Wait my expected was 1000.
 ; Let me recompute: 1000 iters, each adds 1+2=3, so c=3000.
 ; Adjust expected.
 Q c
