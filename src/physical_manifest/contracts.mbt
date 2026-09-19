///|
priv struct PhysicalField {
  name : String
  kind : String
  precision : String?
  scale : String?
}

///|
/// Canonical interpretation contracts for one physical representation.
pub(all) struct PhysicalContracts {
  schema_contract : String
  schema_contract_cid : String
  view_contract : String
  view_contract_cid : String
}

///|
fn optional_text(
  cursor : @decode.Cursor,
) -> Result[String?, PhysicalManifestIssue] {
  if @decode.is_null(cursor) {
    Ok(None)
  } else {
    match @decode.text(cursor) {
      Ok(value) => Ok(Some(value))
      Err(_) => Err(InvalidManifest)
    }
  }
}

///|
fn read_fields(
  fields_frame : String,
  max_contract_bytes : Int,
) -> Result[Array[PhysicalField], PhysicalManifestIssue] {
  if max_contract_bytes < 0 {
    return Err(InvalidManifest)
  }
  let parsed = match
    @source.parse_json(fields_frame, {
      max_input_bytes: max_contract_bytes,
      max_nodes: max_contract_bytes,
      max_depth: 3,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidManifest)
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: max_contract_bytes,
      max_depth: 3,
      max_string_bytes: max_contract_bytes,
      max_total_string_bytes: max_contract_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidManifest)
  }
  let entries = match @decode.elements(root) {
    Ok(value) => value
    Err(_) => return Err(InvalidManifest)
  }
  let fields : Array[PhysicalField] = []
  for entry in entries {
    let tuple = match @decode.elements(entry) {
      Ok(value) => value
      Err(_) => return Err(InvalidManifest)
    }
    if tuple.length() != 4 {
      return Err(InvalidManifest)
    }
    let name = match @decode.text(tuple[0]) {
      Ok(value) => value
      Err(_) => return Err(InvalidManifest)
    }
    let kind = match @decode.text(tuple[1]) {
      Ok(value) => value
      Err(_) => return Err(InvalidManifest)
    }
    let precision = match optional_text(tuple[2]) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let scale = match optional_text(tuple[3]) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    fields.push({ name, kind, precision, scale, })
  }
  Ok(fields)
}

///|
fn emit_optional_text(
  writer : @encode.Writer,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(text) => @encode.string_value(writer, text)
    None => @encode.null_value(writer)
  }
}

///|
fn encode_schema_contract(
  fields : Array[PhysicalField],
  storage_order : Array[Int],
  max_contract_bytes : Int,
) -> Result[String, PhysicalManifestIssue] {
  let writer = @encode.writer(max_contract_bytes, max_contract_bytes, 3) catch {
    _ => return Err(ManifestLimit)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "fields")
    @encode.begin_array(writer)
    for index in storage_order {
      let field = fields[index]
      @encode.begin_array(writer)
      @encode.string_value(writer, field.name)
      @encode.string_value(writer, field.kind)
      emit_optional_text(writer, field.precision)
      emit_optional_text(writer, field.scale)
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-managed-physical-schema/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(ManifestLimit)
    _ => Err(InvalidManifest)
  }
}

///|
fn encode_view_contract(
  schema_contract_cid : String,
  max_contract_bytes : Int,
) -> Result[String, PhysicalManifestIssue] {
  let writer = @encode.writer(max_contract_bytes, 8, 1) catch {
    _ => return Err(ManifestLimit)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "order")
    @encode.string_value(writer, "managed-output-occurrence-ascending")
    @encode.key(writer, "schema_contract_cid")
    @encode.string_value(writer, schema_contract_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-managed-physical-view/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(ManifestLimit)
    _ => Err(InvalidManifest)
  }
}

///|
/// Admit field metadata and storage order before deriving physical contract
/// identities. The adapter supplies metadata but cannot choose either CID.
pub fn admit_contracts(
  fields_frame : String,
  storage_order : Array[Int],
  max_contract_bytes : Int,
) -> Result[PhysicalContracts, PhysicalManifestIssue] {
  let fields = match read_fields(fields_frame, max_contract_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if fields.length() != storage_order.length() {
    return Err(InvalidManifest)
  }
  let seen = Array::make(fields.length(), false)
  for index in storage_order {
    if index < 0 || index >= fields.length() || seen[index] {
      return Err(InvalidManifest)
    }
    seen[index] = true
  }
  let schema_contract = match
    encode_schema_contract(fields, storage_order, max_contract_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let schema_contract_cid = match @sha256.text_hex(schema_contract) {
    Ok(value) => "sha256:" + value
    Err(_) => return Err(InvalidManifest)
  }
  let view_contract = match
    encode_view_contract(schema_contract_cid, max_contract_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let view_contract_cid = match @sha256.text_hex(view_contract) {
    Ok(value) => "sha256:" + value
    Err(_) => return Err(InvalidManifest)
  }
  Ok({ schema_contract, schema_contract_cid, view_contract, view_contract_cid, })
}

///|
pub fn contract_projection(contracts : PhysicalContracts) -> Array[String] {
  [
    contracts.schema_contract,
    contracts.schema_contract_cid,
    contracts.view_contract,
    contracts.view_contract_cid,
  ]
}
