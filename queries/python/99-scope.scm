; class Foo:
(class_definition) @context.scope

; def foo():
(function_definition) @context.scope

; async def foo():
(function_definition) @context.scope

; lambda x: x
(lambda) @context.scope

; Module level (the whole file)
(module) @context.scope

; with statement creates a scope context
(with_statement) @context.scope

; for loop
(for_statement) @context.scope

; while loop
(while_statement) @context.scope

; try/except block
(try_statement) @context.scope

; match statement (Python 3.10+)
(match_statement) @context.scope
