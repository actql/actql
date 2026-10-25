///|
// A lexical envelope guard, not policy admission. Closed canonical readers
// still decide meanings, required fields, positivity, integrity and defaults.
fn closed_values_policy_ascii(text : String, version : Bool) -> Bool {
  for i in 0..<text.length() {
    let c = text[i].to_int()
    if !((c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 95 ||
      (version && (c == 45 || c == 46 || c == 47))) {
      return false
    }
  }
  true
}

///|
fn closed_values_policy_scalar_body(
  body : @decode.Cursor,
  fields : Int,
  key_units : Int,
  longest_key : Int,
  version_units : Int,
) -> Bool {
  guard @decode.object_length(body) is Some(count) && count <= fields else {
    return false
  }
  let mut remaining = key_units
  let mut version_seen = false
  for i in 0..<count {
    let (key, value) = @decode.field_at(body, i).unwrap()
    if key.length() > longest_key ||
      key.length() > remaining ||
      !closed_values_policy_ascii(key, false) {
      return false
    }
    remaining -= key.length()
    if key == "version" {
      if version_seen {
        return false
      }
      version_seen = true
      guard @decode.text(value) is Ok(text) &&
        text.length() <= version_units &&
        closed_values_policy_ascii(text, true) else {
        return false
      }
    } else {
      guard @decode.finite_number(value) is Ok(_) else { return false }
    }
  }
  version_seen
}

///|
/// Establish fixed scalar-wire envelopes from the original installed Cursor
/// BEFORE read_capacity/read_text_time can serialize that Cursor. Otherwise a
/// huge invalid field could allocate its wire before the closed reader rejects.
/// Unknown policy components stay on the ordinary preparation path; this guard
/// is eligibility for the first planned route, not a new language restriction.
/// At most3 component keys and27/6/7 body fields are inspected, with bounded
/// ASCII spellings. No ObjectView, parser, normalization or wire is allocated.
pub fn closed_values_policy_shape(environment : WireEnvironment) -> Bool {
  guard @decode.object_length(environment.policy) is Some(count) && count <= 3 else {
    return false
  }
  let mut capacity = false
  let mut text_time = false
  let mut lookup = false
  for i in 0..<count {
    let (name, body) = @decode.field_at(environment.policy, i).unwrap()
    match name {
      "capacity" => {
        if capacity || !closed_values_policy_scalar_body(body, 27, 645, 33, 30) {
          return false
        }
        capacity = true
      }
      "text_time_evaluation" => {
        if text_time || !closed_values_policy_scalar_body(body, 6, 96, 31, 31) {
          return false
        }
        text_time = true
      }
      "lookup_execution" => {
        // Only a hashing writer is used here, with8 nodes/depth1. The scalar
        // spelling guard bounds its scanned keys without a fresh wire copy.
        if lookup || !closed_values_policy_scalar_body(body, 7, 256, 40, 40) {
          return false
        }
        lookup = true
      }
      _ => return false
    }
  }
  capacity
}
