; foo()
(call
  function: (identifier) @call.name
  arguments: (argument_list) @call.args) @call.node

; obj.method()
(call
  function: (attribute
    object: (_) @call.object
    attribute: (identifier) @call.name)
  arguments: (argument_list) @call.args) @call.node

; Class instantiation: MyClass()
(call
  function: (identifier) @call.name
  arguments: (argument_list) @call.args) @call.node

; super().method()
(call
  function: (attribute
    object: (call
      function: (identifier) @call.super_name)
    attribute: (identifier) @call.name)
  arguments: (argument_list) @call.args) @call.node
