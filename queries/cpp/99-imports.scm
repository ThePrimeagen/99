; import foo_module;
(import_declaration
  name: (module_name
    (identifier) @import.name)) @import.decl

; #include "foo.hpp"
(preproc_include
  path: (string_literal
    (string_content) @import.name)) @import.decl

; #include <foo>
(preproc_include
  path: (system_lib_string) @import.name) @import.decl
