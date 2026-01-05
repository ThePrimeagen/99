; Match require calls to capture imports
; Example: local foo = require("module.path")
(
  (variable_declaration
    (assignment_statement
      (variable_list
        name: (identifier) @import.alias)
      (expression_list
        value: (function_call
          name: (identifier) @_require_fn
          arguments: (arguments
            (string
              content: (string_content) @import.path))))))
  (#eq? @_require_fn "require")
) @import.decl

; Match require calls without assignment
; Example: require("module.path")
(
  (function_call
    name: (identifier) @_require_fn
    arguments: (arguments
      (string
        content: (string_content) @import.path)))
  (#eq? @_require_fn "require")
) @import.call
