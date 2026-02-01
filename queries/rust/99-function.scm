; Regular functions and methods in impl blocks
(function_item) @context.function

; Covers free fn, impl/trait methods, async/unsafe/const/extern fn
(function_item
  body: (block) @context.body)

; Closures (block or expression body)
(closure_expression) @context.function

(closure_expression
  body: (_) @context.body)
