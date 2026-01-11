; Struct definitions
(struct_specifier
  name: (type_identifier) @context.struct.name
  body: (field_declaration_list) @context.struct.body) @context.struct

; Typedefs
(type_definition
  declarator: (_) @context.typedef.name) @context.typedef

; Function prototypes (declarations with function_declarator)
(declaration
  declarator: (function_declarator
    declarator: (identifier) @context.prototype.name)) @context.prototype

; Function prototypes with pointer return type
(declaration
  declarator: (pointer_declarator
    declarator: (function_declarator
      declarator: (identifier) @context.prototype.name))) @context.prototype
