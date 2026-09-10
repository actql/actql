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
