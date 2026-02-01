; fn foo() { }
(function_item
  body: (block) @context.body) @context.function

; |x| { }
(closure_expression
  body: (block) @context.body) @context.function
