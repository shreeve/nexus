DATA ; MITS - $DATA on globals
 ;
 D START^TEST("compliance/globals/DATA")
 ;
 K ^MITS
 ;
 D RUN^TEST("$D undefined ^G",0,"$$UND^DATA()")
 D RUN^TEST("$D defined value",1,"$$VAL^DATA()")
 D RUN^TEST("$D subscripted value",1,"$$SUBVAL^DATA()")
 D RUN^TEST("$D empty string value",1,"$$EMPTY^DATA()")
 D RUN^TEST("$D zero value",1,"$$ZERO^DATA()")
 D RUN^TEST("$D root with leaf only",10,"$$LEAFONLY^DATA()")
 D RUN^TEST("$D intermediate",10,"$$INTERMED^DATA()")
 D RUN^TEST("$D both value and leaves",11,"$$BOTH^DATA()")
 D RUN^TEST("$D after K leaf",0,"$$KLEAF^DATA()")
 D RUN^TEST("$D after K root",0,"$$KROOT^DATA()")
 D RUN^TEST("$D 3-level deep value",1,"$$DEEP^DATA()")
 D RUN^TEST("$D 2-level intermediate with deep",10,"$$DEEPINT^DATA()")
 D RUN^TEST("$D in IF context truthy",1,"$$IFEX^DATA()")
 D RUN^TEST("$D in IF context falsy",0,"$$IFNX^DATA()")
 ;
 K ^MITS
 ;
 D END^TEST("compliance/globals/DATA")
 Q
 ;
UND() K ^MITS
 Q $D(^MITS)
 ;
VAL() K ^MITS S ^MITS=42
 Q $D(^MITS)
 ;
SUBVAL() K ^MITS S ^MITS("a")=1
 Q $D(^MITS("a"))
 ;
EMPTY() K ^MITS S ^MITS=""
 Q $D(^MITS)
 ;
ZERO() K ^MITS S ^MITS=0
 Q $D(^MITS)
 ;
LEAFONLY() K ^MITS S ^MITS("leaf")=1
 Q $D(^MITS)
 ;
INTERMED() K ^MITS S ^MITS("a","b","c")=1
 Q $D(^MITS("a"))
 ;
BOTH() K ^MITS S ^MITS=99,^MITS("leaf")=1
 Q $D(^MITS)
 ;
KLEAF() K ^MITS S ^MITS("a")=1 K ^MITS("a")
 Q $D(^MITS("a"))
 ;
KROOT() K ^MITS S ^MITS=1,^MITS("a")=2 K ^MITS
 Q $D(^MITS)
 ;
DEEP() K ^MITS S ^MITS("a","b","c")=42
 Q $D(^MITS("a","b","c"))
 ;
DEEPINT() K ^MITS S ^MITS("a","b","c")=42
 Q $D(^MITS("a","b"))
 ;
IFEX() K ^MITS S ^MITS=1
 I $D(^MITS) Q 1
 Q 0
 ;
IFNX() K ^MITS
 I $D(^MITS) Q 1
 Q 0
