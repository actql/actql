///|
pub(all) struct WriteCollectionResponseLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
}

///|
pub(all) enum WriteCollectionResponseIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  CountMismatch
} derive(Eq, Debug)

///|
pub(all) enum WriteCollectionKind {
  CollectionCreate
  CollectionUpdate
  CollectionUpsert
} derive(Eq, Debug)

///|
pub(all) struct WriteProviderError {
  status_code : String
  message : String
  fields : Array[String]
} derive(Eq, Debug)

///|
pub(all) enum WriteRowResult {
  RowApplied(String, Bool)
  RowFailed(Array[WriteProviderError])
} derive(Eq, Debug)

///|
/// Exact ordered results from one complete HTTP 200 Collections response.
/// Transport loss or malformed evidence cannot be interpreted as row failure.
pub struct WriteCollectionResponse {
  results : Array[WriteRowResult]
  response_sha256 : String
}

///|
pub fn write_collection_result_count(value : WriteCollectionResponse) -> Int {
  value.results.length()
}

///|
pub fn write_collection_result_at(
  value : WriteCollectionResponse,
  index : Int,
) -> WriteRowResult? {
  value.results.get(index)
}

///|
pub fn write_collection_response_sha256(
  value : WriteCollectionResponse,
) -> String {
  value.response_sha256
}

///|
fn collection_error(
  cursor : @decode.Cursor,
) -> Result[WriteProviderError, WriteCollectionResponseIssue] {
  guard @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, "statusCode") is Some(code_cursor) &&
    @decode.text(code_cursor) is Ok(code) &&
    !code.is_empty() &&
    @decode.lookup(object, "message") is Some(message_cursor) &&
    @decode.text(message_cursor) is Ok(message) &&
    @decode.lookup(object, "fields") is Some(fields_cursor) &&
    @decode.array_length(fields_cursor) is Some(field_count) else {
    return Err(InvalidResponse)
  }
  let fields = []
  for index in 0..<field_count {
    guard @decode.element_at(fields_cursor, index) is Some(field_cursor) &&
      @decode.text(field_cursor) is Ok(field) else {
      return Err(InvalidResponse)
    }
    fields.push(field)
  }
  Ok({ status_code: code, message, fields, })
}

///|
fn collection_result(
  cursor : @decode.Cursor,
  kind : WriteCollectionKind,
) -> Result[WriteRowResult, WriteCollectionResponseIssue] {
  guard @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, "success") is Some(success_cursor) &&
    @decode.boolean(success_cursor) is Ok(success) &&
    @decode.lookup(object, "errors") is Some(errors_cursor) &&
    @decode.array_length(errors_cursor) is Some(error_count) else {
    return Err(InvalidResponse)
  }
  let id = match @decode.field(object, "id") {
    Missing | ExplicitNull => None
    Present(value) =>
      match @decode.text(value) {
        Ok(text) => Some(text)
        Err(_) => return Err(InvalidResponse)
      }
  }
  let created = match @decode.field(object, "created") {
    Missing => None
    ExplicitNull => return Err(InvalidResponse)
    Present(value) =>
      match @decode.boolean(value) {
        Ok(flag) => Some(flag)
        Err(_) => return Err(InvalidResponse)
      }
  }
  if success {
    guard id is Some(record_id) && !record_id.is_empty() && error_count == 0 else {
      return Err(InvalidResponse)
    }
    let was_created = match kind {
      CollectionCreate => {
        if created is Some(false) {
          return Err(InvalidResponse)
        }
        true
      }
      CollectionUpdate => {
        if created is Some(true) {
          return Err(InvalidResponse)
        }
        false
      }
      CollectionUpsert =>
        match created {
          Some(flag) => flag
          None => return Err(InvalidResponse)
        }
    }
    Ok(RowApplied(record_id, was_created))
  } else {
    if id is Some(_) || error_count == 0 || created is Some(true) {
      return Err(InvalidResponse)
    }
    let errors = []
    for index in 0..<error_count {
      guard @decode.element_at(errors_cursor, index) is Some(error_cursor) else {
        return Err(InvalidResponse)
      }
      match collection_error(error_cursor) {
        Ok(error) => errors.push(error)
        Err(issue) => return Err(issue)
      }
    }
    Ok(RowFailed(errors))
  }
}

///|
/// A Collections HTTP status alone proves no member outcome. The caller must
/// supply the exact admitted request count and durable transport observation.
pub fn project_write_collection_response(
  bytes : Bytes,
  kind : WriteCollectionKind,
  expected_count : Int,
  limits : WriteCollectionResponseLimits,
) -> Result[WriteCollectionResponse, WriteCollectionResponseIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_rows < 1 ||
    expected_count < 1 ||
    expected_count > limits.max_rows ||
    expected_count > 200 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
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
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind is @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
  guard @decode.array_length(root) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count != expected_count {
    return Err(CountMismatch)
  }
  let results = []
  for index in 0..<count {
    guard @decode.element_at(root, index) is Some(cursor) else {
      return Err(InvalidResponse)
    }
    match collection_result(cursor, kind) {
      Ok(result) => results.push(result)
      Err(issue) => return Err(issue)
    }
  }
  Ok({ results, response_sha256: @sha.hex(bytes), })
}
