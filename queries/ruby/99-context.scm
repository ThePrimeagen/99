; Class definitions
(class
  name: (_) @context.class.name
  body: (body_statement)? @context.class.body) @context.class

; Module definitions
(module
  name: (_) @context.module.name
  body: (body_statement)? @context.module.body) @context.module

; Singleton class (class << self)
(singleton_class
  body: (body_statement)? @context.class.body) @context.class
