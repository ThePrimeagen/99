; Class declarations
(class_declaration
  name: (type_identifier) @context.class.name
  body: (class_body) @context.class.body) @context.class

; Abstract class declarations
(abstract_class_declaration
  name: (type_identifier) @context.class.name
  body: (class_body) @context.class.body) @context.class

; Class expressions
(class
  name: (type_identifier)? @context.class.name
  body: (class_body) @context.class.body) @context.class

; Interface declarations
(interface_declaration
  name: (type_identifier) @context.interface.name
  body: (interface_body) @context.interface.body) @context.interface

; Type alias declarations (for context)
(type_alias_declaration
  name: (type_identifier) @context.type.name
  value: (_) @context.type.value) @context.type

; Enum declarations
(enum_declaration
  name: (identifier) @context.enum.name
  body: (enum_body) @context.enum.body) @context.enum

; Namespace/Module declarations
(module
  name: (_) @context.namespace.name
  body: (statement_block) @context.namespace.body) @context.namespace
