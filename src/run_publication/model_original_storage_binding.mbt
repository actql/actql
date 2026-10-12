///|
/// Check the exact selected Store's three-field serialization separately from
/// the outer canonical evidence preimage. This validates facts, not physical
/// custody, resource restoration or Model dispatch permission.
fn model_original_storage_binding_shape(value : @json.CanonicalValue) -> Bool {
  guard contract_string_from_value(value, "store_authority_cid")
    is Some(authority) else {
    return false
  }
  guard contract_string_from_value(value, "store_contract_wire") is Some(wire) else {
    return false
  }
  let expected = "{\"version\":\"actql-local-publication-store/0.1\",\"isolation\":\"execution-namespace\",\"store_authority_cid\":\"" +
    authority +
    "\"}"
  if wire != expected {
    return false
  }
  guard @sha.text_hex(wire) is Ok(digest) else { return false }
  contract_string_from_value(value, "store_contract_cid") ==
  Some("sha256:" + digest)
}
