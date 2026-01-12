; Regular comments
(comment) @context.comment

; Docstrings - first string in function body
(function_definition
  body: (block .
    (expression_statement
      (string) @context.docstring)))

; Docstrings - first string in class body
(class_definition
  body: (block .
    (expression_statement
      (string) @context.docstring)))

; Docstrings in decorated functions
(decorated_definition
  definition: (function_definition
    body: (block .
      (expression_statement
        (string) @context.docstring))))
