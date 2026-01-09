; named functions
; 1. arguments and inline do block
(call
  target: (identifier) @_func_type
  (arguments
    (call
      target: (identifier)
      (do_block) @context.body))
  (#any-of? @_func_type "def" "defp" "defmacro" "defmacrop")) @context.function

; 2. arguments and separate do block
(call
  target: (identifier) @_func_type
  (arguments
    (call
      target: (identifier)
      (arguments)))
  (do_block) @context.body
  (#any-of? @_func_type "def" "defp" "defmacro" "defmacrop")) @context.function

; 3. without arguments just identifier
(call
  target: (identifier) @_func_type
  (arguments
    (identifier))
  (do_block) @context.body
  (#any-of? @_func_type "def" "defp" "defmacro" "defmacrop")) @context.function

; anonymous functions
; 1. module attributes (@name fn -> end) with body
(unary_operator
  (call
    (arguments
      (anonymous_function
        (stab_clause
          right: (body) @context.body))))) @context.function

; 2. without body (empty @name fn x -> end)
(unary_operator
  (call
    (arguments
      (anonymous_function
        (stab_clause
          (arguments)))))) @context.function
