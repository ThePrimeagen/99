; Struct definitions
(type_declaration
  (type_spec
    name: (type_identifier) @context.struct.name
    type: (struct_type) @context.struct.body)) @context.struct

; Interface definitions
(type_declaration
  (type_spec
    name: (type_identifier) @context.interface.name
    type: (interface_type) @context.interface.body)) @context.interface

; Method receivers - to identify the receiver type
(method_declaration
  receiver: (parameter_list
    (parameter_declaration
      type: (_) @context.receiver.type))) @context.method_with_receiver
