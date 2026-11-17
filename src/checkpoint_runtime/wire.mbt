///|
fn document_limits(limits : WireLimits) -> @document.Limits {
  {
    max_wire_bytes: limits.max_wire_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  }
}

///|
fn valid_limits(limits : WireLimits) -> Bool {
  @document.valid_limits(document_limits(limits))
}

///|
fn valid_cid(value : String) -> Bool {
  @document.valid_cid(value)
}

///|
fn valid_timestamp(value : String) -> Bool {
  @document.valid_timestamp(value)
}

///|
fn canonical_text(value : String) -> Bool {
  @document.canonical_text(value)
}

///|
fn valid_base64(value : String) -> Bool {
  @document.valid_base64(value)
}

///|
fn parse_wire(wire : String, limits : WireLimits) -> @json.CanonicalValue? {
  @document.parse_wire(wire, document_limits(limits))
}

///|
fn canonical_of(json : Json, limits : WireLimits) -> @json.CanonicalValue? {
  @document.canonical_of(json, document_limits(limits))
}

///|
fn cid_of(value : @json.CanonicalValue, limits : WireLimits) -> String? {
  @document.cid_of(value, document_limits(limits))
}

///|
fn wire_of(value : @json.CanonicalValue, limits : WireLimits) -> String? {
  @document.wire_of(value, document_limits(limits))
}

///|
priv enum ShapeIssue {
  Unknown(String)
  Missing(String)
  NotObject
}

///|
fn closed_shape(
  value : @json.CanonicalValue,
  required : Array[String],
  optional : Array[String],
) -> ShapeIssue? {
  match @document.closed_shape(value, required, optional) {
    Some(@document.Unknown(key)) => Some(Unknown(key))
    Some(@document.Missing(key)) => Some(Missing(key))
    Some(@document.NotObject) => Some(NotObject)
    None => None
  }
}

///|
fn string_field(value : @json.CanonicalValue, key : String) -> String? {
  @document.string_field(value, key)
}

///|
fn string_list_field(
  value : @json.CanonicalValue,
  key : String,
) -> Array[String]? {
  @document.string_list_field(value, key)
}

///|
fn string_array_json(values : Array[String]) -> Json {
  @document.string_array_json(values)
}
