///|
/// Domain-checked data, not evidence of authority or operation admission.
pub struct CheckedValue {
  contract : @contract.Contract
  value : Value
}

///|
pub enum Value {
  Null
  Boolean(Bool)
  Number(Double)
  Text(String)
  Date(String)
  Timestamp(String)
  Decimal(DecimalValue)
  Array(FrozenArray[Value])
  Object(FrozenArray[(String, Value)])
  Vector(FrozenArray[Double])
  Reference(ReferenceValue)
}

///|
pub struct DecimalValue {
  coefficient : String
  precision : Int
  scale : Int
}

///|
struct FrozenArray[T] {
  values : Array[T]
}

///|
/// Package-owned construction prevents mutation after the final value is
/// exposed without requiring a second whole-vector copy.
struct VectorBuilder {
  values : Array[Double]
  expected : Int
  mut open : Bool
}

///|
/// Build an immutable array from values that have already been admitted.
/// The detached backing prevents later mutation of the caller's collection.
pub fn array_value(values : Array[Value]) -> Value {
  Array({ values: values.copy(), })
}

///|
pub fn null_value() -> Value {
  Null
}

///|
/// Build an immutable closed object from already admitted, distinct fields.
/// Canonical object order is independent of authored projection order.
pub fn object_value(entries : Array[(String, Value)]) -> Value? {
  let values = entries.copy()
  let seen : Map[String, Bool] = Map([])
  for (name, _) in values {
    if seen.contains(name) {
      return None
    }
    match @canonical.normalize_nfc_lf(name) {
      Ok(normalized) => if normalized != name { return None }
      Err(_) => return None
    }
    seen[name] = true
  }
  values.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  Some(Object({ values, }))
}

///|
/// Build an admitted Boolean from an already typed execution value.
pub fn boolean_value(value : Bool) -> Value {
  Boolean(value)
}

///|
/// Reject non-finite and negative-zero values at the construction boundary.
pub fn number_value(value : Double) -> Value? {
  if value.is_nan() || value.is_inf() || (value == 0.0 && 1.0 / value < 0.0) {
    None
  } else {
    Some(Number(value))
  }
}

///|
pub fn prepare_vector_value(dimensions : Int) -> VectorBuilder? {
  if dimensions < 1 {
    None
  } else {
    Some({ values: [], expected: dimensions, open: true, })
  }
}

///|
pub fn append_vector_component(
  builder : VectorBuilder,
  component : Double,
) -> Bool {
  if !builder.open || builder.values.length() >= builder.expected {
    return false
  }
  if component.is_nan() ||
    component.is_inf() ||
    (component == 0.0 && 1.0 / component < 0.0) {
    builder.open = false
    builder.values.clear()
    return false
  }
  builder.values.push(component)
  true
}

///|
fn finish_vector_value(builder : VectorBuilder) -> Value? {
  if !builder.open || builder.values.length() != builder.expected {
    return None
  }
  builder.open = false
  Some(Vector({ values: builder.values, }))
}

///|
/// Finish a vector and bind it only to its exact checked vector contract.
pub fn finish_checked_vector_value(
  builder : VectorBuilder,
  contract : @contract.Contract,
) -> CheckedValue? {
  guard contract.shape is @contract.Vector(dimensions~) &&
    !contract.nullable &&
    dimensions == builder.expected.to_double() &&
    finish_vector_value(builder) is Some(value) else {
    return None
  }
  Some({ contract, value, })
}

///|
pub fn cancel_vector_value(builder : VectorBuilder) -> Bool {
  if !builder.open {
    return false
  }
  builder.open = false
  builder.values.clear()
  true
}

///|
/// Recheck Unicode, byte and canonical-text invariants before construction.
pub fn text_value(value : String, max_utf8_bytes : Int) -> Value? {
  if max_utf8_bytes < 0 ||
    @scalar.admit_utf8_length(value, max_utf8_bytes) is Err(_) {
    return None
  }
  match @canonical.normalize_nfc_lf(value) {
    Ok(normalized) => if normalized == value { Some(Text(value)) } else { None }
    Err(_) => None
  }
}

///|
pub fn[T] elements(value : FrozenArray[T]) -> Array[T] {
  value.values.copy()
}

///|
/// Read-only indexed access without allocating a detached array.
pub fn[T] element_at(value : FrozenArray[T], index : Int) -> T? {
  value.values.get(index)
}

///|
pub fn[T] element_count(value : FrozenArray[T]) -> Int {
  value.values.length()
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  WrongType
  UnexpectedNull
  InvalidNumber
  InvalidUnicode
  NonCanonicalText
  InvalidDecimal
  InvalidDate
  InvalidTimestamp
  StringConstraint
  ArrayConstraint
  VectorDimension
  UnsupportedReference
  InvalidReference
  UnauthorizedReference
  BudgetExceeded
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  Decode(@decode.Issue)
  ValueIssue(IssueKind, path~ : Array[@decode.PathSegment], span~ : @span.Span)
} derive(Eq, Debug)

///|
priv suberror Abort {
  Abort(Issue)
}
