; Regular functions (including async)
(function_definition) @context.function

(function_definition
  body: (block) @context.body)

; Decorated functions - the decorator wraps the function
(decorated_definition
  definition: (function_definition)) @context.function

(decorated_definition
  definition: (function_definition
    body: (block) @context.body))

; Lambda expressions
(lambda) @context.function

(lambda
  body: (_) @context.body)
