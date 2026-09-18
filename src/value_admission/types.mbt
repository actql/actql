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
/// Build an immutable array from values that have already been admitted.
/// The detached backing prevents later mutation of the caller's collection.
pub fn array_value(values : Array[Value]) -> Value {
  Array({ values: values.copy(), })
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
