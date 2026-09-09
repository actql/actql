///|
/// Structural object errors keep field names separate from path rendering.
pub(all) enum ObjectKeyIssue {
  MissingKey(String)
  UnknownKey(String)
  DuplicateKey(String)
} derive(Eq, Debug)

///|
/// Collect unknown positions in source order, retaining repeated unknown keys.
/// Unlike check_object_keys, this does not reject missing or duplicate fields:
/// aggregate diagnostic producers intentionally own those separate policies.
pub fn unknown_key_indices(
  keys : Array[String],
  allowed : Array[String],
) -> Array[Int] {
  let result : Array[Int] = []
  if allowed.length() <= 8 {
    for index, key in keys {
      if !allowed.contains(key) {
        result.push(index)
      }
    }
  } else {
    let admitted = Map(allowed.map(key => (key, ())))
    for index, key in keys {
      if !admitted.contains(key) {
        result.push(index)
      }
    }
  }
  result
}

///|
/// Check field names only: missing keys in required order take precedence,
/// then unknown/duplicate keys in source order. Names are compared exactly.
/// Expected linear key operations, plus string hashing/comparison costs.
/// Caller collections are not retained; callers bound key counts and text size.
pub fn check_object_keys(
  keys : Array[String],
  required : Array[String],
  allowed : Array[String],
) -> Result[Unit, ObjectKeyIssue] {
  // Most protocol records are tiny. Keep their bounded scans allocation-free;
  // use indices for wide objects instead of introducing quadratic wide work.
  if keys.length() <= 8 && required.length() <= 8 && allowed.length() <= 8 {
    for name in required {
      if !keys.contains(name) {
        return Err(MissingKey(name))
      }
    }
    for index, name in keys {
      if !allowed.contains(name) {
        return Err(UnknownKey(name))
      }
      for earlier = 0; earlier < index; earlier = earlier + 1 {
        if keys[earlier] == name {
          return Err(DuplicateKey(name))
        }
      }
    }
    return Ok(())
  }
  let present = Map(keys.map(name => (name, ())))
  for name in required {
    if !present.contains(name) {
      return Err(MissingKey(name))
    }
  }
  let admitted = Map(allowed.map(name => (name, ())))
  let seen : Map[String, Unit] = Map([])
  for name in keys {
    if !admitted.contains(name) {
      return Err(UnknownKey(name))
    }
    if seen.contains(name) {
      return Err(DuplicateKey(name))
    }
    seen[name] = ()
  }
  Ok(())
}
