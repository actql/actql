///|
/// Documented evidence that Salesforce refused a write: a REST status whose
/// official definition is a rejection of the request, answered with a
/// structured error body. The statuses admitted are 400 ("couldn't be
/// understood"), 401 (expired or invalid session), 403 ("has been refused",
/// including REQUEST_LIMIT_EXCEEDED), 404 ("couldn't be found") and 428
/// ("wasn't executed"). The outcome code names the evidence; `http_status`
/// is the rejecting status. Anything else, including a 5xx, a timeout, a
/// malformed body or an error code that reports provider uncertainty, is not
/// evidence and stays unknown. An upsert 300 is documented as writing
/// nothing, but the credential transport refuses every 3xx as a redirect
/// before its body is read, so it stays unknown too.
pub(all) struct WriteRejection {
  code : String
  http_status : Int
} derive(Eq, Debug)

///|
const REJECTED_CODE : String = "SalesforceWriteRejected"

///|
fn write_rejection_status(status : Int) -> Bool {
  status == 400 ||
  status == 401 ||
  status == 403 ||
  status == 404 ||
  status == 428
}

///|
/// Error codes that report a provider failure or timeout, not a rejection
/// before the save. A response carrying one is not rejection evidence.
fn write_error_code_uncertain(code : String) -> Bool {
  code == "SERVER_UNAVAILABLE" ||
  code == "UNKNOWN_EXCEPTION" ||
  code == "QUERY_TIMEOUT" ||
  code == "REQUEST_RUNNING_TOO_LONG"
}

///|
/// A Salesforce error code: an upper-case enumeration name. Any other text
/// is not published as a code.
fn write_error_code_valid(code : String) -> Bool {
  if code.length() < 1 || code.length() > 100 {
    return false
  }
  let mut index = 0
  for char in code {
    let upper = char >= 'A' && char <= 'Z'
    let valid = upper ||
      (index > 0 && (char == '_' || (char >= '0' && char <= '9')))
    if !valid {
      return false
    }
    index = index + 1
  }
  true
}

///|
/// The fields of the written Resource this installation declared: those
/// described in the write projection and its external target. An error may
/// name only these; any other field name is not published.
fn declared_write_fields(projection : WriteProjection) -> Array[String] {
  let names = []
  let add = fn(name : String) {
    if !name.is_empty() && !names.contains(name) {
      names.push(name)
    }
  }
  for name in projection.field_names {
    add(name)
  }
  for field in projection.fields {
    add(field.name)
  }
  if projection.external_target is Some(field) {
    add(field.name)
  }
  names
}

///|
/// The field names of one provider error, reduced to declared fields.
fn declared_error_fields(
  fields : Array[String],
  declared : Array[String],
) -> Array[String] {
  let kept = []
  for field in fields {
    if declared.contains(field) && !kept.contains(field) {
      kept.push(field)
    }
  }
  kept
}

///|
/// A provider error with its message withheld and its fields reduced to the
/// declared fields. The raw response stays private evidence.
fn published_write_error(
  error : WriteProviderError,
  declared : Array[String],
) -> WriteProviderError {
  {
    status_code: error.status_code,
    message: "",
    fields: declared_error_fields(error.fields, declared),
  }
}

///|
fn parse_write_rejection_root(
  bytes : Bytes,
  limits : WriteCollectionResponseLimits,
) -> Result[@decode.Cursor, WriteSingleResponseIssue] {
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
/// One REST error object: `errorCode` (an enumeration name) and `message`,
/// with an optional `fields` array of names. Other members are ignored.
fn rejection_error(
  cursor : @decode.Cursor,
  declared : Array[String],
) -> Result[WriteProviderError, WriteSingleResponseIssue] {
  guard @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, "errorCode") is Some(code_cursor) &&
    @decode.text(code_cursor) is Ok(code) &&
    write_error_code_valid(code) &&
    @decode.lookup(object, "message") is Some(message_cursor) &&
    @decode.text(message_cursor) is Ok(_) else {
    return Err(InvalidResponse)
  }
  if write_error_code_uncertain(code) {
    return Err(UnexpectedStatus)
  }
  let fields = []
  if @decode.lookup(object, "fields") is Some(fields_cursor) {
    guard @decode.array_length(fields_cursor) is Some(count) && count <= 1000 else {
      return Err(InvalidResponse)
    }
    for index in 0..<count {
      guard @decode.element_at(fields_cursor, index) is Some(field_cursor) &&
        @decode.text(field_cursor) is Ok(field) else {
        return Err(InvalidResponse)
      }
      fields.push(field)
    }
  }
  Ok(
    published_write_error({ status_code: code, message: "", fields, }, declared),
  )
}

