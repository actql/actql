///|
/// A field-set constraint, not row-order, uniqueness, or acquisition evidence.
pub(all) enum FieldSet {
  Open
  Closed
} derive(Eq, Debug)

///|
pub struct Field {
  name : @row.FieldName
  contract : @value.Contract?
}

///|
/// Unknown is not Absent, and a known field need not have a known value type.
pub enum Lookup {
  Unknown
  Absent
  Present(Field)
}

///|
struct Knowledge {
  field_set : FieldSet
  entries : Array[Field]
  complete : @row.Schema?
  conditional : @row.ConditionalSchema?
  has_qualified_fields : Bool
}

///|
pub fn unknown_rows() -> Knowledge {
  {
    field_set: Open,
    entries: [],
    complete: None,
    conditional: None,
    has_qualified_fields: false,
  }
}

///|
pub fn typed_rows(schema : @row.Schema) -> Knowledge {
  {
    field_set: Closed,
    entries: @row.fields(schema).map(f => {
      name: f.name,
      contract: Some(f.contract),
    }),
    complete: Some(schema),
    conditional: None,
    has_qualified_fields: @row.as_object(schema) is None,
  }
}

///|
/// A finite Relation layout with row-dependent presence. Conditional fields
/// retain their exact contracts in the schema but are not ordinary lookup
/// evidence or a complete dense schema for unadapted consumers.
pub fn conditional_rows(schema : @row.ConditionalSchema) -> Knowledge {
  let entries = []
  let mut qualified = false
  for index in 0..<@row.presence_field_count(schema) {
    let field = @row.presence_field_at(schema, index).unwrap()
    let name = @row.presence_field_name(field)
    if name is @row.Qualified(_, _) {
      qualified = true
    }
    entries.push({
      name,
      contract: if @row.field_presence(field) == @row.Required {
        Some(@row.presence_field_contract(field))
      } else {
        None
      },
    })
  }
  {
    field_set: Closed,
    entries,
    complete: None,
    conditional: Some(schema),
    has_qualified_fields: qualified,
  }
}

///|
/// Validates names/duplicates and copies entries. Child contracts are already
/// admitted and shared; limits cover this field-set construction, not children.
pub fn rows(
  fields : Array[(@row.FieldName, @value.Contract?)],
  field_set~ : FieldSet,
  max_fields~ : Int,
  max_name_bytes~ : Int,
) -> Result[Knowledge, @row.Issue] {
  if max_fields < 0 || max_name_bytes < 0 {
    return Err(@row.InvalidLimits)
  }
  if fields.length() > max_fields {
    return Err(@row.LimitExceeded)
  }
  let placeholder = @value.primitive(NumberType, nullable=false)
  // Reuse the exact provenance-aware name admission without exposing a
  // placeholder as inferred type evidence.
  let admitted = match
    @row.from_fields(
      fields.map(pair => (pair.0, pair.1.unwrap_or(placeholder))),
      max_fields~,
      max_name_bytes~,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let types : Map[String, @value.Contract?] = Map([])
  let mut all_typed = true
  for (name, contract) in fields {
    types[@row.reference_name(name)] = contract
    if contract is None {
      all_typed = false
    }
  }
  let entries = @row.fields(admitted).map(f => {
    name: f.name,
    contract: types[@row.reference_name(f.name)],
  })
  Ok({
    field_set,
    entries,
    complete: if field_set == Closed && all_typed {
      Some(admitted)
    } else {
      None
    },
    conditional: None,
    has_qualified_fields: @row.as_object(admitted) is None,
  })
}

///|
pub fn field_set(rows : Knowledge) -> FieldSet {
  rows.field_set
}

///|
pub fn field_count(rows : Knowledge) -> Int {
  rows.entries.length()
}

///|
pub fn field_at(rows : Knowledge, index : Int) -> Field? {
  if index < 0 || index >= rows.entries.length() {
    None
  } else {
    Some(rows.entries[index])
  }
}

///|
pub fn fields(rows : Knowledge) -> Array[Field] {
  rows.entries.copy()
}

///|
pub fn complete_schema(rows : Knowledge) -> @row.Schema? {
  rows.complete
}

///|
pub fn conditional_schema(rows : Knowledge) -> @row.ConditionalSchema? {
  rows.conditional
}

///|
pub fn lookup(rows : Knowledge, name : @row.FieldName) -> Lookup {
  let spelling = @row.reference_name(name)
  let mut lo = 0
  let mut hi = rows.entries.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let candidate = @row.reference_name(rows.entries[mid].name)
    if @canonical.compare_utf16(candidate, spelling) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < rows.entries.length() && rows.entries[lo].name == name {
    if rows.conditional is Some(schema) &&
      @row.presence_lookup(schema, name) is @row.ConditionallyPresent(_) {
      return Unknown
    }
    Present(rows.entries[lo])
  } else if rows.field_set == Closed {
    Absent
  } else {
    Unknown
  }
}
