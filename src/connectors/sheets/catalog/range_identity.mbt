// The existing Sheets identity domains, moved without changing their bytes.
// These are provider request identities, never approval or dispatch authority.

///|
pub struct RangeFailure {
  code : String
  refusal : Issue?
} derive(Eq, Debug)

///|
fn range_failure(code : String) -> RangeFailure {
  { code, refusal: None, }
}

///|
fn range_contract_failure(issue : Issue) -> RangeFailure {
  { code: "SheetsContractRefused", refusal: Some(issue), }
}

///|
pub fn range_failure_code(issue : RangeFailure) -> String {
  issue.code
}

///|
pub fn range_failure_refusal(issue : RangeFailure) -> Issue? {
  issue.refusal
}

///|
fn range_parse(
  wire : String,
  limits : Limits,
  code : String,
) -> Result[Json, RangeFailure] {
  guard admit(@utf8.encode(wire), limits) is Ok(_) else {
    return Err(range_failure(code))
  }
  Ok(@json.parse(wire)) catch {
    _ => Err(range_failure(code))
  }
}

///|
fn range_canonical(
  value : Json,
  limits : Limits,
) -> Result[String, RangeFailure] {
  try {
    let value = @canonical.from_json(
      value,
      limits.max_nodes,
      limits.max_depth,
      limits.max_bytes,
      data_keys=true,
    )
    Ok(
      @canonical.stringify_value(
        value,
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      ),
    )
  } catch {
    _ => Err(range_failure("SheetsRangeRecoveryMismatch"))
  }
}

///|
// Host configuration identity historically uses NFC for both keys and values,
// without newline conversion. Payload canonicalization above preserves data.
fn range_configuration_value(value : Json) -> Result[Json, RangeFailure] {
  match value {
    String(value) =>
      match @text.normalize_nfc(value) {
        Ok(value) => Ok(value.to_json())
        Err(_) => Err(range_failure("InvalidCanonicalText"))
      }
    Array(values) => {
      let output = []
      for value in values {
        match range_configuration_value(value) {
          Ok(value) => output.push(value)
          Err(issue) => return Err(issue)
        }
      }
      Ok(Json::array(output))
    }
    Object(fields) => {
      let output : Map[String, Json] = Map([])
      for key, value in fields {
        let key = match @text.normalize_nfc(key) {
          Ok(value) => value
          Err(_) => return Err(range_failure("InvalidCanonicalText"))
        }
        match range_configuration_value(value) {
          Ok(value) => output[key] = value
          Err(issue) => return Err(issue)
        }
      }
      Ok(Json::object(output))
    }
    _ => Ok(value)
  }
}

///|
fn range_content_cid(
  value : Json,
  limits : Limits,
) -> Result[String, RangeFailure] {
  let normalized = match range_configuration_value(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match range_canonical(normalized, limits) {
    Ok(wire) => Ok("sha256:" + @sha.hex(@utf8.encode(wire)))
    Err(issue) => Err(issue)
  }
}

///|
fn range_json_value(range : GridRange) -> Json {
  {
    "sheetId": range.sheet_id.to_json(),
    "startRow": range.start_row.to_json(),
    "endRow": range.end_row.to_json(),
    "startColumn": range.start_column.to_json(),
    "endColumn": range.end_column.to_json(),
  }
}

///|
fn range_provider_identity_document(
  origin : String,
  spreadsheet_id : String,
) -> Json {
  {
    "version": "actql-sheets-provider/0.1",
    "api_origin": origin.to_json(),
    "spreadsheet_id": spreadsheet_id.to_json(),
  }
}

///|
fn range_identity_document(range : GridRange) -> Json {
  { "version": "actql-sheets-range/0.1", "range": range_json_value(range) }
}

///|
fn range_reference_document(
  provider_cid : String,
  identity_cid : String,
  catalog_cid : String,
  binding_cid : String,
) -> Json {
  {
    "$actql_ref": "resource",
    "version": "actql-resource-ref/0.1",
    "provider_namespace": "sheets",
    "resource_kind": "sheet_range",
    "provider_identity_cid": provider_cid.to_json(),
    "identity_cid": identity_cid.to_json(),
    "authority_scope_cid": binding_cid.to_json(),
    "boundary_cid": catalog_cid.to_json(),
  }
}

///|
pub fn range_reference(
  origin : String,
  spreadsheet_id : String,
  range : GridRange,
  catalog_cid : String,
  binding_cid : String,
  limits : Limits,
) -> Result[Json, RangeFailure] {
  let provider_cid = match
    range_content_cid(
      range_provider_identity_document(origin, spreadsheet_id),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let identity_cid = match
    range_content_cid(range_identity_document(range), limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(
    range_reference_document(
      provider_cid, identity_cid, catalog_cid, binding_cid,
    ),
  )
}

///|
fn range_request_cid(
  origin : String,
  path : String,
  body : String,
  target : String,
) -> Result[String, RangeFailure] {
  framed_request_identity(
    ["actql-sheets-update-request/0.1", origin, "POST", path, body, target],
    "InvalidSheetsUpdateBinding",
  )
}

///|
pub fn append_request_identity(
  origin : String,
  path : String,
  body : String,
) -> Result[String, RangeFailure] {
  framed_request_identity(
    ["actql-sheets-append-request/0.1", origin, "POST", path, body],
    "InvalidSheetsAppendBinding",
  )
}

///|
fn framed_request_identity(
  parts : Array[String],
  failure_code : String,
) -> Result[String, RangeFailure] {
  let hash = @sha.hasher()
  try {
    for part in parts {
      let bytes = @utf8.encode(part)
      @sha.update(hash, @utf8.encode(bytes.length().to_string() + ":"))
      @sha.update(hash, bytes)
    }
    Ok("sha256:" + @sha.finish_hex(hash))
  } catch {
    _ => Err(range_failure(failure_code))
  }
}
