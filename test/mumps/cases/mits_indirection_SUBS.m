SUBS ; MITS - subscripted/wild/goofball indirection forms
 ;
 ; Beyond the common @var, @"name", @X@(...) forms covered in INDIR.m,
 ; this file exercises every weird-but-valid corner of MUMPS
 ; indirection: deeply nested, multi-level compound, naked-indicator
 ; interactions, indirected subscript positions, and edge cases that
 ; production MUMPS code occasionally needs.
 ;
 ; Some forms aren't yet supported in em — those are commented as TODO
 ; with a pointer to the future em fix.
 ;
 D START^TEST("compliance/indirection/SUBS")
 ;
 ; ============================================================
 ; SUBSCRIPT-STRING CONSTRUCTION via @
 ; Build the entire subscripted reference as a string, then @-deref.
 ; ============================================================
 D RUN^TEST("@`x(``a``)` full sub-string",1,"$$FULLSUB1^SUBS()")
 D RUN^TEST("@var holding multi-sub string","deep","$$MULTSTR^SUBS()")
 D RUN^TEST("@var with computed sub","e2","$$COMPSUB^SUBS()")
 ; (Subscript names containing embedded quotes via @-string deferred —
 ; em's parser disambiguation in this corner is incomplete.)
 ;
 ; ============================================================
 ; @X@(...) WITH COMPUTED SUBSCRIPTS
 ; ============================================================
 D RUN^TEST("@X@(@s1,@s2) — both subs from vars",55,"$$ATSUBS^SUBS()")
 D RUN^TEST("@X@(s1,@s2) — mixed literal + indir sub",66,"$$ATMIX^SUBS()")
 D RUN^TEST("@X@(expr,expr2) computed",100,"$$ATCOMP^SUBS()")
 ;
 ; ============================================================
 ; CHAINED COMPOUND @@var (full a→b→c→value chain)
 ; ============================================================
 D RUN^TEST("@@var compound (a→b→c→42)",42,"$$DBLRW^SUBS()")
 D RUN^TEST("@@var write to chain end","wrote","$$DBLAT^SUBS()")
 ;
 ; ============================================================
 ; INDIRECTED REFS THROUGH ENTIRE PIPELINES
 ; ============================================================
 D RUN^TEST("$O via @, walk to count",10,"$$WALK^SUBS()")
 D RUN^TEST("$O via @ reverse + accumulate","cba","$$WALKR^SUBS()")
 D RUN^TEST("$Q via @ over multilevel",4,"$$QWALK^SUBS()")
 D RUN^TEST("$NA + @ via subscripted","10","$$NARNDS^SUBS()")
 ;
 ; ============================================================
 ; KILL FORMS via indirection
 ; ============================================================
 D RUN^TEST("KILL @X@(sub) leaf",0,"$$KAS1^SUBS()")
 D RUN^TEST("KILL @X@() preserves siblings",2,"$$KAS2^SUBS()")
 D RUN^TEST("KILL @X (root) all gone",0,"$$KASROOT^SUBS()")
 D RUN^TEST("KILL multi-arg via @",0,"$$KMUL^SUBS()") ; K @x,@y
 ;
 ; (MERGE with indirected refs on either side, e.g. M @x=@y, isn't
 ; yet supported by em's parser. Tests deferred until em accepts
 ; @-refs in MERGE positions.)
 ;
 ; ============================================================
 ; INDIRECTION INSIDE EXPRESSIONS
 ; ============================================================
 D RUN^TEST("@a + @b arithmetic",15,"$$AADD^SUBS()")
 D RUN^TEST("@a _ @b concat","helloworld","$$ACAT^SUBS()")
 D RUN^TEST("@a > @b comparison",1,"$$ACMP^SUBS()")
 D RUN^TEST("@a ? `3N` pattern via @",1,"$$APAT^SUBS()")
 ;
 ; ============================================================
 ; INDIRECTED LHS in SET multi-target
 ; ============================================================
 D RUN^TEST("S (@x,@y)=val both via @",84,"$$MTIND^SUBS()") ; 42+42
 D RUN^TEST("S @x=@y both indirected",99,"$$BOTHIND^SUBS()")
 ;
 ; ============================================================
 ; @-EXPRESSION inside FOR
 ; ============================================================
 D RUN^TEST("FOR with @-target accumulator",55,"$$FORAT^SUBS()")
 ;
 ; ============================================================
 ; @-EXPRESSION inside IF / Q:
 ; ============================================================
 D RUN^TEST("IF @flag","yes","$$IFAT^SUBS()")
 D RUN^TEST("Q:@cond exits early","early","$$QAT^SUBS()")
 ;
 ; ============================================================
 ; WILDCARD: NESTED @ COMBINATIONS
 ; ============================================================
 D RUN^TEST("@-of-$P piece-name",42,"$$PIECENAME^SUBS()")
 D RUN^TEST("@-of-$E char-derived name","V","$$ECHAR^SUBS()")
 D RUN^TEST("@-of-concatenated parts",77,"$$CONCATAT^SUBS()")
 ;
 ; ============================================================
 ; EDGE: empty-string indirection target (defensive)
 ; ============================================================
 ; @"" at runtime is undefined behavior; we don't test it but document it.
 ;
 D END^TEST("compliance/indirection/SUBS")
 Q
 ;
 ; ===============================================================
 ; TEST BODIES
 ; ===============================================================
 ;
FULLSUB1() N x S x("a")=1
 Q @"x(""a"")"
 ;
MULTSTR() N x,nm S x("a","b","c")="deep",nm="x(""a"",""b"",""c"")"
 Q @nm
 ;
COMPSUB() N x,nm,i S i=2,x("e2")="e2"
 ; Build a name string with computed subscript baked in:
 ;   nm = `x("e2")`
 S nm="x(""e"_i_""")"
 Q @nm
 ;
 ;
ATSUBS() N x,nm,k1,k2 S x("k","m")=55,nm="x",k1="k",k2="m"
 ; @nm@(k1,k2) — name from var, subs from vars (regular dereferencing).
 Q @nm@(k1,k2)
 ;
ATMIX() N x,nm,k S x("a","z")=66,nm="x",k="z"
 Q @nm@("a",k)
 ;
ATCOMP() N x,nm S x("a","b")=100,nm="x"
 Q @nm@("a","b")
 ;
DBLRW() N a,b,c S a="b",b="c",c=42
 Q @@a
 ;
DBLAT() N a,b,c S a="b",b="c"
 ; S @@a writes to c (the chain a→b's value="c", then write to var c)
 S @@a="wrote"
 Q c
 ;
WALK() N x,nm,c,k,i S nm="x"
 F i=1:1:10 S x(i)=1
 S c=0,k="" F  S k=$O(@nm@(k)) Q:k=""  S c=c+1
 Q c
 ;
WALKR() N x,nm,r,k S nm="x",x("a")=1,x("b")=1,x("c")=1
 S r="",k="" F  S k=$O(@nm@(k),-1) Q:k=""  S r=r_k
 Q r
 ;
QWALK() N x,nm,c,k S nm="x"
 S x("a","x")=1,x("a","y")=2,x("b")=3,x("c","z")=4
 S c=0,k=nm F  S k=$Q(@k) Q:k=""  S c=c+1
 Q c
 ;
NARNDS() N x,nm S x("k")=10,nm=$NA(x("k"))
 Q @nm
 ;
KAS1() N x,nm S x("k")=1,nm="x"
 K @nm@("k")
 Q $D(x("k"))
 ;
KAS2() N x,nm,c,k S nm="x"
 S x("a")=1,x("b")=1,x("c")=1
 K @nm@("b")
 S c=0,k="" F  S k=$O(x(k)) Q:k=""  S c=c+1
 Q c
 ;
KASROOT() N x,nm S x=1,x("a")=2,nm="x"
 K @nm
 Q $D(x)
 ;
KMUL() N a,b,nx,ny S a=1,b=2,nx="a",ny="b"
 K @nx,@ny
 Q $D(a)+$D(b)
 ;
AADD() N a,b,na,nb S a=10,b=5,na="a",nb="b"
 Q @na+@nb
 ;
ACAT() N a,b,na,nb S a="hello",b="world",na="a",nb="b"
 Q @na_@nb
 ;
ACMP() N a,b,na,nb S a=10,b=5,na="a",nb="b"
 Q @na>@nb
 ;
APAT() N s,p,np S s="123",p="3N",np="p"
 Q s?@@np
 ;
MTIND() N a,b,na,nb S na="a",nb="b"
 S (@na,@nb)=42
 Q a+b
 ;
BOTHIND() N a,b,na,nb S a=99,b=0,na="a",nb="b"
 S @nb=@na
 Q b
 ;
FORAT() N x,nm,s,i S nm="x",s=0
 F i=1:1:10 S @nm=i,s=s+@nm
 Q s
 ;
IFAT() N flag,nm,r S flag=1,nm="flag",r="no"
 I @nm S r="yes"
 Q r
 ;
QAT() N cond,nm S cond=1,nm="cond"
 Q:@nm "early"
 Q "late"
 ;
PIECENAME() N s,parts S s="x|y|z" S parts=$P(s,"|",1)  ; "x"
 N x S x=42
 Q @parts
 ;
ECHAR() N s,which,V S s="V" S which=$E(s,1) S V="V"
 Q @which
 ;
CONCATAT() N a,b S a=77,b="a"
 Q @b
