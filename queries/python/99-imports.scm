; import foo
(import_statement
  (dotted_name) @import.name) @import.decl

; import foo as bar
(import_statement
  (aliased_import
    name: (dotted_name) @import.name
    alias: (identifier) @import.alias)) @import.decl

; from foo import bar
(import_from_statement
  module_name: (dotted_name) @import.module
  name: (dotted_name) @import.name) @import.decl

; from foo import bar as baz
(import_from_statement
  module_name: (dotted_name) @import.module
  name: (aliased_import
    name: (dotted_name) @import.name
    alias: (identifier) @import.alias)) @import.decl

; from . import foo (relative import)
(import_from_statement
  module_name: (relative_import) @import.module
  name: (dotted_name) @import.name) @import.decl

; from __future__ import annotations
(future_import_statement
  name: (dotted_name) @import.name) @import.decl
