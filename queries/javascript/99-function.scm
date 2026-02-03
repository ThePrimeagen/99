(function_declaration) @context.function
(function_expression) @context.function
(arrow_function) @context.function
(method_definition) @context.function
(generator_function) @context.function
(generator_function_declaration) @context.function

(function_declaration
  body: (statement_block) @context.body)

(function_expression
  body: (statement_block) @context.body)

(arrow_function
  body: (statement_block) @context.body)

(method_definition
  body: (statement_block) @context.body)

(generator_function
  body: (statement_block) @context.body)

(generator_function_declaration
  body: (statement_block) @context.body)
