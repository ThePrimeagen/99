; Instance methods
(method) @context.function

(method
  body: (body_statement) @context.body)

; Singleton/class methods (def self.foo)
(singleton_method) @context.function

(singleton_method
  body: (body_statement) @context.body)

; Lambda literals
(lambda) @context.function

(lambda
  body: (_) @context.body)

; Do blocks (treat as fillable)
(do_block) @context.function

(do_block
  body: (body_statement) @context.body)

; Brace blocks (treat as fillable)
(block) @context.function

(block
  body: (block_body) @context.body)
