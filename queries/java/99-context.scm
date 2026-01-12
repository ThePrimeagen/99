; Class definitions
(class_declaration
  name: (identifier) @context.class.name
  body: (class_body) @context.class.body) @context.class

; Interface definitions
(interface_declaration
  name: (identifier) @context.interface.name
  body: (interface_body) @context.interface.body) @context.interface

; Enum definitions
(enum_declaration
  name: (identifier) @context.enum.name
  body: (enum_body) @context.enum.body) @context.enum

; Record definitions (Java 14+)
(record_declaration
  name: (identifier) @context.record.name
  body: (class_body) @context.record.body) @context.record
