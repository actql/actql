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
  has_qualified_fields : Bool
}

///|
pub fn unknown_rows() -> Knowledge {
  { field_set: Open, entries: [], complete: None, has_qualified_fields: false, }
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
    has_qualified_fields: @row.as_object(schema) is None,
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
    Present(rows.entries[lo])
  } else if rows.field_set == Closed {
    Absent
  } else {
    Unknown
  }
}
