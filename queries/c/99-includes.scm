; Local includes (quoted) - #include "header.h"
(preproc_include
  path: (string_literal) @include.local)

; System includes (angle brackets) - #include <stdio.h>
(preproc_include
  path: (system_lib_string) @include.system)
