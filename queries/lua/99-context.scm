; Lua doesn't have classes/structs in the traditional sense
; but we can capture table assignments that look like module definitions

; Local table assignments (local M = {})
(variable_declaration
  (assignment_statement
    (variable_list
      name: (identifier) @context.module.name)
    (expression_list
      value: (table_constructor) @context.module.body))) @context.module
