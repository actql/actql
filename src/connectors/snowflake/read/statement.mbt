///|
pub(all) enum StatementIssue {
  InvalidSettings
  AlreadyBound
  Closed
  PendingRequest
  WrongRequest
  WrongResponse
  AlreadyAttempted
  NotAttempted
  AlreadyObserved
  RequestLimit
  InvalidResponse
  ForeignHandle
  UnrepresentableHandle
  HttpRejected(Int)
  TransportUnknown
  Read(ReadIssue)
}

///|
priv enum StatementRequestKind {
  Submit
  Status
  Partition(Int)
}

///|
/// Provider request progress for the same already-accounted Read. This does
/// not create a Run, reservation, credential grant or recovery authority.
pub struct StatementRead {
  priv read : Read
  priv request_id : String
  priv body : String
  priv max_requests : Int
  priv max_request_bytes : Int
  priv mut issued : Int
  priv mut pending : StatementRequest?
  priv mut pending_response : StatementResponse?
  priv mut next : StatementRequestKind?
  priv mut handle : String?
  priv mut unknown : Bool
}

///|
/// One nominal, one-shot physical request candidate. Its path/body is material;
/// dispatch still requires the existing current credential/Source authority.
pub struct StatementRequest {
  priv owner : StatementRead
  priv sequence : Int
  priv kind : StatementRequestKind
  priv http_method : String
  priv path : String
  priv body : String?
  priv mut attempted : Bool
  priv mut observed : Bool
}

///|
/// The original physical body has already consumed transfer capacity, before
/// any decompression or provider JSON parsing. This ticket grants no rows or
/// successful completion and can be admitted only by its original session.
pub struct StatementResponse {
  priv owner : StatementRead
  priv request : StatementRequest
  priv charge : @rows.RowPageCharge
  priv status_code : Int
  priv mut consumed : Bool
}

///|
fn statement_uuid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for index in 0..<36 {
    let character = value[index]
    if index == 8 || index == 13 || index == 18 || index == 23 {
      if character != '-' {
        return false
      }
    } else if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f') ||
      (character >= 'A' && character <= 'F')) {
      return false
    }
  }
  true
}

///|
/// Encode the original handle as one bounded path segment. Never follow a
/// server-supplied status URL or interpret a handle as path/query syntax.
fn statement_handle_path(
  handle : String,
  partition : Int?,
  max_bytes : Int,
) -> Result[String, StatementIssue] {
  // Standard URL construction removes exact dot segments, including %2E.
  // Keep the valid opaque observation, but issue no changed-handle candidate.
  if handle == "." || handle == ".." {
    return Err(UnrepresentableHandle)
  }
  let prefix = "/api/v2/statements/"
  let suffix = match partition {
    Some(value) => "?partition=" + value.to_string()
    None => ""
  }
  if prefix.length() > max_bytes ||
    suffix.length() > max_bytes - prefix.length() {
    return Err(InvalidSettings)
  }
  let mut remaining = max_bytes - prefix.length() - suffix.length()
  let bytes = @utf8.encode(handle)
  for byte in bytes {
    let byte = byte.to_int()
    let unreserved = (byte >= 65 && byte <= 90) ||
      (byte >= 97 && byte <= 122) ||
      (byte >= 48 && byte <= 57) ||
      byte == 45 ||
      byte == 46 ||
      byte == 95 ||
      byte == 126
    let needed = if unreserved { 1 } else { 3 }
    if needed > remaining {
      return Err(InvalidSettings)
    }
    remaining -= needed
  }
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  out.write_string(prefix)
  for byte in bytes {
    let byte = byte.to_int()
    if (byte >= 65 && byte <= 90) ||
      (byte >= 97 && byte <= 122) ||
      (byte >= 48 && byte <= 57) ||
      byte == 45 ||
      byte == 46 ||
      byte == 95 ||
      byte == 126 {
      out.write_char(byte.to_char().unwrap())
    } else {
      out.write_char('%')
      out.write_char(hex[byte / 16].to_int().to_char().unwrap())
      out.write_char(hex[byte % 16].to_int().to_char().unwrap())
    }
  }
  out.write_string(suffix)
  Ok(out.to_string())
}

