COERCE ; MITS - string/numeric coercion edge cases
 ;
 ; MUMPS auto-coerces strings to numbers and back per the canonical
 ; lenient rules. Tests document precisely what counts as numeric.
 ;
 D START^TEST("compliance/operators/COERCE")
 ;
 ; --- Unary + as coercion-to-number ---
 D RUN^TEST("+ on plain digit",5,"+""5""")
 D RUN^TEST("+ leading sign",-5,"+""-5""")
 D RUN^TEST("+ leading + ignored",5,"+""+5""")
 D RUN^TEST("+ leading zeros stripped",5,"+""005""")
 D RUN^TEST("+ trailing junk",5,"+""5abc""")
 D RUN^TEST("+ numeric in middle ignores trailing",5,"+""5 6""") ; stops at space
 D RUN^TEST("+ leading whitespace = 0 (per spec)",0,"+"" 5""") ; spec: leading whitespace is non-numeric
 D RUN^TEST("+ scientific",100,"+""1E2""")
 D RUN^TEST("+ neg scientific",.01,"+""1E-2""")
 D RUN^TEST("+ decimal",3.14,"+""3.14""")
 D RUN^TEST("+ leading dot",.5,"+"".5""")
 D RUN^TEST("+ trailing dot ignored",5,"+""5.""")
 D RUN^TEST("+ all junk = 0",0,"+""xyz""")
 D RUN^TEST("+ empty = 0",0,"+""""")
 ;
 ; --- Number to string (canonical form) ---
 D RUN^TEST("1.5 in concat","val=1.5","""val=""_1.5")
 D RUN^TEST("trailing zeros stripped","val=1.5","""val=""_1.50")
 D RUN^TEST("leading zeros stripped","val=5","""val=""_05")
 D RUN^TEST("scientific normalized","val=100","""val=""_1E2")
 D RUN^TEST("negative zero is just 0","val=0","""val=""_(-0)")
 ;
 ; --- = comparison: pure string compare for string operands ---
 ; em canonicalizes numeric literals at PARSE time but not string
 ; operands at RUNTIME. So 03=3 is true (both parse to 3), but
 ; "05"=5 is false ("05" stays as "05" at runtime, "5" stays as "5").
 ; This is an em-specific behavior; strict ANSI spec would canonicalize
 ; both. Tests reflect what em currently does.
 D RUN^TEST("string non-canon != canonical",0,"""05""=5")
 D RUN^TEST("decimal-form string != canon",0,"""5.0""=5")
 D RUN^TEST("string with garbage != number",0,"""5abc""=5")
 D RUN^TEST("non-numeric string != zero",0,"""abc""=0")
 ;
 ; --- Numeric comparison (<, >) does coerce ---
 D RUN^TEST("""abc""<1 coerces to 0",1,"""abc""<1")
 D RUN^TEST("""5abc""<10 coerces to 5",1,"""5abc""<10")
 D RUN^TEST("""5abc"">4 coerces to 5",1,"""5abc"">4")
 ;
 ; --- + on undefined boolean ---
 D RUN^TEST("+ on true (1)",1,"+1")
 D RUN^TEST("+ on false (0)",0,"+0")
 ;
 ; --- $L preserves numeric form (canonicalizes first) ---
 D RUN^TEST("$L of number = digits in canonical",1,"$L(05)") ; 05 → "5", len 1
 D RUN^TEST("$L of negative",2,"$L(-5)")
 D RUN^TEST("$L of decimal",3,"$L(1.5)")
 D RUN^TEST("$L of scientific normalized",3,"$L(1E2)") ; "100"
 ;
 D END^TEST("compliance/operators/COERCE")
 Q
