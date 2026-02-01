; Block scope: { }
(block) @context.scope

; impl Type { } or impl Trait for Type { }
(impl_item) @context.scope

; trait Name { }
(trait_item) @context.scope

; struct Name { } or struct Name (..);
(struct_item) @context.scope

; mod name { }
(mod_item) @context.scope
