///|
priv enum RequirementTypePart {
  Field(String)
  Items
}

///|
fn write_check_requirement_path(
  writer : @encode.Writer,
  path : Array[RequirementTypePart],
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "path")
  @encode.begin_array(writer)
  for part in path {
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    match part {
      Field(name) => {
        @encode.string_value(writer, "field")
        @encode.key(writer, "name")
        @encode.string_value(writer, name)
      }
      Items => @encode.string_value(writer, "items")
    }
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
}

///|
/// The admitted type Owner supplies the complete contract and recursive rules.
/// A rule path is a type-definition path, never an invented input location.
/// The existing report writer bounds this traversal and can omit a whole
/// Requirement if its safe admission facts cannot fit. No raw cursor, default,
/// annotation or supplied value enters this projection.
fn write_check_parameter_admission(
  writer : @encode.Writer,
  root : @parameter_contract.ParameterType,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "contract")
  @parameter_contract.emit_checked(root.contract, writer)
  @encode.key(writer, "contract_schema_cid")
  @encode.string_value(writer, check_parameter_contract_schema_cid)
  @encode.key(writer, "constraints")
  @encode.begin_array(writer)
  let pending : Array[
    (@parameter_contract.ParameterType, Array[RequirementTypePart]),
  ] = [(root, [])]
  while pending.pop() is Some((value, path)) {
    match value.rule {
      Plain => ()
      Numeric(integer~, minimum~, maximum~) => {
        @encode.begin_object(writer)
        @encode.key(writer, "integer")
        @encode.bool_value(writer, integer)
        @encode.key(writer, "kind")
        @encode.string_value(writer, "numeric")
        if maximum is Some(bound) {
          @encode.key(writer, "maximum")
          @encode.number_value(writer, bound)
        }
        if minimum is Some(bound) {
          @encode.key(writer, "minimum")
          @encode.number_value(writer, bound)
        }
        write_check_requirement_path(writer, path)
        @encode.end_object(writer)
      }
      Duration => {
        @encode.begin_object(writer)
        @encode.key(writer, "kind")
        @encode.string_value(writer, "duration")
        write_check_requirement_path(writer, path)
        @encode.end_object(writer)
      }
      Items(child, length~) => {
        if length is Some(count) {
          @encode.begin_object(writer)
          @encode.key(writer, "kind")
          @encode.string_value(writer, "array_length")
          @encode.key(writer, "length")
          @encode.number_value(writer, count.to_double())
          write_check_requirement_path(writer, path)
          @encode.end_object(writer)
        }
        let next = path.copy()
        next.push(Items)
        pending.push((child, next))
      }
      Properties(fields) => {
        // Read the canonical Owner order without copying the field array.
        let mut index = 0
        let children = []
        while @parameter_contract.parameter_field_at(fields, index)
              is Some(child) {
          let next = path.copy()
          next.push(Field(child.0))
          children.push((child.1, next))
          index = index + 1
        }
        for child = children.length() - 1; child >= 0; child = child - 1 {
          pending.push(children[child])
        }
      }
    }
  }
  @encode.end_array(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "parameter_declaration")
  @encode.key(writer, "supplier")
  @encode.string_value(writer, "caller")
  @encode.end_object(writer)
}
