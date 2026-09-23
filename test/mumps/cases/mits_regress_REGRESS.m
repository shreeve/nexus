REGRESS ; MITS - regression tests for em-specific bugs we've fixed
 ;
 ; Each test here captures a bug that was fixed in em's history. The
 ; test is the bug reproducer; passing means the fix is still in place.
 ;
 ; Naming: <commit-prefix>_<short-desc> — points back to the fix commit.
 ;
 D START^TEST("compliance/regress/REGRESS")
 ;
 ; --- ac8b68a: indirection cache use-after-free ---
 ; The xecuteCache freed source buffers while compiled routines still
 ; referenced them via slices in EntryRef and Val.ref literals. Fixed
 ; by transferring source ownership to the Routine via sourceBacking.
 D RUN^TEST("ac8b68a indir UAF: 50x repeated XECUTE",50,"$$INDIRUAF^REGRESS()")
 ;
 ; --- 2b49ec5: $INCREMENT compiler wire-up ---
 ; \$I was parsed and dispatcher-wired but had no compiler emission;
 ; .incr was unreachable bytecode. Result: \$I always returned empty
 ; and never mutated. Now emits Inst.ref(.incr, ...) for unsubscripted.
 D RUN^TEST("2b49ec5 \$I returns new value",1,"$$INCRET^REGRESS()")
 D RUN^TEST("2b49ec5 \$I mutates source",1,"$$INCMUT^REGRESS()")
 ;
 ; --- 2b49ec5: xecuteCache active-routine eviction ---
 ; Outer X compiles + caches its source; inner extrinsic does many
 ; unique X's that fill the FIFO and would evict the outer's still-
 ; live entry. Now isRoutineActive() guards against eviction of any
 ; routine on the active call stack.
 D RUN^TEST("2b49ec5 cache holds active routine","ok","$$CACHEHOLD^REGRESS()")
 D RUN^TEST("2b49ec5 100K nested unique X","ok","$$NESTSTRESS^REGRESS()")
 ;
 ; --- 256f75f: Val arithmetic 18-digit boundary ---
 ; Integer fast paths could produce mantissas > 1e18, violating the
 ; canonical-form invariant. canonI64() guard added; out-of-range
 ; results fall back to the decimal pipeline.
 D RUN^TEST("256f75f i64 boundary add","1000000000000000000","999999999999999999+1")
 D RUN^TEST("256f75f i64 boundary mul",100000000000000000,"10000000000000000*10")
 ;
 ; --- 4f23114: integer literal compileAtom round-trip ---
 ; compileAtom used to round-trip integer literals through string,
 ; forcing ensureNum to re-parse on every iteration. Now stores them
 ; directly as Val.fromInt(n).
 D RUN^TEST("4f23114 tight literal loop",1000000,"$$LITLOOP^REGRESS()")
 ;
 ; --- 256f75f: doForStep1 fast-path canonical mantissa ---
 ; FOR i=1:1:N hot path missed canonical-mantissa cases like
 ; 100000 (canonicalized to man=1, exp=5). Widened the guard to
 ; cur.exp == 0 and endVal.exp >= 0 with overflow-safe addition.
 D RUN^TEST("256f75f FOR 100K iterations",100000,"$$FORHOT^REGRESS()")
 ;
 D END^TEST("compliance/regress/REGRESS")
 Q
 ;
INDIRUAF() N i,result S result=0
 N c S c="S y=42"
 ; Run X repeatedly; the cache gets reused, then evicted.
 F i=1:1:50 X c S result=result+1
 Q result
 ;
INCRET() N x
 Q $I(x)
 ;
INCMUT() N x S r=$I(x)
 Q x
 ;
CACHEHOLD() N r,A,C
 ; Outer X "S A=$$INNER1^REGRESS()" must survive 10K inner unique X's.
 S C="$$INNER1^REGRESS()"
 X "S A="_C
 Q A
 ;
INNER1() N i,x
 F i=1:1:10000 X "S x="_i
 Q "ok"
 ;
NESTSTRESS() N r,A,C
 ; Same pattern, with 100K to stress harder.
 S C="$$INNER2^REGRESS()"
 X "S A="_C
 Q A
 ;
INNER2() N i,x
 F i=1:1:100000 X "S x="_i
 Q "ok"
 ;
LITLOOP() N i,s S s=0
 F i=1:1:1000000 S s=s+1
 Q s
 ;
FORHOT() N i,c S c=0
 F i=1:1:100000 S c=c+1
 Q c
