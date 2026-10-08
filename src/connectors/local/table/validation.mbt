///|
fn table_name_valid(value : String) -> Bool {
  let mut count = 0
  for c in value.iter() {
    if c == '\u{0000}' || c == '\r' || c == '\n' {
      return false
    }
    count += 1
  }
  if count < 1 || count > 256 || value.length() > 1024 {
    return false
  }
  match @canonical.normalize_nfc_lf(value) {
    Ok(normalized) =>
      normalized == value && @utf8.encode(value).length() <= 1024
    Err(_) => false
  }
}

///|
fn ledger_string(value : @json.CanonicalValue, field : String) -> String? {
  match @json.object_field(value, field) {
    Some(@json.String(v)) => Some(v)
    _ => None
  }
}

///|
fn ledger_cid(value : @json.CanonicalValue, field : String) -> String? {
  guard ledger_string(value, field) is Some(v) else { return None }
  if v.length() != 71 || !v.has_prefix("sha256:") {
    return None
  }
  for i in 7..<71 {
    let c = v[i]
    if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return None
    }
  }
  Some(v)
}

///|
fn ledger_integer(
  value : @json.CanonicalValue,
  field : String,
  minimum : Int64,
) -> Int64? {
  match @json.object_field(value, field) {
    Some(@json.Number(v)) if v >= minimum.to_double() &&
      v <= 9007199254740991.0 &&
      v.to_int64().to_double() == v => Some(v.to_int64())
    _ => None
  }
}
