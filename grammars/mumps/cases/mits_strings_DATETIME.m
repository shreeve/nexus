DATETIME ; MITS - $ZD / $ZT / $ZDATETIME formatting tests
 ;
 ; $ZDATE(horolog, fmt)
 ;   fmt 1: MM/DD/YY    e.g. 04/27/26
 ;   fmt 2: MM/DD/YYYY  e.g. 04/27/2026
 ;   fmt 3: DD-MM-YYYY  e.g. 27-04-2026
 ;   default: MM/DD/YYYY (engine-specific)
 ;
 ; $ZTIME(seconds, fmt) where seconds is seconds-since-midnight
 ;   fmt 1: HH:MM:SS
 ;   fmt 2: HH:MM
 ;   default: HH:MM:SS (engine-specific)
 ;
 D START^TEST("compliance/strings/DATETIME")
 ;
 ; --- $ZDATE: known horolog values ---
 ; MUMPS day 47117 = Unix epoch = 01/01/1970
 D RUN^TEST("$ZD epoch fmt 1","01/01/70","$ZD(47117,1)")
 D RUN^TEST("$ZD epoch fmt 2","01/01/1970","$ZD(47117,2)")
 D RUN^TEST("$ZD epoch fmt 3","01-01-1970","$ZD(47117,3)")
 D RUN^TEST("$ZD numeric arg works","01/01/1970","$ZD(47117,2)")
 D RUN^TEST("$ZD string arg works","01/01/1970","$ZD(""47117"",2)")
 ;
 ; --- $ZD known dates ---
 ; em's MUMPS-epoch base: day 0 = 12/31/1840, day 1 = 01/01/1841.
 D RUN^TEST("$ZD MUMPS day 0","12/31/40","$ZD(0,1)")
 D RUN^TEST("$ZD MUMPS day 1","01/01/41","$ZD(1,1)")
 D RUN^TEST("$ZD MUMPS day 0 long","12/31/1840","$ZD(0,2)")
 ;
 ; --- $ZTIME: seconds since midnight ---
 D RUN^TEST("$ZT 0 (midnight)","00:00:00","$ZT(0,1)")
 D RUN^TEST("$ZT 1 (00:00:01)","00:00:01","$ZT(1,1)")
 D RUN^TEST("$ZT noon","12:00:00","$ZT(43200,1)")
 D RUN^TEST("$ZT one minute","00:01:00","$ZT(60,1)")
 D RUN^TEST("$ZT one hour","01:00:00","$ZT(3600,1)")
 D RUN^TEST("$ZT 23:59:59","23:59:59","$ZT(86399,1)")
 D RUN^TEST("$ZT format 2 HH:MM","12:00","$ZT(43200,2)")
 ;
 ; --- $ZDATETIME ---
 ; Note: $ZDT abbreviation isn't a clean prefix of $ZDATETIME (collides
 ; with $ZDATE), so MITS uses the full name.
 D RUN^TEST("$ZDATETIME epoch noon","01/01/1970 12:00:00","$ZDATETIME(""47117,43200"",2,1)")
 D RUN^TEST("$ZDATETIME epoch midnight","01/01/1970 00:00:00","$ZDATETIME(""47117,0"",2,1)")
 D RUN^TEST("$ZDATETIME with $ZH 4-field horolog","01/01/1970 12:00:00","$ZDATETIME(""47117,43200,12345,21600"",2,1)")
 D RUN^TEST("$ZDATETIME numeric date arg","12/31/1840 00:00:00","$$ZDTNUM^DATETIME()")
 ;
 ; --- $ZD with computed argument ---
 D RUN^TEST("$ZD day-after epoch","01/02/1970","$ZD(47117+1,2)")
 D RUN^TEST("$ZD year boundary","12/31/1970","$ZD(47117+364,2)")
 ;
 D END^TEST("compliance/strings/DATETIME")
 Q
 ;
ZDTNUM() Q $ZDATETIME("0,0",2,1)
