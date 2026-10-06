///|
pub(all) enum Side {
  Left
  Right
} derive(Eq, Debug)

///|
/// A relation field reference, not a nested object path or an identity.
pub(all) enum FieldName {
  Unqualified(String)
  Qualified(Side, String)
} derive(Eq, Debug)

///|
pub struct Field {
  name : FieldName
  contract : @contract.Contract
  presence : Presence
}

///|
/// A row-level existence guarantee, independent of the value's nullability.
pub(all) enum Presence {
  Required
  Conditional
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidRowContract
  InvalidLimits
  LimitExceeded
  DuplicateField(FieldName)
  InvalidField(FieldName, @contract.ConstructionIssue)
} derive(Eq, Debug)

///|
priv enum Representation {
  Flat(@contract.Contract, @contract.Fields)
  Scoped(Array[Entry])
}

///|
priv struct Entry {
  field : Field
  spelling : String
}

///|
/// Complete relation field types only; no row data, key/order or Carrier proof.
struct Schema {
  representation : Representation
  all_required : Bool
  qualified : Bool
}

///|
/// O(1) admission of an already checked non-null object row contract.
pub fn from_object(row : @contract.Contract) -> Result[Schema, Issue] {
  match row.shape {
    @contract.Object(fields) =>
      if row.nullable {
        Err(InvalidRowContract)
      } else {
        Ok({
          representation: Flat(row, fields),
          all_required: true,
          qualified: false,
        })
      }
    _ => Err(InvalidRowContract)
  }
}

///|
/// An explicit projection to an ordinary value contract, never lossy flattening.
pub fn as_object(schema : Schema) -> @contract.Contract? {
  match schema.representation {
    Flat(row, _) => Some(row)
    Scoped(_) => None
  }
}

///|
pub fn field_count(schema : Schema) -> Int {
  match schema.representation {
    Flat(_, fields) => @contract.field_count(fields)
    Scoped(fields) => fields.length()
  }
}

///|
/// Indexed canonical UTF-16 reference order; not authored projection or row order.
pub fn field_at(schema : Schema, index : Int) -> Field? {
  match schema.representation {
    Flat(_, fields) =>
      @contract.field_at(fields, index).map(f => {
        name: Unqualified(f.name),
        contract: f.contract,
        presence: Required,
      })
    Scoped(fields) =>
      if index < 0 || index >= fields.length() {
        None
      } else {
        Some(fields[index].field)
      }
  }
}

///|
pub fn fields(schema : Schema) -> Array[Field] {
  Array::makei(field_count(schema), i => field_at(schema, i).unwrap())
}

///|
pub fn field_reference_name(field : Field) -> String {
  reference_name(field.name)
}

///|
pub fn field_contract(field : Field) -> @contract.Contract {
  field.contract
}

///|
pub fn field_presence(field : Field) -> Presence {
  field.presence
}

///|
pub fn all_fields_required(schema : Schema) -> Bool {
  schema.all_required
}

///|
pub fn has_qualified_fields(schema : Schema) -> Bool {
  schema.qualified
}

///|
/// Unambiguous spelling of a validated field reference, not nested access.
pub fn reference_name(name : FieldName) -> String {
  match name {
    Unqualified(name) => name
    Qualified(Left, name) => "left." + name
    Qualified(Right, name) => "right." + name
  }
}

///|
pub fn lookup(schema : Schema, name : FieldName) -> @contract.Contract? {
  let spelling = reference_name(name)
  match lookup_reference(schema, spelling) {
    Some(f) => if f.name == name { Some(f.contract) } else { None }
    None => None
  }
}

///|
/// Resolves an exact reference spelling against admitted schema entries. Never
/// parses a chain of dots or invents qualification for an authored field.
pub fn lookup_reference(schema : Schema, spelling : String) -> Field? {
  let mut lo = 0
  let mut hi = field_count(schema)
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let candidate = match schema.representation {
      Flat(_, fields) => @contract.field_at(fields, mid).unwrap().name
      Scoped(fields) => fields[mid].spelling
    }
    let order = @canonical.compare_utf16(candidate, spelling)
    if order < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  match field_at(schema, lo) {
    Some(f) => if reference_name(f.name) == spelling { Some(f) } else { None }
    None => None
  }
}

///|
/// Validates/copies field names and shares opaque child contracts. Does not
/// validate a join, extend nullability, infer provenance, or flatten nested names.
/// Limits cover this construction's fields and full UTF-8 reference spellings.
pub fn from_fields(
  entries : Array[(FieldName, @contract.Contract)],
  max_fields~ : Int,
  max_name_bytes~ : Int,
) -> Result[Schema, Issue] {
  from_presence_fields(
    entries.map(e => (e.0, e.1, Required)),
    max_fields~,
    max_name_bytes~,
  )
}

///|
/// Closed finite columns. Conditional means omission is permitted, not NULL,
/// an open field set, or an optional field in an ordinary object value.
pub fn from_presence_fields(
  entries : Array[(FieldName, @contract.Contract, Presence)],
  max_fields~ : Int,
  max_name_bytes~ : Int,
) -> Result[Schema, Issue] {
  if max_fields < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if entries.length() > max_fields {
    return Err(LimitExceeded)
  }
  let mut remaining = max_name_bytes
  let seen : Map[String, Bool] = Map([])
  let output : Array[Entry] = []
  let flat : Array[(String, @contract.Contract)] = []
  let mut qualified = false
  let mut conditional = false
  for (name, contract, presence) in entries {
    if presence == Conditional {
      conditional = true
    }
    let (leaf, prefix) = match name {
      Unqualified(s) => (s, 0)
      Qualified(side, s) => {
        qualified = true
        (s, if side == Left { 5 } else { 6 })
      }
    }
    if prefix > remaining {
      return Err(LimitExceeded)
    }
    let size = match @scalar.admit_utf8_length(leaf, remaining - prefix) {
      Ok(n) => n
      Err(@scalar.MalformedUtf16(_)) =>
        return Err(InvalidField(name, @contract.InvalidConstructionUnicode))
      Err(_) => return Err(LimitExceeded)
    }
    remaining -= size + prefix
    match
      @contract.object_contract(
        [(leaf, contract)],
        nullable=false,
        max_fields=1,
        max_name_bytes=size,
      ) {
      Err(e) => return Err(InvalidField(name, e))
      Ok(_) => ()
    }
    let spelling = reference_name(name)
    if seen.contains(spelling) {
      return Err(DuplicateField(name))
    }
    seen[spelling] = true
    output.push({ field: { name, contract, presence, }, spelling, })
    flat.push((leaf, contract))
  }
  if !qualified && !conditional {
    let row = @contract.object_contract(
      flat,
      nullable=false,
      max_fields~,
      max_name_bytes~,
    ).unwrap()
    from_object(row)
  } else {
    output.sort_by((a, b) => @canonical.compare_utf16(a.spelling, b.spelling))
    Ok({
      representation: Scoped(output),
      all_required: !conditional,
      qualified,
    })
  }
}