///|
/// The error body of a rejected request: an array of at least one error
/// object, or one error object alone.
fn rejection_errors(
  bytes : Bytes,
  limits : WriteCollectionResponseLimits,
  declared : Array[String],
) -> Result[Array[WriteProviderError], WriteSingleResponseIssue] {
  let root = match parse_write_rejection_root(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let errors = []
  match @decode.array_length(root) {
    Some(count) => {
      if count < 1 || count > 100 {
        return Err(InvalidResponse)
      }
      for index in 0..<count {
        guard @decode.element_at(root, index) is Some(cursor) else {
          return Err(InvalidResponse)
        }
        match rejection_error(cursor, declared) {
          Ok(error) => errors.push(error)
          Err(issue) => return Err(issue)
        }
      }
    }
    None =>
      match rejection_error(root, declared) {
        Ok(error) => errors.push(error)
        Err(issue) => return Err(issue)
      }
  }
  Ok(errors)
}

///|
/// Classify a complete non-success response of one single-record write. It
/// returns a definite failure only on the documented rejection evidence for
/// this request's operation; every other response is an issue, and the
/// caller keeps the write unknown.
pub fn project_write_single_rejection(
  http_status : Int,
  bytes : Bytes,
  request : SingleWriteRequest,
  limits : WriteCollectionResponseLimits,
) -> Result[WriteSingleResponse, WriteSingleResponseIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if !write_rejection_status(http_status) {
    return Err(UnexpectedStatus)
  }
  match
    rejection_errors(bytes, limits, declared_write_fields(request.projection)) {
    Ok(errors) =>
      Ok({
        result: RowFailed(errors),
        response_sha256: @sha.hex(bytes),
        rejection: Some({ code: REJECTED_CODE, http_status, }),
      })
    Err(issue) => Err(issue)
  }
}

///|
/// Classify a complete non-success Collections response. A request-level
/// rejection saved no row, so every row of the request failed with the same
/// errors. Every other response keeps every row unknown.
pub fn project_write_collection_rejection(
  http_status : Int,
  bytes : Bytes,
  request : WriteCollectionRequest,
  limits : WriteCollectionResponseLimits,
) -> Result[WriteCollectionResponse, WriteCollectionResponseIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if !write_rejection_status(http_status) {
    return Err(UnexpectedStatus)
  }
  let errors = match
    rejection_errors(bytes, limits, declared_write_fields(request.projection)) {
    Ok(value) => value
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(InvalidLimits) => return Err(InvalidLimits)
    Err(UnexpectedStatus) => return Err(UnexpectedStatus)
    Err(InvalidResponse) => return Err(InvalidResponse)
  }
  Ok({
    results: request.row_preview_cids.map(fn(_) { RowFailed(errors) }),
    response_sha256: @sha.hex(bytes),
    row_preview_cids: Some(request.row_preview_cids.copy()),
    rejection: Some({ code: REJECTED_CODE, http_status, }),
  })
}

///|
/// The rejection evidence of a single-record response, if it is a failure.
pub fn write_single_rejection(value : WriteSingleResponse) -> WriteRejection? {
  value.rejection
}

///|
/// Per-row Collections failures of an HTTP 200 response, published with the
/// provider messages withheld and the fields reduced to declared fields.
fn published_collection_results(
  results : Array[WriteRowResult],
  projection : WriteProjection,
) -> Array[WriteRowResult] {
  let declared = declared_write_fields(projection)
  results.map(fn(result) {
    match result {
      RowFailed(errors) =>
        RowFailed(
          errors.map(fn(error) { published_write_error(error, declared) }),
        )
      applied => applied
    }
  })
}
