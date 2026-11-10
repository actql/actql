///|
// Shape/kind admission belongs to the existing closed schema. Typed evidence
// lists additionally require canonical kind/CID order, not only uniqueItems.
fn lookup_lifecycle_order_valid(value : @json.CanonicalValue) -> Bool {
  guard @json.object_field(value, "lifecycle_evidence")
    is Some(@json.Array(entries)) else {
    return false
  }
  let mut previous = ""
  let mut accounting = 0
  for entry in @json.array_values(entries) {
    guard evidence_string(entry, "kind") is Some(kind) &&
      evidence_string(entry, "cid") is Some(cid) else {
      return false
    }
    let key = kind + ":" + cid
    if @canonical.compare_utf16(key, previous) <= 0 {
      return false
    }
    previous = key
    if kind == "accounting" {
      accounting += 1
    }
  }
  accounting == 1
}

///|
fn lookup_cid_set_order_valid(
  value : @json.CanonicalValue,
  field : String,
) -> Bool {
  guard @json.object_field(value, field) is Some(@json.Array(entries)) else {
    return false
  }
  let mut previous = ""
  for entry in @json.array_values(entries) {
    guard entry is @json.String(cid) else { return false }
    if @canonical.compare_utf16(cid, previous) <= 0 {
      return false
    }
    previous = cid
  }
  true
}
