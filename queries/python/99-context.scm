; Class definitions
(class_definition
  name: (identifier) @context.class.name
  body: (block) @context.class.body) @context.class

; Decorated classes
(decorated_definition
  definition: (class_definition
    name: (identifier) @context.class.name
    body: (block) @context.class.body)) @context.class
