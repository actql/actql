// Provider request/response DATA only. These values do not issue credentials,
// permission, a send claim, a durable receipt, a retry, or job completion.

///|
pub(all) enum JobKind {
  RefreshDataSource
  RunFlow
} derive(Eq, Debug)

///|
pub(all) enum JobIssue {
  InvalidLimits
  InvalidSelection
  CapacityExceeded
  UnexpectedStatus
  InvalidResponse
  ForeignJob
} derive(Eq, Debug)

///|
pub(all) struct JobResponseLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub struct JobStartRequest {
  kind : JobKind
  api_version : String
  site_id : String
  target_id : String
  path : String
}

///|
pub struct StartedJob {
  request : JobStartRequest
  job_id : String
  response_sha256 : String
}

///|
// An exact-job response identity, not a statement that the job completed.
pub struct JobLookupObservation {
  job : StartedJob
  response_sha256 : String
}

///|
fn luid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for index in 0..<36 {
    let c = value[index]
    if index == 8 || index == 13 || index == 18 || index == 23 {
      if c != '-' {
        return false
      }
    } else if !((c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')) {
      return false
    }
  }
  true
}

///|
fn version(value : String) -> Bool {
  let mut dot = -1
  for index in 0..<value.length() {
    let c = value[index]
    if c == '.' {
      if dot != -1 {
        return false
      }
      dot = index
    } else if c < '0' || c > '9' {
      return false
    }
  }
  dot > 0 &&
  dot < value.length() - 1 &&
  !(dot > 1 && value[0] == '0') &&
  !(value.length() - dot > 2 && value[dot + 1] == '0')
}

///|
// The installed provider profile selects the API version and site. This pure
// path projection does not assert that the server supports that version.
pub fn prepare_job_start_request(
  kind : JobKind,
  api_version : String,
  site_id : String,
  target_id : String,
  max_path_bytes : Int,
) -> Result[JobStartRequest, JobIssue] {
  if max_path_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if api_version.length() > max_path_bytes {
    return Err(CapacityExceeded)
  }
  if !version(api_version) || !luid(site_id) || !luid(target_id) {
    return Err(InvalidSelection)
  }
  let (collection, operation) = match kind {
    RefreshDataSource => ("datasources", "refresh")
    RunFlow => ("flows", "run")
  }
  let path = "/api/" +
    api_version +
    "/sites/" +
    site_id +
    "/" +
    collection +
    "/" +
    target_id +
    "/" +
    operation
  // All selected path characters are ASCII; this is its exact byte length.
  if path.length() > max_path_bytes {
    return Err(CapacityExceeded)
  }
  Ok({ kind, api_version, site_id, target_id, path, })
}

///|
pub fn job_start_path(request : JobStartRequest) -> String {
  request.path
}

///|
pub fn job_start_method(_request : JobStartRequest) -> String {
  "POST"
}

///|
// The documented default is full refresh / all flow outputs. No parameter,
// output-step override, incremental flag, idempotency key or CAS is invented.
pub fn job_start_body(request : JobStartRequest) -> String {
  match request.kind {
    RefreshDataSource => "<tsRequest/>"
    RunFlow =>
      // A supplied flow body must name that same selected LUID. The closed
      // LUID alphabet needs no XML escaping; absent output steps means all.
      "<tsRequest><flowRunSpec flowId=\"" +
      request.target_id +
      "\" runMode=\"full\"/></tsRequest>"
  }
}

///|
fn job_type(kind : JobKind) -> String {
  match kind {
    RefreshDataSource => "RefreshExtract"
    RunFlow => "RunFlow"
  }
}

///|
fn object_at(
  object : @decode.ObjectView,
  key : String,
) -> Result[@decode.ObjectView, JobIssue] {
  guard @decode.field(object, key) is Present(value) &&
    @decode.open_object(value) is Ok(child) else {
    return Err(InvalidResponse)
  }
  Ok(child)
}

///|
fn text_at(object : @decode.ObjectView, key : String) -> String? {
  match @decode.field(object, key) {
    Present(value) => @decode.text(value).to_option()
    _ => None
  }
}

