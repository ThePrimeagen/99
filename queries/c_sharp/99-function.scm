(method_declaration) @context.function
(constructor_declaration) @context.function
(destructor_declaration) @context.function
(operator_declaration) @context.function
(conversion_operator_declaration) @context.function
(local_function_statement) @context.function

(method_declaration
  body: (block) @context.body)

(constructor_declaration
  body: (block) @context.body)

(destructor_declaration
  body: (block) @context.body)

(operator_declaration
  body: (block) @context.body)

(conversion_operator_declaration
  body: (block) @context.body)

(local_function_statement
  body: (block) @context.body)
