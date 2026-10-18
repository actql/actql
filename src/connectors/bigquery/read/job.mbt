///|
pub(all) enum JobIssue {
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
  UnrepresentableJob
  ProviderFailed
  HttpRejected(Int)
  TransportUnknown
  Read(ReadIssue)
}

///|
priv enum JobRequestKind {
  Submit
  Status
  Results(String?)
}

///|
/// Provider request progress for the same already-accounted Read. This does
/// not create a Run, reservation, credential grant or recovery authority.
pub struct JobRead {
  priv read : Read
  priv material : @catalog.QueryJobMaterial
  priv submit_path : String
  priv status_path : String
  priv results_path : String
  priv max_requests : Int
  priv max_request_bytes : Int
  priv mut issued : Int
  priv mut pending : JobRequest?
  priv mut pending_response : JobResponse?
  priv mut next : JobRequestKind?
  priv mut remote_done : Bool
  priv mut unknown : Bool
}

///|
/// One nominal, one-shot physical request candidate. Its path/body is material;
/// dispatch still requires the existing current credential/Source authority.
pub struct JobRequest {
  priv owner : JobRead
  priv sequence : Int
  priv kind : JobRequestKind
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
pub struct JobResponse {
  priv owner : JobRead
  priv request : JobRequest
  priv charge : @rows.RowPageCharge
  priv status_code : Int
  priv mut consumed : Bool
}

///|
fn job_component(text : String, max_bytes : Int) -> Result[String, JobIssue] {
  let bytes = @utf8.encode(text)
  let mut remaining = max_bytes
  for byte in bytes {
    let n = byte.to_int()
    let plain = (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126
    let used = if plain { 1 } else { 3 }
    if used > remaining {
      return Err(InvalidSettings)
    }
    remaining -= used
  }
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in bytes {
    let n = byte.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 46 ||
      n == 95 ||
      n == 126 {
      out.write_char(n.to_char().unwrap())
    } else {
      out.write_char('%')
      out.write_char(hex[n / 16].to_int().to_char().unwrap())
      out.write_char(hex[n % 16].to_int().to_char().unwrap())
    }
  }
  Ok(out.to_string())
}

///|
/// Bind one original already-accounted acquisition before its first request.
/// The Job ID is supplied before POST, never minted from a lost response.
pub fn prepare_job_read(
  read : Read,
  maximum_bytes_billed : Int64,
  max_results : Int,
  timeout_ms : Int,
  max_requests : Int,
  max_request_bytes : Int,
) -> Result[JobRead, JobIssue] {
  if !read_available(read) || read.finished || read.pages != 0 {
    return Err(Closed)
  }
  if read.job_bound {
    return Err(AlreadyBound)
  }
  if max_results <= 0 ||
    timeout_ms < 0 ||
    max_requests <= 0 ||
    max_request_bytes <= 0 {
    return Err(InvalidSettings)
  }
  let (project, job_id, location) = @catalog.query_job_reference(read.job)
  // URL implementations normalize dot segments, including percent escapes.
  // Refuse a changed-identity transport candidate without narrowing Catalog DATA.
  if project == "." || project == ".." {
    return Err(UnrepresentableJob)
  }
  let project = match job_component(project, max_request_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let location = match job_component(location, max_request_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let base = "/bigquery/v2/projects/" + project
  let submit_path = base + "/jobs"
  let status_path = submit_path + "/" + job_id + "?location=" + location
  let results_path = base +
    "/queries/" +
    job_id +
    "?location=" +
    location +
    "&maxResults=" +
    max_results.to_string() +
    "&timeoutMs=" +
    timeout_ms.to_string()
  if submit_path.length() > max_request_bytes ||
    status_path.length() > max_request_bytes ||
    results_path.length() > max_request_bytes {
    return Err(InvalidSettings)
  }
  let material = match
    @catalog.prepare_query_job_material(
      read.prepared.projection,
      read.job,
      maximum_bytes_billed,
      max_request_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Read(Page(issue)))
  }
  read.job_bound = true
  Ok({
    read,
    material,
    submit_path,
    status_path,
    results_path,
    max_requests,
    max_request_bytes,
    issued: 0,
    pending: None,
    pending_response: None,
    next: Some(Submit),
    remote_done: false,
    unknown: false,
  })
}

///|
fn job_live(value : JobRead) -> Bool {
  read_available(value.read) && !value.unknown
}

///|
/// Relate this live Job to its original same-runtime RowRun and acquisition.
/// This observation issues no reservation, request authority, journal COMMIT
/// or cleanup acknowledgement; matching routing DATA is not nominal identity.
pub fn job_read_matches_row_run(
  value : JobRead,
  run : @rows.RowRun,
  acquisition : @rows.RowAcquisition,
) -> Bool {
  job_live(value) &&
  physical_equal(value.read.run, run) &&
  physical_equal(value.read.prepared.acquisition, acquisition)
}

///|
fn[T] fail_job(value : JobRead, issue : JobIssue) -> Result[T, JobIssue] {
  interrupt_result_read(value.read)
  value.next = None
  Err(issue)
}

///|
pub fn next_job_request(value : JobRead) -> Result[JobRequest?, JobIssue] {
  if !job_live(value) {
    return Err(Closed)
  }
  if value.pending is Some(_) || value.pending_response is Some(_) {
    return Err(PendingRequest)
  }
  guard value.next is Some(kind) else { return Ok(None) }
  if value.issued >= value.max_requests {
    return fail_job(value, RequestLimit)
  }
  let (http_method, path, body) = match kind {
    Submit =>
      (
        "POST",
        value.submit_path,
        Some(@catalog.query_job_material_body(value.material)),
      )
    Status => ("GET", value.status_path, None)
    Results(token) => {
      let path = match token {
        None => value.results_path
        Some(token) => {
          let encoded = match job_component(token, value.max_request_bytes) {
            Ok(encoded) => encoded
            Err(issue) => return fail_job(value, issue)
          }
          value.results_path + "&pageToken=" + encoded
        }
      }
      if path.length() > value.max_request_bytes {
        return fail_job(value, InvalidSettings)
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
fn job_original_request(value : JobRead, request : JobRequest) -> Bool {
  physical_equal(value, request.owner) &&
  value.pending is Some(pending) &&
  physical_equal(request, pending)
}

///|
/// This marks the one-shot dispatch attempt, not physical send or execution.
/// Failure after this point must retain the original and cannot repeat POST.
pub fn attempt_job_request(
  value : JobRead,
  request : JobRequest,
) -> Result[Unit, JobIssue] {
  if !job_live(value) {
    return Err(Closed)
  }
  if !job_original_request(value, request) {
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
pub fn job_request_method(request : JobRequest) -> String {
  request.http_method
}

///|
pub fn job_request_path(request : JobRequest) -> String {
  request.path
}

///|
pub fn job_request_body(request : JobRequest) -> String? {
  request.body
}

///|
pub fn job_request_sequence(request : JobRequest) -> Int {
  request.sequence
}

///|
/// Charge the exact physical body before its decoder allocates or parses the
/// provider representation. A lost/malformed decode never permits resending
/// the request, nor does receipt settle its socket or source responsibility.
pub fn charge_job_response(
  value : JobRead,
  request : JobRequest,
  status_code : Int,
  wire_body : Bytes,
) -> Result[JobResponse, JobIssue] {
  if !job_live(value) {
    return Err(Closed)
  }
  if request.observed {
    return Err(AlreadyObserved)
  }
  if !job_original_request(value, request) {
    return Err(WrongRequest)
  }
  if !request.attempted {
    return Err(NotAttempted)
  }
  request.observed = true
  value.pending = None
  let charge = match @rows.charge_row_run_page(value.read.run, wire_body) {
    Ok(value) => value
    Err(issue) => return fail_job(value, Read(Host(issue)))
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
fn consume_job_response(
  value : JobRead,
  response : JobResponse,
) -> Result[Unit, JobIssue] {
  if !job_live(value) {
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
pub fn reject_job_response(
  value : JobRead,
  response : JobResponse,
) -> Result[Unit, JobIssue] {
  match consume_job_response(value, response) {
    Ok(_) => fail_job(value, InvalidResponse)
    Err(issue) => Err(issue)
  }
}

///|
/// The selected physical decoder must preserve the original wire/decoded
/// correspondence. This typed admission is not itself a gzip execution or a
/// proof of current authority, physical allocation or socket retirement.
pub fn accept_charged_job_response(
  value : JobRead,
  response : JobResponse,
  decoded_body : Bytes,
) -> Result[Unit, JobIssue] {
  match consume_job_response(value, response) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let read = value.read
  let request = response.request
  if response.status_code != 200 {
    return fail_job(value, HttpRejected(response.status_code))
  }
  match request.kind {
    Submit | Status => {
      let observation = match
        @catalog.project_query_job_observation(
          value.material,
          decoded_body,
          read.limits,
        ) {
        Ok(value) => value
        Err(issue) => return fail_job(value, Read(Page(issue)))
      }
      guard @catalog.query_job_observation_state(observation, value.material)
        is Some((done, failed)) else {
        return fail_job(value, InvalidResponse)
      }
      match
        @rows.consume_row_run_observation_charge(read.run, response.charge) {
        Ok(_) => ()
        Err(issue) => return fail_job(value, Read(Host(issue)))
      }
      value.remote_done = done
      if failed {
        return fail_job(value, ProviderFailed)
      }
      value.next = Some(if done { Results(None) } else { Status })
    }
    Results(token) => {
      let page = match
        @catalog.project_query_page(
          read.prepared.projection,
          read.job,
          decoded_body,
          read.limits,
        ) {
        Ok(page) => page
        Err(@catalog.QueryPending) => {
          match
            @rows.consume_row_run_observation_charge(read.run, response.charge) {
            Ok(_) => ()
            Err(issue) => return fail_job(value, Read(Host(issue)))
          }
          value.next = Some(Results(token))
          return Ok(())
        }
        Err(issue) => return fail_job(value, Read(Page(issue)))
      }
      match accept_projected_query_page(read, response.charge, token, page) {
        Ok(_) => ()
        Err(issue) => return fail_job(value, Read(issue))
      }
      if result_read_complete(read) {
        match read.custody {
          Original(_) =>
            match finish_result_read(read) {
              Ok(_) => ()
              Err(issue) => return fail_job(value, Read(issue))
            }
          InstalledBorrow(_) => read.finished = true
        }
        value.next = None
      } else {
        value.next = Some(Results(read.next))
      }
    }
  }
  Ok(())
}

///|
/// Convenience for an already bounded identity decoder. Compressed transports
/// must use charge_job_response before decoding, then the same response
/// ticket with accept_charged_job_response.
pub fn accept_job_response(
  value : JobRead,
  request : JobRequest,
  status_code : Int,
  wire_body : Bytes,
  decoded_body : Bytes,
) -> Result[Unit, JobIssue] {
  match charge_job_response(value, request, status_code, wire_body) {
    Ok(response) => accept_charged_job_response(value, response, decoded_body)
    Err(issue) => Err(issue)
  }
}

///|
/// Lost response is not absence, a fresh attempt, provider cancellation, a
/// settled transport or permission to reissue the original request.
pub fn mark_job_response_unknown(
  value : JobRead,
  request : JobRequest,
) -> Result[Unit, JobIssue] {
  if !job_original_request(value, request) {
    return Err(WrongRequest)
  }
  if !request.attempted {
    return Err(NotAttempted)
  }
  request.observed = true
  value.pending = None
  value.unknown = true
  fail_job(value, TransportUnknown)
}

///|
pub fn job_read_complete(value : JobRead) -> Bool {
  job_live(value) &&
  value.read.finished &&
  value.pending_response is None &&
  value.pending is None &&
  value.next is None
}

///|
/// The original routing DATA survives interruption and local reader retirement.
/// It is not launch, retry, stop or settlement authority.
pub fn job_read_original(value : JobRead) -> @catalog.QueryJob {
  value.read.job
}

///|
/// Only a matching provider DONE observation establishes this fact. A socket
/// close, local cleanup or later HTTP refusal cannot establish remote stop.
pub fn job_read_remote_done(value : JobRead) -> Bool {
  value.remote_done
}
