; foo(...)
(call_expression
  function: (identifier) @call.name
  arguments: (arguments) @call.args) @call.node

; obj.method(...)
(call_expression
  function: (field_expression
    field: (field_identifier) @call.name)
  arguments: (arguments) @call.args) @call.node

; path::to::function(...)
(call_expression
  function: (scoped_identifier
    name: (identifier) @call.name)
  arguments: (arguments) @call.args) @call.node

; foo::<T, U>(...)
(call_expression
  function: (generic_function
    function: (identifier) @call.name)
  arguments: (arguments) @call.args) @call.node

; macro!(...)
(macro_invocation
  macro: (identifier) @call.name
  token_tree: (_) @call.args) @call.node

; path::macro!(...)
(macro_invocation
  macro: (scoped_identifier
    name: (identifier) @call.name)
  token_tree: (_) @call.args) @call.node
