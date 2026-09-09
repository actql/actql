///|
/// Incremental exact-key admission. Domain decoders interleave this check with
/// value validation so that a later duplicate cannot hide an earlier bad value.
/// Keys are not normalized here; normalization belongs to the input boundary.
/// Callers limit distinct key count and total retained text. Duplicate rejection
/// does not poison the state or insert a second copy.
struct KeyAdmission {
  seen : Map[String, Unit]
}

///|
pub fn key_admission() -> KeyAdmission {
  { seen: Map([]), }
}

///|
pub fn admit_key(keys : KeyAdmission, name : String) -> Bool {
  if keys.seen.contains(name) {
    false
  } else {
    keys.seen[name] = ()
    true
  }
}
