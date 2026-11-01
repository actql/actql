///|
/// Output spelling/topology bounds from the SAME closed Command document
/// builders. This is fixed template DATA, never an issued Command, accepted
/// schema, Catalog, capacity or permission. Dynamic authored strings are
/// borrowed; this routine does not parse them or compute their identities.
pub(all) struct RangeDeclarationConstructionBounds {
  bundle_bytes : Int
  bundle_nodes : Int
  bundle_depth : Int
}

///|
fn range_template_nodes(value : Json) -> Int {
  match value {
    Array(values) =>
      1 + values.fold(init=0, (n, value) => n + range_template_nodes(value))
    Object(fields) =>
      1 +
      fields
      .values()
      .fold(init=0, (n, value) => n + range_template_nodes(value))
    _ => 1
  }
}

///|
fn range_template_depth(value : Json) -> Int {
  match value {
    Array(values) =>
      1 +
      values.fold(init=0, (n, value) => Int::max(n, range_template_depth(value)))
    Object(fields) =>
      1 +
      fields
      .values()
      .fold(init=0, (n, value) => Int::max(n, range_template_depth(value)))
    _ => 0
  }
}

///|
fn range_declaration_template(clear : Bool, one_field : Bool) -> Json {
  let connector_id = "original-connector"
  let (input_id, output_id, command_id, operation) = range_declaration_names(
    connector_id, clear,
  )
  let fields : Map[String, Json] = Map([])
  if one_field {
    fields["original-field"] = { "type": "boolean", "nullable": false }
  }
  let input_fields = if clear {
    Json::object(Map([]))
  } else {
    range_input_fields_document(fields, 2147483647)
  }
  let cid = "sha256:" + "0".repeat(64)
  let input = range_contract_document(input_id, "command_input", input_fields)
  let output = range_contract_document(
    output_id,
    "command_output",
    range_output_fields_document(clear),
  )
  if input is Object(fields) {
    fields["cid"] = cid.to_json()
  }
  if output is Object(fields) {
    fields["cid"] = cid.to_json()
  }
  let command = range_command_document(
    connector_id, command_id, input, output, input_fields, operation,
  )
  if command is Object(fields) {
    fields["contract_cid"] = cid.to_json()
  }
  range_command_bundle_document(
    command,
    input,
    output,
    command_id,
    cid,
    command.stringify(),
  )
}

///|
pub fn range_declaration_construction_bounds(
  schema_bytes : Int,
  columns : Int,
  connector_bytes : Int,
) -> RangeDeclarationConstructionBounds? {
  if schema_bytes < 1 || columns < 1 || columns > 64 || connector_bytes < 1 {
    return None
  }
  let mut bytes = 0L
  let mut nodes = 0
  let mut depth = 0
  for clear in [false, true] {
    let empty = range_declaration_template(clear, false)
    let one = range_declaration_template(clear, true)
    let empty_wire = empty.stringify()
    let one_wire = one.stringify()
    let fixed = empty_wire.length().to_int64()
    let field = (one_wire.length() - empty_wire.length()).to_int64()
    let connectors = one_wire.split("original-connector").count().to_int64() -
      1L
    let names = one_wire.split("original-field").count().to_int64() - 1L
    // Every original column-name unit is already in schema_bytes. A JSON
    // escape needs <=6 units, and quoting that escaped Command in installed
    // body needs <=7; use7 for each actual template occurrence. Connector
    // spellings repeat only where the shared documents place that marker.
    // Keep the markers too: no subtraction assumes an admitted input width.
    let total = fixed +
      field * columns.to_int64() +
      7L * connectors * connector_bytes.to_int64() +
      7L * names * schema_bytes.to_int64()
    bytes = Int64::max(bytes, total)
    depth = Int::max(depth, range_template_depth(one))
    nodes = Int::max(
      nodes,
      range_template_nodes(empty) +
      (range_template_nodes(one) - range_template_nodes(empty)) * columns,
    )
  }
  if bytes > 2147483647L {
    return None
  }
  Some({
    bundle_bytes: bytes.to_int(),
    bundle_nodes: nodes,
    bundle_depth: depth,
  })
}

///|
/// Fixed shape DATA from the SAME original reference/identity builders. The
/// supplied byte counts describe checked installation strings; no identity is
/// hashed, no original reference is created, and no authorization is issued.
pub(all) struct RangeReferenceConstructionBounds {
  identity_bytes : Int
  identity_nodes : Int
  identity_depth : Int
  reference_bytes : Int
  reference_nodes : Int
}

///|
pub fn range_reference_construction_bounds(
  origin_bytes : Int,
  spreadsheet_bytes : Int,
) -> RangeReferenceConstructionBounds? {
  if origin_bytes < 1 || spreadsheet_bytes < 1 {
    return None
  }
  let provider = range_provider_identity_document("", "")
  let identity = range_identity_document({
    sheet_id: 2147483647,
    start_row: 2147483647,
    end_row: 2147483647,
    start_column: 2147483647,
    end_column: 2147483647,
  })
  // NFC output expands by <=8 UTF16 units per original decoded unit. JSON
  // spelling then needs <=6; input bytes bound the original UTF16 units.
  // This is constructor geometry, not a changed configuration text policy.
  let bytes = provider.stringify().length().to_int64() +
    identity.stringify().length().to_int64() +
    48L * (origin_bytes.to_int64() + spreadsheet_bytes.to_int64())
  if bytes > 2147483647L {
    return None
  }
  let cid = "sha256:" + "0".repeat(64)
  let reference = range_reference_document(cid, cid, cid, cid)
  Some({
    identity_bytes: bytes.to_int(),
    identity_nodes: range_template_nodes(provider) + range_template_nodes(identity),
    identity_depth: Int::max(range_template_depth(provider), range_template_depth(identity)),
    reference_bytes: reference.stringify().length(),
    reference_nodes: range_template_nodes(reference),
  })
}
