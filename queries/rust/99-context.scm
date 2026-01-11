; Inherent impl blocks (impl MyType { ... })
(impl_item
  type: (_) @context.impl.type
  body: (declaration_list) @context.impl.body) @context.impl

; Trait implementations (impl Trait for Type { ... })
(impl_item
  trait: (_) @context.impl.trait
  type: (_) @context.impl.type
  body: (declaration_list) @context.impl.body) @context.trait_impl

; Trait definitions
(trait_item
  name: (type_identifier) @context.trait.name
  body: (declaration_list) @context.trait.body) @context.trait

; Struct definitions
(struct_item
  name: (type_identifier) @context.struct.name) @context.struct

; Enum definitions
(enum_item
  name: (type_identifier) @context.enum.name
  body: (enum_variant_list) @context.enum.body) @context.enum
