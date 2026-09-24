///|
/// Unbounded primitive contracts; this does not infer a type from a value.
pub(all) enum Primitive {
  StringType
  NumberType
  BooleanType
  DateType
  TimestampType
  JsonType
} derive(Eq, Debug)

///|
pub fn primitive(kind : Primitive, nullable~ : Bool) -> Contract {
  let shape = match kind {
    StringType =>
      Text({ min_length: None, max_codepoints: None, max_utf8_bytes: None, })
    NumberType => Number
    BooleanType => Boolean
    DateType => Date
    TimestampType => Timestamp
    JsonType => Json
  }
  { shape, nullable, }
}

///|
/// Changes only root nullability, preserving all nested constraints.
pub fn with_nullability(value : Contract, nullable : Bool) -> Contract {
  { ..value, nullable, }
}

///|
/// Root nullability of an admitted contract. Nested field nullability is
/// inspected through the corresponding nested contract instead.
pub fn contract_nullable(value : Contract) -> Bool {
  value.nullable
}

///|
/// The kind of a non-null value-level ResourceRef. This does not establish
/// that the reference exists or that the caller may use its target.
pub fn nonnull_resource_ref_kind(value : Contract) -> String? {
  if value.nullable {
    return None
  }
  match value.shape {
    ResourceRef(resource_kind~) => Some(resource_kind)
    _ => None
  }
}

///|
fn valid_size_bound(value : Int64?) -> Bool {
  match value {
    None => true
    Some(n) => n >= 0L && n <= 9007199254740991L
  }
}

///|
pub fn string_contract(
  nullable~ : Bool,
  min_length? : Int64? = None,
  max_codepoints? : Int64? = None,
  max_utf8_bytes? : Int64? = None,
) -> Contract? {
  if !valid_size_bound(min_length) ||
    !valid_size_bound(max_codepoints) ||
    !valid_size_bound(max_utf8_bytes) {
    return None
  }
  Some({
    nullable,
    shape: Text({ min_length, max_codepoints, max_utf8_bytes, }),
  })
}

///|
pub fn decimal_contract(
  precision : Int,
  scale : Int,
  nullable~ : Bool,
) -> Contract? {
  if precision < 1 || precision > 38 || scale < 0 || scale > precision {
    return None
  }
  Some({ nullable, shape: Decimal(precision~, scale~), })
}

///|
pub fn vector_contract(dimensions : Double, nullable~ : Bool) -> Contract? {
  if dimensions < 1.0 || @scalar.read_integer_number(dimensions) is None {
    return None
  }
  Some({ nullable, shape: Vector(dimensions~), })
}

///|
pub fn array_contract(
  items : Contract,
  nullable~ : Bool,
  max_items? : Int64? = None,
) -> Contract? {
  if !valid_size_bound(max_items) {
    return None
  }
  Some({ nullable, shape: Array(items, max_items~), })
}

///|
pub(all) enum ConstructionIssue {
  InvalidConstructionLimits
  ConstructionLimit
  InvalidConstructionName(String)
  NonCanonicalConstructionName(String)
  InvalidConstructionUnicode
  DuplicateConstructionName(String)
} derive(Eq, Debug)

///|
/// Assembles already admitted children without traversing them again. Limits
/// bound this call's fields and UTF-8 names, not the resulting recursive tree.
/// The caller accounts for cumulative tree work. Names are checked, not repaired.
pub fn object_contract(
  entries : Array[(String, Contract)],
  nullable~ : Bool,
  max_fields~ : Int,
  max_name_bytes~ : Int,
) -> Result[Contract, ConstructionIssue] {
  if max_fields < 0 || max_name_bytes < 0 {
    return Err(InvalidConstructionLimits)
  }
  if entries.length() > max_fields {
    return Err(ConstructionLimit)
  }
  let mut remaining = max_name_bytes
  let seen : Map[String, Bool] = Map([])
  let values : Array[Field] = []
  for (name, contract) in entries {
    match @scalar.admit_utf8_length(name, remaining) {
      Ok(size) => remaining -= size
      Err(@scalar.MalformedUtf16(_)) => return Err(InvalidConstructionUnicode)
      Err(_) => return Err(ConstructionLimit)
    }
    match @canonical.normalize_nfc_lf(name) {
      Ok(normalized) =>
        if normalized != name {
          return Err(NonCanonicalConstructionName(name))
        }
      Err(_) => return Err(InvalidConstructionUnicode)
    }
    if !nonblank(name) ||
      name.contains(".") ||
      name == "__cid" ||
      name.has_prefix("__actql_") {
      return Err(InvalidConstructionName(name))
    }
    if seen.contains(name) {
      return Err(DuplicateConstructionName(name))
    }
    seen[name] = true
    values.push({ name, contract, })
  }
  values.sort_by((a, b) => @canonical.compare_utf16(a.name, b.name))
  Ok({ nullable, shape: Object({ values, }), })
}

///|
/// Read-only indexed access; unlike fields(), this does not copy the field array.
pub fn field_at(fields : Fields, index : Int) -> Field? {
  if index < 0 || index >= fields.values.length() {
    None
  } else {
    Some(fields.values[index])
  }
}

///|
pub fn field_count(fields : Fields) -> Int {
  fields.values.length()
}