///|
pub fn prepare_statement_read(
  read : Read,
  request_id : String,
  warehouse : String,
  role : String,
  timeout_seconds : Int,
  max_requests : Int,
  max_request_bytes : Int,
) -> Result[StatementRead, StatementIssue] {
  if read.closed || read.interrupted || read.finished || read.pages != 0 {
    return Err(Closed)
  }
  if read.statement_bound {
    return Err(AlreadyBound)
  }
  if !statement_uuid(request_id) ||
    warehouse.is_empty() ||
    role.is_empty() ||
    warehouse.contains("\u0000") ||
    role.contains("\u0000") ||
    timeout_seconds <= 0 ||
    max_requests <= 0 ||
    max_request_bytes <= 0 ||
    @scalar.admit_utf8_length(warehouse, max_request_bytes) is Err(_) ||
    @scalar.admit_utf8_length(role, max_request_bytes) is Err(_) {
    return Err(InvalidSettings)
  }
  let body = try {
    // The fixed request has five root values and one fixed parameter value.
    // This structural encoding bound is not a physical allocation grant.
    let writer = @encode.writer(max_request_bytes, 16, 4)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "parameters")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "multi_statement_count")
    @encode.string_value(writer, "1")
    @encode.end_object(writer)
    @encode.ordered_key(writer, "role")
    @encode.string_value(writer, role)
    @encode.ordered_key(writer, "statement")
    @encode.string_value(
      writer,
      @description.read_projection_statement(read.prepared.projection),
    )
    @encode.ordered_key(writer, "timeout")
    @encode.number_value(writer, timeout_seconds.to_double())
    @encode.ordered_key(writer, "warehouse")
    @encode.string_value(writer, warehouse)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(InvalidSettings)
  }
  let path = "/api/v2/statements?requestId=" + request_id
  if path.length() > max_request_bytes {
    return Err(InvalidSettings)
  }
  read.statement_bound = true
  Ok({
    read,
    request_id,
    body,
    max_requests,
    max_request_bytes,
    issued: 0,
    pending: None,
    pending_response: None,
    next: Some(Submit),
    handle: None,
    unknown: false,
  })
}

///|
fn statement_live(value : StatementRead) -> Bool {
  !value.read.closed && !value.read.interrupted && !value.unknown
}

///|
fn[T] fail_statement(
  value : StatementRead,
  issue : StatementIssue,
) -> Result[T, StatementIssue] {
  interrupt_result_read(value.read)
  value.next = None
  Err(issue)
}

///|
pub fn next_statement_request(
  value : StatementRead,
) -> Result[StatementRequest?, StatementIssue] {
  if !statement_live(value) {
    return Err(Closed)
  }
  if value.pending is Some(_) || value.pending_response is Some(_) {
    return Err(PendingRequest)
  }
  guard value.next is Some(kind) else { return Ok(None) }
  if value.issued >= value.max_requests {
    return fail_statement(value, RequestLimit)
  }
  let (http_method, path, body) = match kind {
    Submit =>
      (
        "POST",
        "/api/v2/statements?requestId=" + value.request_id,
        Some(value.body),
      )
    Status | Partition(_) => {
      guard value.handle is Some(handle) else {
        return fail_statement(value, InvalidResponse)
      }
      let partition = match kind {
        Partition(index) => Some(index)
        _ => None
      }
      let path = match
        statement_handle_path(handle, partition, value.max_request_bytes) {
        Ok(path) => path
        Err(issue) => return fail_statement(value, issue)
      }
      ("GET", path, None)
    }
  }
  let request = {
    owner: value,
    sequence: value.issued,
    kind,
    http_method,
    path,
    body,
    attempted: false,
    observed: false,
  }
  value.issued += 1
  value.pending = Some(request)
  value.next = None
  Ok(Some(request))
}

///|
fn statement_original_request(
  value : StatementRead,
  request : StatementRequest,
) -> Bool {
  physical_equal(value, request.owner) &&
  value.pending is Some(pending) &&
  physical_equal(request, pending)
}

///|
/// This marks the one-shot dispatch attempt, not physical send or execution.
/// Failure after this point must retain the original and cannot repeat POST.
pub fn attempt_statement_request(
  value : StatementRead,
  request : StatementRequest,
) -> Result[Unit, StatementIssue] {
  if !statement_live(value) {
    return Err(Closed)
  }
  if !statement_original_request(value, request) {
    return Err(WrongRequest)
  }
  if request.observed {
    return Err(AlreadyObserved)
  }
  if request.attempted {
    return Err(AlreadyAttempted)
  }
  request.attempted = true
  Ok(())
}

///|
pub fn statement_request_method(request : StatementRequest) -> String {
  request.http_method
}

///|
pub fn statement_request_path(request : StatementRequest) -> String {
  request.path
}

///|
pub fn statement_request_body(request : StatementRequest) -> String? {
  request.body
}

///|
pub fn statement_request_sequence(request : StatementRequest) -> Int {
  request.sequence
}

///|
/// Charge the exact physical body before its decoder allocates or parses the
/// provider representation. A lost/malformed decode never permits resending
/// the request, nor does receipt settle its socket or source responsibility.
pub fn charge_statement_response(
  value : StatementRead,
  request : StatementRequest,
  status_code : Int,
  wire_body : Bytes,
) -> Result[StatementResponse, StatementIssue] {
  if !statement_live(value) {
    return Err(Closed)
  }
  if request.observed {
    return Err(AlreadyObserved)
  }
  if !statement_original_request(value, request) {
    return Err(WrongRequest)
  }
  if !request.attempted {
    return Err(NotAttempted)
  }
  request.observed = true
  value.pending = None
  let charge = match @rows.charge_row_run_page(value.read.run, wire_body) {
    Ok(value) => value
    Err(issue) => return fail_statement(value, Read(Host(issue)))
  }
  let response = {
    owner: value,
    request,
    charge,
    status_code,
    consumed: false,
  }
  value.pending_response = Some(response)
  Ok(response)
}

