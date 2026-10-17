///|
/// None and Some(0) distinguish unrestricted Text from an empty non-null
/// domain. The vector itself stays behind the existing Contract owner.
pub fn text_enumerant_count(bounds : TextLimits) -> Int? {
  bounds.enumeration.map(value => value.values.length())
}

///|
pub fn text_enumerant_at(bounds : TextLimits, index : Int) -> String? {
  match bounds.enumeration {
    Some(value) => value.values.get(index)
    None => None
  }
}

///|
fn read_text_enumeration(
  view : @decode.ObjectView,
  budget : Budget,
  depth : Int,
) -> TextEnumeration? raise Abort {
  match @decode.field(view, "enum") {
    Missing => None
    ExplicitNull => invalid(required(view, "enum"), InvalidRange)
    Present(cursor) => {
      guard @decode.array_length(cursor) is Some(count) else {
        return invalid(cursor, InvalidRange)
      }
      if budget.nodes <= budget.scheduled ||
        count > budget.nodes - budget.scheduled - 1 ||
        depth >= budget.max_depth ||
        (count != 0 && depth + 1 >= budget.max_depth) {
        invalid(cursor, BudgetExceeded)
      }
      // One array and every entry, including duplicates/empty strings. The
      // original exact data spelling is not an NFC/LF identifier spelling.
      budget.nodes -= count + 1
      let values : Array[String] = []
      for index in 0..<count {
        let child = @decode.element_at(cursor, index).unwrap()
        let value = decoded(@decode.text(child))
        match @scalar.admit_utf8_length(value, budget.text) {
          Ok(size) => budget.text -= size
          Err(@scalar.MalformedUtf16(_)) => invalid(child, InvalidUnicode)
          Err(_) => invalid(child, BudgetExceeded)
        }
        values.push(value)
      }
      Some({ values, })
    }
  }
}

///|
priv struct EnumerationWork {
  mut remaining : Int
}

///|
fn enum_charge(work : EnumerationWork) -> Unit raise RelationError {
  if work.remaining == 0 {
    raise RelationLimit
  }
  work.remaining -= 1
}

///|
// One metadata transition or up to 64 exact UTF-16 comparisons per unit.
fn enum_text_equal(
  a : String,
  b : String,
  work : EnumerationWork,
) -> Bool raise RelationError {
  enum_charge(work)
  if a.length() != b.length() {
    return false
  }
  for index in 0..<a.length() {
    if index > 0 && index % 64 == 0 {
      enum_charge(work)
    }
    if a[index] != b[index] {
      return false
    }
  }
  true
}

///|
fn enum_extents_allow(
  bounds : TextLimits,
  value : String,
  work : EnumerationWork,
) -> Bool raise RelationError {
  enum_charge(work)
  let mut index = 0
  let mut characters = 0L
  let mut bytes = 0L
  let mut quantum = 0
  while index < value.length() {
    if quantum >= 64 {
      enum_charge(work)
      quantum = 0
    }
    // Enumeration construction already checked Unicode. Retain exact scalar
    // spelling and count without a second normalized/canonical String.
    let unit = value[index].to_int()
    let width = if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else if unit >= 0xd800 && unit <= 0xdbff {
      index += 1
      quantum += 1
      4
    } else {
      3
    }
    index += 1
    quantum += 1
    characters += 1L
    bytes += width.to_int64()
  }
  (bounds.min_length is None || characters >= bounds.min_length.unwrap()) &&
  (
    bounds.max_codepoints is None ||
    characters <= bounds.max_codepoints.unwrap()
  ) &&
  (bounds.max_utf8_bytes is None || bytes <= bounds.max_utf8_bytes.unwrap())
}

///|
fn enum_contains(
  enumeration : TextEnumeration,
  value : String,
  work : EnumerationWork,
) -> Bool raise RelationError {
  for candidate in enumeration.values {
    if enum_text_equal(value, candidate, work) {
      return true
    }
  }
  false
}

///|
fn text_assignment(
  actual : TextLimits,
  expected : TextLimits,
  remaining : Int,
) -> (Bool, Int) raise RelationError {
  let work = { remaining, }
  match actual.enumeration {
    None =>
      (
        expected.enumeration is None &&
        lower_assign(actual.min_length, expected.min_length) &&
        upper_assign(actual.max_codepoints, expected.max_codepoints) &&
        upper_assign(actual.max_utf8_bytes, expected.max_utf8_bytes),
        remaining,
      )
    Some(enumeration) => {
      for value in enumeration.values {
        if enum_extents_allow(actual, value, work) {
          if !enum_extents_allow(expected, value, work) {
            return (false, work.remaining)
          }
          if expected.enumeration is Some(target) &&
            !enum_contains(target, value, work) {
            return (false, work.remaining)
          }
        }
      }
      (true, work.remaining)
    }
  }
}

///|
fn join_text_enumeration(
  a : TextLimits,
  b : TextLimits,
  remaining : Int,
) -> (TextEnumeration?, Int) raise RelationError {
  match (a.enumeration, b.enumeration) {
    (Some(left), Some(right)) => {
      let work = { remaining, }
      let values : Array[String] = []
      // Preserve all left occurrences; no input is sorted or deduplicated.
      for value in left.values {
        enum_charge(work)
        values.push(value)
      }
      let result = { values, }
      for value in right.values {
        enum_charge(work)
        if !enum_contains(result, value, work) {
          result.values.push(value)
        }
      }
      (Some(result), work.remaining)
    }
    _ => (None, remaining)
  }
}
