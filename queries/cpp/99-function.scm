; void foo() { }
(function_definition
  body: (compound_statement) @context.body) @context.function

; const auto foo = [](int arg) { };
(declaration
  declarator: (init_declarator
    value: (lambda_expression
      body: (compound_statement) @context.body))) @context.function

; template<typename T>
; concept Foo = requires(T foo) {
;     { foo() } -> std::same_as<void>;
;     {  ...  } -> ...;
; };
(concept_definition
  (requires_expression
    requirements: (requirement_seq) @context.body)) @context.function
