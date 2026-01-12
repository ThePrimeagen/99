; Regular functions and methods in impl blocks
(function_item) @context.function

(function_item
  body: (block) @context.body)

; Closures with block body
(closure_expression) @context.function

(closure_expression
  body: (block) @context.body)

; Closures with expression body (no block, just an expression)
(closure_expression
  body: (_) @context.body)
