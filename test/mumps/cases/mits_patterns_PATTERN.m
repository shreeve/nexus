PATTERN ; MITS - pattern matching (?) operator tests
 ;
 ; expr ? pattern  - returns 1 if expr matches pattern, 0 otherwise.
 ; Pattern atoms:
 ;   nN   - exactly n digits   ("3N" = 3 numerics)
 ;   .N   - any number of digits (zero or more)
 ;   1.5N - 1 to 5 digits
 ;   nA   - alphabetic chars
 ;   nU   - uppercase
 ;   nL   - lowercase
 ;   nP   - punctuation
 ;   nC   - control chars
 ;   nE   - everything (any char)
 ;   n"lit" - exactly that literal string repeated n times
 ;   (alt1,alt2)  - alternation
 ;
 D START^TEST("compliance/patterns/PATTERN")
 ;
 ; --- Numeric patterns ---
 D RUN^TEST("3N exact 3 digits",1,"""123""?3N")
 D RUN^TEST("3N reject 2 digits",0,"""12""?3N")
 D RUN^TEST("3N reject 4 digits",0,"""1234""?3N")
 D RUN^TEST(".N matches 0 digits",1,"""""?.N")
 D RUN^TEST(".N matches many digits",1,"""123456789""?.N")
 D RUN^TEST(".N rejects letters",0,"""abc""?.N")
 D RUN^TEST("1.3N range 1-3 digits OK",1,"""12""?1.3N")
 D RUN^TEST("1.3N range too many",0,"""1234""?1.3N")
 ;
 ; --- Alpha / case patterns ---
 D RUN^TEST("3A letters",1,"""abc""?3A")
 D RUN^TEST("3U uppercase",1,"""ABC""?3U")
 D RUN^TEST("3U rejects lowercase",0,"""abc""?3U")
 D RUN^TEST("3L lowercase",1,"""abc""?3L")
 D RUN^TEST("3L rejects uppercase",0,"""ABC""?3L")
 ;
 ; --- Concatenated atoms ---
 D RUN^TEST("3N1.E1A digit-anychar-letter",1,"""123 z""?3N1.E1A")
 D RUN^TEST("phone-like 3N1""-""4N",1,"""555-1234""?3N1""-""4N")
 D RUN^TEST("phone reject no dash",0,"""5551234""?3N1""-""4N")
 ;
 ; --- Literal patterns ---
 D RUN^TEST("literal exact match",1,"""ABC""?1""ABC""")
 D RUN^TEST("literal reject differ",0,"""XYZ""?1""ABC""")
 ;
 ; --- Empty / edge cases ---
 D RUN^TEST(".A on empty matches",1,"""""?.A")
 D RUN^TEST("0N on empty",1,"""""?0N")
 ;
 ; --- Punctuation / control ---
 D RUN^TEST("3P punctuation",1,"""!@#""?3P")
 D RUN^TEST("3P rejects letters",0,"""abc""?3P")
 ;
 ; --- Mixed-content pattern .E (any) ---
 D RUN^TEST(".E matches anything",1,"""whatever""?.E")
 ;
 ; --- Real-world patterns ---
 D RUN^TEST("simple email-like ID",1,"""ab12""?2A2N")
 D RUN^TEST("US zip 5N",1,"""12345""?5N")
 D RUN^TEST("US zip+4 like",1,"""12345-6789""?5N1""-""4N")
 ;
 D END^TEST("compliance/patterns/PATTERN")
 Q
