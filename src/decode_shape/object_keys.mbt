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
  if object_keys_use_linear_scan(
      keys.length(),
      required.length(),
      allowed.length(),
    ) {
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

///|
fn object_keys_use_linear_scan(
  keys : Int,
  required : Int,
  allowed : Int,
) -> Bool {
  keys <= 8 && required <= 8 && allowed <= 8
}

///|
/// Constructor DATA for the same selected key-check path, not a key verdict.
/// Pairs and map entries borrow the supplied original names. All maps are
/// counted together, including partially built maps on refusal.
pub(all) struct ObjectKeyConstructionCounts {
  maps : Int
  map_entries : Int64
  pair_arrays : Int
  pairs : Int64
} derive(Eq, Debug)

///|
pub fn object_key_construction_counts(
  keys : Int,
  required : Int,
  allowed : Int,
) -> ObjectKeyConstructionCounts? {
  if keys < 0 || required < 0 || allowed < 0 {
    return None
  }
  if object_keys_use_linear_scan(keys, required, allowed) {
    Some({ maps: 0, map_entries: 0L, pair_arrays: 0, pairs: 0L, })
  } else {
    Some({
      maps: 3,
      map_entries: 2L * keys.to_int64() + allowed.to_int64(),
      pair_arrays: 2,
      pairs: keys.to_int64() + allowed.to_int64(),
    })
  }
}
