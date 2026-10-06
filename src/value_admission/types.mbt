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
  JsonData(Value)
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
/// Package-owned construction prevents mutation after an array is exposed
/// without requiring a second whole-array copy at completion.
struct ArrayBuilder {
  values : Array[Value]
  expected : Int
  mut open : Bool
}

///|
/// Package-owned construction for a canonical closed object. Fields must be
/// appended in strict UTF-16 name order, so finishing never sorts or copies.
struct ObjectBuilder {
  values : Array[(String, Value)]
  expected : Int
  mut previous : String?
  mut open : Bool
  data_keys : Bool
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
pub fn prepare_array_value(length : Int) -> ArrayBuilder? {
  if length < 0 {
    None
  } else {
    Some({ values: [], expected: length, open: true, })
  }
}

///|
pub fn append_array_item(builder : ArrayBuilder, value : Value) -> Bool {
  if !builder.open || builder.values.length() >= builder.expected {
    false
  } else {
    builder.values.push(value)
    true
  }
}

///|
pub fn finish_array_value(builder : ArrayBuilder) -> Value? {
  if !builder.open || builder.values.length() != builder.expected {
    None
  } else {
    builder.open = false
    Some(Array({ values: builder.values, }))
  }
}

///|
/// Seal a bounded array at its current length without copying its backing.
pub fn finish_bounded_array_value(builder : ArrayBuilder) -> Value? {
  if !builder.open {
    None
  } else {
    builder.open = false
    Some(Array({ values: builder.values, }))
  }
}

///|
pub fn cancel_array_value(builder : ArrayBuilder) -> Bool {
  if !builder.open {
    false
  } else {
    builder.open = false
    builder.values.clear()
    true
  }
}

///|
pub fn prepare_object_value(
  length : Int,
  data_keys? : Bool = false,
) -> ObjectBuilder? {
  if length < 0 {
    None
  } else {
    Some({
      values: [],
      expected: length,
      previous: None,
      open: true,
      data_keys,
    })
  }
}

///|
pub fn append_object_field(
  builder : ObjectBuilder,
  name : String,
  value : Value,
) -> Bool {
  if !builder.open || builder.values.length() >= builder.expected {
    return false
  }
  guard (if builder.data_keys {
      @scalar.admit_utf8_length(name, 2147483647) is Ok(_)
    } else {
      @canonical.normalize_nfc_lf(name) == Ok(name)
    }) &&
    (
      builder.previous is None ||
      @canonical.compare_utf16(builder.previous.unwrap(), name) < 0
    ) else {
    builder.open = false
    builder.values.clear()
    return false
  }
  builder.values.push((name, value))
  builder.previous = Some(name)
  true
}

///|
pub fn finish_object_value(builder : ObjectBuilder) -> Value? {
  if !builder.open || builder.values.length() != builder.expected {
    None
  } else {
    builder.open = false
    Some(Object({ values: builder.values, }))
  }
}

///|
pub fn cancel_object_value(builder : ObjectBuilder) -> Bool {
  if !builder.open {
    false
  } else {
    builder.open = false
    builder.values.clear()
    true
  }
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
/// Recheck Unicode and exact value-byte bounds without normalizing data.
pub fn text_value(value : String, max_utf8_bytes : Int) -> Value? {
  if max_utf8_bytes < 0 ||
    @scalar.admit_utf8_length(value, max_utf8_bytes) is Err(_) {
    return None
  }
  Some(Text(value))
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
