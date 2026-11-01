// Clear is an explicit operation, never a partial overwrite or inferred NULL.

///|
// Original UUID spelling bound, shared by validation and construction DATA.
pub fn clear_marker_text_units() -> Int {
  36
}

///|
fn check_clear_marker(marker : String) -> Bool {
  if marker.length() != clear_marker_text_units() {
    return false
  }
  for index = 0; index < marker.length(); index = index + 1 {
    let character = marker[index]
    if index == 8 || index == 13 || index == 18 || index == 23 {
      if character != '-' {
        return false
      }
    } else if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  marker[14] == '4' &&
  (
    marker[19] == '8' ||
    marker[19] == '9' ||
    marker[19] == 'a' ||
    marker[19] == 'b'
  )
}

///|
fn clear_marker_value(range : GridRange, marker : String) -> Json {
  { "marker": marker.to_json(), "range": range_json_value(range) }
}

///|
pub fn clear_request_identity(
  origin : String,
  path : String,
  body : String,
  target : String,
) -> Result[String, RangeFailure] {
  framed_request_identity(
    ["actql-sheets-clear-request/0.1", origin, "POST", path, body, target],
    "InvalidSheetsClearBinding",
  )
}

///|
/// An independently selected clear masks values only. The original request
/// marker is written in the same batch, at the sheet containing this range.
/// Its value binds the complete rectangle; it grants no reconciliation result.
pub fn clear_request(
  range : GridRange,
  columns : Array[Column],
  marker : String,
  limits : Limits,
) -> Result[String, Issue] {
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !check_clear_marker(marker) {
    return Err(InvalidSchema)
  }
  let marker_value = match
    range_canonical(clear_marker_value(range, marker), limits) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  let body = clear_request_document(range, marker_value).stringify()
  match admit(@utf8.encode(body), limits) {
    Ok(_) => Ok(body)
    Err(issue) => Err(issue)
  }
}

///|
/// Same values-only clear document and original marker envelope. This pure
/// shape builder supplies neither a marker admission nor a cleanup result.
pub fn clear_request_document(range : GridRange, marker_value : String) -> Json {
  {
    "requests": [
      {
        "updateCells": {
          "range": {
            "sheetId": range.sheet_id.to_json(),
            "startRowIndex": range.start_row.to_json(),
            "endRowIndex": range.end_row.to_json(),
            "startColumnIndex": range.start_column.to_json(),
            "endColumnIndex": range.end_column.to_json(),
          },
          "rows": [],
          "fields": "userEnteredValue",
        },
      },
      {
        "createDeveloperMetadata": {
          "developerMetadata": {
            "metadataKey": "actql_request",
            "metadataValue": marker_value.to_json(),
            "location": { "sheetId": range.sheet_id.to_json() },
            "visibility": "DOCUMENT",
          },
        },
      },
    ],
  }
}

///|
/// Require the complete atomic acknowledgement and the original range marker.
/// No empty-cell observation, nearby marker or HTTP status alone settles a Run.
pub fn classify_clear(
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
  guard parse_response_body(body, limits) is Ok(root) &&
    acknowledgement_object(root) is Some(object) &&
    object.get("spreadsheetId") is Some(id) &&
    acknowledgement_text(id) == Some(spreadsheet_id) &&
    object.get("replies") is Some(replies) &&
    acknowledgement_array(replies) is Some(items) &&
    items.length() == 2 &&
    acknowledgement_object_length(items[0]) is Some(0) &&
    acknowledgement_object(items[1]) is Some(second) &&
    second.get("createDeveloperMetadata") is Some(created) &&
    acknowledgement_object(created) is Some(created) &&
    created.get("developerMetadata") is Some(metadata) &&
    acknowledgement_object(metadata) is Some(metadata) &&
    metadata.get("metadataId") is Some(metadata_id) &&
    acknowledgement_int32(metadata_id) is Some(metadata_id) &&
    metadata_id >= 0 &&
    metadata.get("metadataKey") is Some(key) &&
    acknowledgement_text(key) == Some("actql_request") &&
    metadata.get("metadataValue") is Some(value) &&
    acknowledgement_text(value) is Some(value) &&
    range_canonical(clear_marker_value(range, marker), limits) == Ok(value) &&
    metadata.get("visibility") is Some(visibility) &&
    acknowledgement_text(visibility) == Some("DOCUMENT") &&
    metadata.get("location") is Some(location) &&
    acknowledgement_object_length(location) is Some(1) &&
    acknowledgement_object(location) is Some(location) &&
    location.get("sheetId") is Some(sheet_id) &&
    acknowledgement_int32(sheet_id) == Some(range.sheet_id) else {
    return Unknown
  }
  Applied
}
