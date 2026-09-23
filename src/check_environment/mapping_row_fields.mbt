///|
pub(all) enum MappingRowFieldsIssue {
  InvalidLimits
  WorkLimit
  InvalidRowMapping
  NonWritableField(String)
  MissingRequiredField(String)
} derive(Eq, Debug)

///|
pub struct MappingRowFields {
  shape : MappingContractShape
  fields : Array[String]
  work : Int
}

///|
pub fn mapping_row_fields_shape(
  value : MappingRowFields,
) -> MappingContractShape {
  value.shape
}

///|
pub fn mapping_row_fields_names(value : MappingRowFields) -> Array[String] {
  value.fields.copy()
}

///|
pub fn mapping_row_fields_work(value : MappingRowFields) -> Int {
  value.work
}

///|
/// Admit explicit target-field sources and null behavior for a result-backed
/// create or store. Literal/result type compatibility and conversion laws are
/// separate obligations; this is not a Preview or apply permit.
pub fn check_mapping_row_fields(
  shape : MappingContractShape,
  max_work : Int,
) -> Result[MappingRowFields, MappingRowFieldsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let root = member_body(shape.item)
  let object = @decode.open_object(root).unwrap()
  let row = match @decode.lookup(object, "row_mapping") {
    Some(value) => value
    None => return Err(InvalidRowMapping)
  }
  let count = match @decode.object_length(row) {
    Some(value) => value
    None => return Err(InvalidRowMapping)
  }
  if count > max_work ||
    shape.writable_fields.length() > max_work - count ||
    shape.required_fields.length() >
    max_work - count - shape.writable_fields.length() {
    return Err(WorkLimit)
  }
  let writable : Map[String, Bool] = Map([])
  for field in shape.writable_fields {
    writable[field] = true
  }
  let fields : Array[String] = []
  let selected : Map[String, Bool] = Map([])
  for index in 0..<count {
    let (field, source) = @decode.field_at(row, index).unwrap()
    if field.is_empty() {
      return Err(InvalidRowMapping)
    }
    if !writable.contains(field) {
      return Err(NonWritableField(field))
    }
    let entry = match
      @decode.closed_object(source, ["field", "literal", "null_behavior"]) {
      Ok(value) => value
      Err(_) => return Err(InvalidRowMapping)
    }
    let from_field = @decode.lookup(entry, "field")
    let literal = @decode.lookup(entry, "literal")
    if (from_field is Some(_)) == (literal is Some(_)) {
      return Err(InvalidRowMapping)
    }
    if from_field is Some(value) {
      match @decode.text(value) {
        Ok(name) if !name.is_empty() => ()
        _ => return Err(InvalidRowMapping)
      }
    }
    let behavior = match @decode.lookup(entry, "null_behavior") {
      Some(value) =>
        match @decode.text(value) {
          Ok(name) => name
          Err(_) => return Err(InvalidRowMapping)
        }
      None => return Err(InvalidRowMapping)
    }
    if behavior != "reject" && behavior != "write_null" && behavior != "omit" {
      return Err(InvalidRowMapping)
    }
    fields.push(field)
    selected[field] = true
  }
  for field in shape.required_fields {
    if !selected.contains(field) {
      return Err(MissingRequiredField(field))
    }
  }
  Ok({
    shape,
    fields,
    work: count +
    shape.writable_fields.length() +
    shape.required_fields.length(),
  })
}
