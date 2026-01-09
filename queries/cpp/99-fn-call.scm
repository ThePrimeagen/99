; // Identifier call
; auto foo(int arg) -> void { foo(arg); }
(call_expression
  function: (identifier) @call.name
  arguments: (argument_list) @call.args) @call.node

; // Qualified call
; namespace ns {
;     void bar(int);
; }
; auto bar(int arg) -> void { ns::bar(arg); }
(call_expression
  function: (qualified_identifier
    name: (identifier) @call.name)
  arguments: (argument_list) @call.args) @call.node

; // Member & pointer member call
; struct S {
;     void baz(int);
; };
; auto baz(S obj, int arg) -> void { obj.baz(arg); }
; auto baz(S* obj, int arg) -> void { obj->baz(arg); }
(call_expression
  function: (field_expression
    field: (field_identifier) @call.name)
  arguments: (argument_list) @call.args) @call.node

; // Template call
; template <class T> void qux(T);
; auto qux(int arg) -> void { qux<int>(arg); }
(call_expression
  function: (template_function
    name: (identifier) @call.name)
  arguments: (argument_list) @call.args) @call.node

; // Function pointer call
; using Fn = void (*)(int);
; auto quux(Fn fp, int arg) -> void { (*fp)(arg); }
(call_expression
  function: (parenthesized_expression
    (pointer_expression
      (identifier) @call.name))
  arguments: (argument_list) @call.args) @call.node
