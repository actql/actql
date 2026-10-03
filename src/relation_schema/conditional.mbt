///|
/// Field presence is independent of the admitted value contract's nullability.
pub(all) enum FieldPresence {
  Required
  Conditional
} derive(Eq, Debug)

///|
struct ConditionalField {
  field : Field
  presence : FieldPresence
}

///|
/// A finite typed layout whose rows may omit only conditional fields. This
/// cannot be passed to the dense Relation APIs as an ordinary Schema.
struct ConditionalSchema {
  fields : Array[ConditionalField]
  required : Schema
  required_indices : Array[Int]
}

///|
pub enum PresenceLookup {
  AlwaysPresent(Field)
  ConditionallyPresent(Field)
  AbsentField
}

///|
/// Validate all names and contracts through the existing schema owner, then
/// retain the presence declaration separately from the nullable value type.
pub fn from_presence_fields(
  entries : Array[(FieldName, @contract.Contract, FieldPresence)],
  max_fields~ : Int,
  max_name_bytes~ : Int,
) -> Result[ConditionalSchema, Issue] {
  let all = match
    from_fields(
      entries.map(entry => (entry.0, entry.1)),
      max_fields~,
      max_name_bytes~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let presence : Map[String, FieldPresence] = Map([])
  for (name, _, declared) in entries {
    presence[reference_name(name)] = declared
  }
  let result_fields = []
  let required_entries = []
  for field in fields(all) {
    let declared = presence[reference_name(field.name)]
    result_fields.push({ field, presence: declared, })
    if declared == Required {
      required_entries.push((field.name, field.contract))
    }
  }
  let required = from_fields(required_entries, max_fields~, max_name_bytes~).unwrap()
  let required_indices = []
  for index in 0..<result_fields.length() {
    if result_fields[index].presence == Required {
      required_indices.push(index)
    }
  }
  Ok({ fields: result_fields, required, required_indices, })
}

///|
pub fn presence_field_count(schema : ConditionalSchema) -> Int {
  schema.fields.length()
}

///|
pub fn presence_field_at(
  schema : ConditionalSchema,
  index : Int,
) -> ConditionalField? {
  schema.fields.get(index)
}

///|
pub fn presence_field_name(field : ConditionalField) -> FieldName {
  field.field.name
}

///|
pub fn presence_field_contract(field : ConditionalField) -> @contract.Contract {
  field.field.contract
}

///|
pub fn field_presence(field : ConditionalField) -> FieldPresence {
  field.presence
}

///|
pub fn presence_lookup(
  schema : ConditionalSchema,
  name : FieldName,
) -> PresenceLookup {
  let spelling = reference_name(name)
  let mut lo = 0
  let mut hi = schema.fields.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let candidate = reference_name(schema.fields[mid].field.name)
    if @canonical.compare_utf16(candidate, spelling) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  match schema.fields.get(lo) {
    Some(entry) if entry.field.name == name =>
      if entry.presence == Required {
        AlwaysPresent(entry.field)
      } else {
        ConditionallyPresent(entry.field)
      }
    _ => AbsentField
  }
}

///|
/// Only these columns may enter an existing dense Relation consumer without
/// a separate proof that conditionally present fields exist in every row.
pub fn required_projection_schema(schema : ConditionalSchema) -> Schema {
  schema.required
}

///|
pub fn required_source_index(schema : ConditionalSchema, index : Int) -> Int? {
  schema.required_indices.get(index)
}