///|
fn provider_response_object(
  bytes : Bytes,
  limits : JobResponseLimits,
) -> Result[@decode.ObjectView, JobIssue] {
  if limits.max_bytes <= 0 || limits.max_nodes <= 0 || limits.max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(CapacityExceeded)
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
          InputLimit | NodeLimit | DepthLimit => CapacityExceeded
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
          CapacityExceeded
        } else {
          InvalidResponse
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) else {
    return Err(InvalidResponse)
  }
  Ok(object)
}

///|
fn job_object(
  bytes : Bytes,
  limits : JobResponseLimits,
) -> Result[@decode.ObjectView, JobIssue] {
  match provider_response_object(bytes, limits) {
    Ok(object) => object_at(object, "job")
    Err(issue) => Err(issue)
  }
}

///|
// Call only on a complete response observed for this exact sent request. The
// transport/Effect owner still owns response loss, persistence and Unknown.
pub fn admit_started_job(
  request : JobStartRequest,
  http_status : Int,
  bytes : Bytes,
  limits : JobResponseLimits,
) -> Result[StartedJob, JobIssue] {
  let expected_status = match request.kind {
    RefreshDataSource => 202
    RunFlow => 200
  }
  if http_status != expected_status {
    return Err(UnexpectedStatus)
  }
  let job = match job_object(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard text_at(job, "id") is Some(job_id) &&
    luid(job_id) &&
    text_at(job, "mode") is Some("Asynchronous") &&
    text_at(job, "type") is Some(kind) &&
    kind == job_type(request.kind) else {
    return Err(InvalidResponse)
  }
  let (detail_key, target_key) = match request.kind {
    RefreshDataSource => ("extractRefreshJob", "datasource")
    RunFlow => ("runFlowJobType", "flow")
  }
  let detail = match object_at(job, detail_key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target = match object_at(detail, target_key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard text_at(target, "id") is Some(target_id) else {
    return Err(InvalidResponse)
  }
  if target_id != request.target_id {
    return Err(ForeignJob)
  }
  Ok({ request, job_id, response_sha256: @sha.hex(bytes), })
}

///|
pub fn started_job_id(job : StartedJob) -> String {
  job.job_id
}

///|
pub fn started_job_response_sha256(job : StartedJob) -> String {
  job.response_sha256
}

///|
// A missing initial job id cannot be filled from recent/same-target jobs.
// This API takes only the original admitted response, not a caller's new id.
pub fn job_lookup_path(
  job : StartedJob,
  max_path_bytes : Int,
) -> Result[String, JobIssue] {
  if max_path_bytes <= 0 {
    return Err(InvalidLimits)
  }
  let path = "/api/" +
    job.request.api_version +
    "/sites/" +
    job.request.site_id +
    "/jobs/" +
    job.job_id
  if path.length() > max_path_bytes {
    return Err(CapacityExceeded)
  }
  Ok(path)
}

///|
// A complete Query Job response must name that same original job and type.
// Progress/finishCode/notes are not promoted into completion: Tableau has
// job-type-specific finish semantics (including Bridge refresh exceptions).
pub fn admit_job_lookup_observation(
  job : StartedJob,
  http_status : Int,
  bytes : Bytes,
  limits : JobResponseLimits,
) -> Result[JobLookupObservation, JobIssue] {
  if http_status != 200 {
    return Err(UnexpectedStatus)
  }
  let observed = match job_object(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if text_at(observed, "id") != Some(job.job_id) ||
    text_at(observed, "type") != Some(job_type(job.request.kind)) ||
    text_at(observed, "mode") != Some("Asynchronous") {
    return Err(ForeignJob)
  }
  Ok({ job, response_sha256: @sha.hex(bytes), })
}

///|
pub fn job_lookup_observation_id(observation : JobLookupObservation) -> String {
  observation.job.job_id
}

///|
pub fn job_lookup_response_sha256(observation : JobLookupObservation) -> String {
  observation.response_sha256
}
