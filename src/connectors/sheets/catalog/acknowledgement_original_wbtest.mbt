// Original decoder-backed classifiers retained only for paired comparison.

///|
fn original_acknowledgement_admit(
  body : Bytes,
  limits : Limits,
) -> Result[@decode.Cursor, Issue] {
  match check_limits(limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if body.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(issue) =>
      Err(
        if issue.kind is @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
}

///|
fn original_acknowledgement_append(
  status : Int,
  body : Bytes,
  spreadsheet_id : String,
  limits : Limits,
) -> AppendOutcome {
  if status != 200 {
    return Unknown
  }
  guard original_acknowledgement_admit(body, limits) is Ok(root) &&
    @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "spreadsheetId") is Some(id) &&
    @decode.text(id) is Ok(answered) &&
    answered == spreadsheet_id &&
    @decode.lookup(object, "replies") is Some(replies) &&
    @decode.elements(replies) is Ok(items) &&
    items.length() == 1 &&
    @decode.object_length(items[0]) is Some(0) else {
    return Unknown
  }
  Applied
}

///|
fn original_acknowledgement_clear(
  status : Int,
  body : Bytes,
  spreadsheet_id : String,
  range : GridRange,
  marker : String,
  limits : Limits,
) -> AppendOutcome {
  if status != 200 || !check_clear_marker(marker) {
    return Unknown
  }
  guard original_acknowledgement_admit(body, limits) is Ok(root) &&
    @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "spreadsheetId") is Some(id) &&
    @decode.text(id) == Ok(spreadsheet_id) &&
    @decode.lookup(object, "replies") is Some(replies) &&
    @decode.elements(replies) is Ok(items) &&
    items.length() == 2 &&
    @decode.object_length(items[0]) is Some(0) &&
    @decode.open_object(items[1]) is Ok(second) &&
    @decode.lookup(second, "createDeveloperMetadata") is Some(created) &&
    @decode.open_object(created) is Ok(created) &&
    @decode.lookup(created, "developerMetadata") is Some(metadata) &&
    @decode.open_object(metadata) is Ok(metadata) &&
    @decode.lookup(metadata, "metadataId") is Some(metadata_id) &&
    @decode.int32(metadata_id) is Ok(metadata_id) &&
    metadata_id >= 0 &&
    @decode.lookup(metadata, "metadataKey") is Some(key) &&
    @decode.text(key) == Ok("actql_request") &&
    @decode.lookup(metadata, "metadataValue") is Some(value) &&
    @decode.text(value) is Ok(value) &&
    range_canonical(clear_marker_value(range, marker), limits) == Ok(value) &&
    @decode.lookup(metadata, "visibility") is Some(visibility) &&
    @decode.text(visibility) == Ok("DOCUMENT") &&
    @decode.lookup(metadata, "location") is Some(location) &&
    @decode.object_length(location) is Some(1) &&
    @decode.open_object(location) is Ok(location) &&
    @decode.lookup(location, "sheetId") is Some(sheet_id) &&
    @decode.int32(sheet_id) == Ok(range.sheet_id) else {
    return Unknown
  }
  Applied
}

///|
test "acknowledgement source projection preserves original complete decoder acceptance" {
  let bodies = [
    "",
    "null",
    "[]",
    "{}",
    "{\"spreadsheetId\":\"book\",\"replies\":[{}]}",
    "{\"spreadsheetId\":\"foreign\",\"replies\":[{}]}",
    "{\"spreadsheetId\":\"book\",\"replies\":[]}",
    "{\"spreadsheetId\":\"book\",\"replies\":[{},{}]}",
    "{\"spreadsheetId\":\"book\",\"replies\":[null]}",
    "{\"spreadsheetId\":\"book\",\"replies\":[{\"extra\":0}]}",
    "{\"spreadsheetId\":\"book\",\"spreadsheetId\":\"book\",\"replies\":[{}]}",
    "{\"spreadsheetId\":\"book\",\"replies\":[{}],\"extra\":{\"e\\u0301\":1,\"é\":2}}",
    "{\"spreadsheetId\":\"book\",\"replies\":[{}],\"extra\":\"\\ud800\"}",
    clear_fixed_reply(),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":-1",
    ),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":17.0",
    ),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":1.7e1",
    ),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":1.5",
    ),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":2147483648",
    ),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":-0",
    ),
    clear_fixed_reply().replace(
      old="\"metadataId\":17",
      new="\"metadataId\":1e309",
    ),
    clear_fixed_reply().replace(old="actql_request", new="foreign"),
    clear_fixed_reply().replace(old="DOCUMENT", new="PROJECT"),
    clear_fixed_reply().replace(old="\"sheetId\":7", new="\"sheetId\":8"),
    clear_fixed_reply().replace(old="\"sheetId\":7", new="\"sheetId\":\"7\""),
    clear_fixed_reply() + " trailing",
  ]
  let original = clear_limits()
  let limits = [
    original,
    { ..original, max_bytes: 128, },
    { ..original, max_nodes: 4, },
    { ..original, max_depth: 1, },
    { ..original, max_depth: 2, },
    { ..original, max_bytes: 0, },
    { ..original, max_nodes: 0, },
    { ..original, max_depth: 0, },
    { ..original, max_cells: 0, },
  ]
  for body in bodies {
    let bytes = @utf8.encode(body)
    for limit in limits {
      for status in [200, 201, 503] {
        assert_eq(
          classify_append(status, bytes, "book", limit),
          original_acknowledgement_append(status, bytes, "book", limit),
        )
        for marker in [clear_fixed_marker(), "not-a-marker"] {
          assert_eq(
            classify_clear(status, bytes, "book", clear_grid(), marker, limit),
            original_acknowledgement_clear(
              status,
              bytes,
              "book",
              clear_grid(),
              marker,
              limit,
            ),
          )
        }
      }
    }
  }
}
