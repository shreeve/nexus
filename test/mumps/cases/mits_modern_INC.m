INC ; MITS - $INCREMENT (atomic counter increment)
 ;
 ; $INCREMENT(@ref[, delta])
 ;   - atomically reads, adds delta (default 1), writes back
 ;   - returns the NEW value
 ;   - undefined ref is treated as 0
 ;
 ; Both unsubscripted ($I(x)) and subscripted ($I(x("k"))) forms are
 ; supported. Indirected refs ($I(@var)) are deferred.
 ;
 D START^TEST("compliance/modern/INC")
 ;
 ; --- Basic increment (no delta = +1) ---
 D RUN^TEST("$I undefined creates with 1",1,"$$BASIC^INC()")
 D RUN^TEST("$I existing adds 1",2,"$$EXIST^INC()")
 D RUN^TEST("$I returns new value",10,"$$RETVAL^INC()")
 D RUN^TEST("$I mutates in place",6,"$$MUT^INC()")
 ;
 ; --- With delta ---
 D RUN^TEST("$I delta=5",5,"$$D5^INC()")
 D RUN^TEST("$I negative delta",-3,"$$DNEG^INC()")
 D RUN^TEST("$I delta=0 returns current",7,"$$D0^INC()")
 D RUN^TEST("$I decimal delta",1.5,"$$DDEC^INC()")
 D RUN^TEST("$I large positive delta",1000,"$$DLG^INC()")
 ;
 ; --- Loop accumulation ---
 D RUN^TEST("$I in 100-iter loop",100,"$$LOOP^INC()")
 D RUN^TEST("$I sum-of-1-to-10",55,"$$MIXLOOP^INC()")
 D RUN^TEST("$I as condition (truthy after first)",1,"$$ASCOND^INC()")
 ;
 ; --- Multiple counters ---
 D RUN^TEST("multiple counters independent",3,"$$MULT^INC()")
 ;
 ; --- Subscripted form ---
 D RUN^TEST("$I subscripted local",1,"$$SUB1^INC()")
 D RUN^TEST("$I subscripted with delta",5,"$$SUB5^INC()")
 D RUN^TEST("$I deep subscript creates and increments",1,"$$DEEPSUB^INC()")
 D RUN^TEST("$I deep with delta",10,"$$DEEPDEL^INC()")
 D RUN^TEST("$I subscripted in loop accumulates",55,"$$SUBLOOP^INC()")
 D RUN^TEST("$I global subscripted",1,"$$GSUB^INC()")
 D RUN^TEST("$I sibling counters independent","2,3","$$SIBLINGS^INC()")
 ;
 D END^TEST("compliance/modern/INC")
 Q
 ;
BASIC() N x
 Q $I(x)
 ;
EXIST() N x S x=1
 Q $I(x)
 ;
RETVAL() N x S x=9
 N r S r=$I(x)
 Q r
 ;
MUT() N x S x=5
 N r S r=$I(x)
 ; After $I, x is mutated to 6 in place; we read x AFTER.
 Q x
 ;
D5() N x
 Q $I(x,5)
 ;
DNEG() N x
 Q $I(x,-3)
 ;
D0() N x S x=7
 Q $I(x,0)
 ;
DDEC() N x S x=1
 Q $I(x,0.5)
 ;
DLG() N x
 Q $I(x,1000)
 ;
LOOP() N x,i,r
 F i=1:1:100 S r=$I(x)
 Q x
 ;
MIXLOOP() N x,i,r
 F i=1:1:10 S r=$I(x,i)
 Q x
 ;
ASCOND() N x,result S result=0
 ; First $I returns 1 (truthy), entering the THEN branch.
 I $I(x) S result=1
 Q result
 ;
MULT() N x,y
 ; Independent counters
 N r S r=$I(x)+$I(x)+$I(y)+$I(y)+$I(x)
 ; x: 1, 2, 3 → x ends at 3
 Q x
 ;
SUB1() N x
 Q $I(x("k"))
 ;
SUB5() N x
 Q $I(x("k"),5)
 ;
DEEPSUB() N x,r
 Q $I(x("a","b","c"))
 ;
DEEPDEL() N x,i,r
 F i=1:1:10 S r=$I(x("counter"))
 Q x("counter")
 ;
SUBLOOP() N x,i,r
 F i=1:1:10 S r=$I(x("k"),i)
 Q x("k")
 ;
GSUB() K ^MITS
 N r S r=$I(^MITS("counter"))
 N v S v=^MITS("counter")
 K ^MITS
 Q v
 ;
SIBLINGS() N x
 N r1 S r1=$I(x("a"))     ; 1
 N r2 S r2=$I(x("b"))     ; 1
 N r3 S r3=$I(x("a"))     ; 2
 N r4 S r4=$I(x("b"),2)   ; 3
 Q x("a")_","_x("b")
