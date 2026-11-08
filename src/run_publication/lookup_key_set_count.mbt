///|
/// Pure DATA projection from the already admitted closed key-set envelope.
/// This does not restore reference capabilities or grant a Source request.
pub fn lookup_request_key_set_tuple_count(keys : PublicationContract) -> Int? {
  guard keys.name == "request_key_set" &&
    @json.object_field(keys.value, "tuples") is Some(@json.Array(tuples)) else {
    return None
  }
  Some(@json.array_count(tuples))
}
