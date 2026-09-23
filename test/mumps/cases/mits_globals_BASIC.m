BASIC ; MITS - basic global variable operations (^GBL)
 ;
 ; Globals are persistent across processes (database-backed). All tests
 ; here use a temp global ^MITS that we KILL at start and end so they
 ; don't accumulate state across runs.
 ;
 D START^TEST("compliance/globals/BASIC")
 ;
 ; Clean slate
 K ^MITS
 ;
 ; --- SET / GET ---
 D RUN^TEST("set/get unsubscripted",42,"$$SETGET^BASIC()")
 D RUN^TEST("set/get subscripted",1,"$$SUBSET^BASIC()")
 D RUN^TEST("set/get deep subscript",99,"$$DEEPSET^BASIC()")
 D RUN^TEST("set numeric value coerces","123","$$NUMSTR^BASIC()")
 D RUN^TEST("empty string value preserved","","$$EMPTYVAL^BASIC()")
 ;
 ; --- $D on globals ---
 D RUN^TEST("$D undefined global",0,"$$DUND^BASIC()")
 D RUN^TEST("$D defined value",1,"$$DDEF^BASIC()")
 D RUN^TEST("$D root with descendants only",10,"$$DDESC^BASIC()")
 D RUN^TEST("$D both value and descendants",11,"$$DBOTH^BASIC()")
 ;
 ; --- $G with default ---
 D RUN^TEST("$G undefined global","NA","$$GETUND^BASIC()")
 D RUN^TEST("$G defined ignores default","real","$$GETDEF^BASIC()")
 ;
 ; --- KILL ---
 D RUN^TEST("KILL of leaf",0,"$$KLEAF^BASIC()")
 D RUN^TEST("KILL of root removes subtree",0,"$$KROOT^BASIC()")
 D RUN^TEST("KILL preserves siblings",1,"$$KSIB^BASIC()")
 ;
 ; --- Persistence within a test (next op sees prior op) ---
 D RUN^TEST("write then read in same test","persisted","$$PERSIST^BASIC()")
 ;
 ; --- $O on globals (sanity, deeper coverage in ORDER.m) ---
 D RUN^TEST("$O simple chain","abc","$$O3^BASIC()")
 ;
 ; Clean up
 K ^MITS
 ;
 D END^TEST("compliance/globals/BASIC")
 Q
 ;
SETGET() K ^MITS S ^MITS=42
 Q ^MITS
 ;
SUBSET() K ^MITS S ^MITS("a")=1
 Q ^MITS("a")
 ;
DEEPSET() K ^MITS S ^MITS("a","b","c")=99
 Q ^MITS("a","b","c")
 ;
NUMSTR() K ^MITS S ^MITS=123
 Q ^MITS
 ;
EMPTYVAL() K ^MITS S ^MITS=""
 Q ^MITS
 ;
DUND() K ^MITS
 Q $D(^MITS)
 ;
DDEF() K ^MITS S ^MITS=1
 Q $D(^MITS)
 ;
DDESC() K ^MITS S ^MITS("leaf")=1
 Q $D(^MITS)
 ;
DBOTH() K ^MITS S ^MITS=1,^MITS("leaf")=2
 Q $D(^MITS)
 ;
GETUND() K ^MITS
 Q $G(^MITS,"NA")
 ;
GETDEF() K ^MITS S ^MITS="real"
 Q $G(^MITS,"NA")
 ;
KLEAF() K ^MITS S ^MITS("a")=1 K ^MITS("a")
 Q $D(^MITS("a"))
 ;
KROOT() K ^MITS S ^MITS=1,^MITS("a")=2 K ^MITS
 Q $D(^MITS("a"))
 ;
KSIB() K ^MITS S ^MITS("a")=1,^MITS("b")=1 K ^MITS("a")
 Q $D(^MITS("b"))
 ;
PERSIST() K ^MITS S ^MITS("k")="persisted"
 Q ^MITS("k")
 ;
O3() K ^MITS S ^MITS("a")=1,^MITS("b")=1,^MITS("c")=1
 N r,k S r="",k="" F  S k=$O(^MITS(k)) Q:k=""  S r=r_k
 Q r
