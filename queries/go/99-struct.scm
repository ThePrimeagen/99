(type_spec
  (type_identifier) @struct.name
  (struct_type
    (field_declaration_list) @struct.body
  )
) @struct.definition

(field_declaration
  (field_identifier) @field.name
  (_) @field.type
) @field

