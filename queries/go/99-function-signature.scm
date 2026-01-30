(function_declaration
  name: (identifier) @function.name

  parameters: (parameter_list
    (parameter_declaration
      name: (identifier)? @parameter.name
      type: (_) @parameter.type
    )*
  )

  result: (parameter_list
    (parameter_declaration
      name: (identifier)? @return.name
      type: (_) @return.type
    )*
  )?
) @function.definition

(method_declaration
  receiver: (parameter_list
    (parameter_declaration
      name: (identifier)? @receiver.name
      type: (type_identifier) @receiver.type.id
    )
  )

  name: (field_identifier) @function.name

  parameters: (parameter_list
    (parameter_declaration
      name: (identifier)? @parameter.name
      type: (_) @parameter.type
    )*
  )

  result: (parameter_list
    (parameter_declaration
      name: (identifier)? @return.name
      type: (_) @return.type
    )*
  )?
) @function.definition

(method_declaration
  receiver: (parameter_list
    (parameter_declaration
      name: (identifier)? @receiver.name
      type: (pointer_type
              (type_identifier) @receiver.type.id)
    )
  )

  name: (field_identifier) @function.name

  parameters: (parameter_list
    (parameter_declaration
      name: (identifier)? @parameter.name
      type: (_) @parameter.type
    )*
  )

  result: (parameter_list
    (parameter_declaration
      name: (identifier)? @return.name
      type: (_) @return.type
    )*
  )?
) @function.definition