///|
fn consume_statement_response(
  value : StatementRead,
  response : StatementResponse,
) -> Result[Unit, StatementIssue] {
  if !statement_live(value) {
    return Err(Closed)
  }
  if response.consumed {
    return Err(AlreadyObserved)
  }
  guard physical_equal(value, response.owner) &&
    value.pending_response is Some(expected) &&
    physical_equal(response, expected) else {
    return Err(WrongResponse)
  }
  response.consumed = true
  value.pending_response = None
  Ok(())
}

///|
/// A bounded decoder failure abandons only this original response. It is not
/// a response-loss retry, a new request, provider cancellation or close ACK.
pub fn reject_statement_response(
  value : StatementRead,
  response : StatementResponse,
) -> Result[Unit, StatementIssue] {
  match consume_statement_response(value, response) {
    Ok(_) => fail_statement(value, InvalidResponse)
    Err(issue) => Err(issue)
  }
}

///|
/// The selected physical decoder must preserve the original wire/decoded
/// correspondence. This typed admission is not itself a gzip execution or a
/// proof of current authority, physical allocation or socket retirement.
pub fn accept_charged_statement_response(
  value : StatementRead,
  response : StatementResponse,
  decoded_body : Bytes,
) -> Result[Unit, StatementIssue] {
  match consume_statement_response(value, response) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let read = value.read
  let request = response.request
  let status_code = response.status_code
  let charge = response.charge
  if status_code == 202 {
    if request.kind is Partition(_) {
      return fail_statement(value, InvalidResponse)
    }
    let handle = match
      @response.project_running_statement(decoded_body, read.limits) {
      Ok(value) => value
      Err(issue) => return fail_statement(value, Read(Response(issue)))
    }
    if value.handle is Some(expected) && expected != handle {
      return fail_statement(value, ForeignHandle)
    }
    match @rows.consume_row_run_response_charge(read.run, charge) {
      Ok(_) => ()
      Err(issue) => return fail_statement(value, Read(Host(issue)))
    }
    value.handle = Some(handle)
    value.next = Some(Status)
    return Ok(())
  }
  if status_code != 200 {
    return fail_statement(value, HttpRejected(status_code))
  }
  let accepted = match request.kind {
    Partition(ordinal) =>
      accept_charged_result_partition(read, charge, ordinal, decoded_body)
    Submit | Status =>
      accept_charged_first_result(read, charge, decoded_body, value.handle)
  }
  match accepted {
    Ok(_) => ()
    Err(issue) => return fail_statement(value, Read(issue))
  }
  guard read.original is Some(original) else {
    return fail_statement(value, InvalidResponse)
  }
  value.handle = Some(@response.result_set_handle(original))
  if read.pages == @response.result_set_partition_count(original) {
    match finish_result_read(read) {
      Ok(_) => ()
      Err(issue) => return fail_statement(value, Read(issue))
    }
    value.next = None
  } else {
    value.next = Some(Partition(read.pages))
  }
  Ok(())
}

///|
/// Convenience for an already bounded identity decoder. Compressed transports
/// must use charge_statement_response before decoding, then the same response
/// ticket with accept_charged_statement_response.
pub fn accept_statement_response(
  value : StatementRead,
  request : StatementRequest,
  status_code : Int,
  wire_body : Bytes,
  decoded_body : Bytes,
) -> Result[Unit, StatementIssue] {
  match charge_statement_response(value, request, status_code, wire_body) {
    Ok(response) =>
      accept_charged_statement_response(value, response, decoded_body)
    Err(issue) => Err(issue)
  }
}

///|
/// Lost response is not absence, a fresh attempt, provider cancellation, a
/// settled transport or permission to reissue the original request.
pub fn mark_statement_response_unknown(
  value : StatementRead,
  request : StatementRequest,
) -> Result[Unit, StatementIssue] {
  if !statement_original_request(value, request) {
    return Err(WrongRequest)
  }
  if !request.attempted {
    return Err(NotAttempted)
  }
  request.observed = true
  value.pending = None
  value.unknown = true
  fail_statement(value, TransportUnknown)
}

///|
pub fn statement_read_complete(value : StatementRead) -> Bool {
  statement_live(value) &&
  value.read.finished &&
  value.pending_response is None &&
  value.pending is None &&
  value.next is None
}

///|
pub fn statement_read_request_id(value : StatementRead) -> String {
  value.request_id
}

///|
pub fn statement_read_handle(value : StatementRead) -> String? {
  value.handle
}
