///|
pub(all) struct JobRecordLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_job_bytes : Int
  max_material_bytes : Int
}

///|
pub(all) enum JobRecordIssue {
  InvalidLimits
  Limit
  InvalidRecord
  Closed
  NotOriginalSubmit
} derive(Eq, Debug)

///|
/// Closed DATA only. It cannot restore a JobRead, original Run or permission.
/// The existing Journal must bind it to its original accepted task and epoch.
pub struct JobOriginalRecord {
  priv job : @catalog.QueryJob
  priv path : String
  priv body : String
  priv wire : String
}

///|
fn valid_job_record_limits(limits : JobRecordLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_job_bytes > 0 &&
  limits.max_material_bytes > 0
}

///|
fn build_job_original_record(
  job : @catalog.QueryJob,
  path : String,
  body : String,
  limits : JobRecordLimits,
) -> Result[JobOriginalRecord, JobRecordIssue] {
  if !valid_job_record_limits(limits) {
    return Err(InvalidLimits)
  }
  let (project, job_id, location) = @catalog.query_job_reference(job)
  if @catalog.query_job(project, job_id, location, limits.max_job_bytes)
    is Err(_) {
    return Err(InvalidRecord)
  }
  let mut remaining = limits.max_material_bytes
  for text in [path, body] {
    match @scalar.admit_utf8_length(text, remaining) {
      Ok(size) => remaining -= size
      Err(_) => return Err(Limit)
    }
  }
  // Share the original transport component encoder. A closed DATA projection
  // must not change the same project's one-segment POST route.
  if project == "." || project == ".." {
    return Err(InvalidRecord)
  }
  let encoded = match job_component(project, limits.max_material_bytes) {
    Ok(value) => value
    Err(_) => return Err(Limit)
  }
  if path != "/bigquery/v2/projects/" + encoded + "/jobs" {
    return Err(InvalidRecord)
  }
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  try {
    @encode.begin_ordered_object(writer)
    for
      (key, value) in [
        ("body", body),
        ("format", "actql.bigquery-job-original/0.1"),
        ("jobId", job_id),
        ("location", location),
        ("method", "POST"),
        ("path", path),
        ("project", project),
      ] {
      @encode.ordered_key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok({ job, path, body, wire: @encode.finish(writer), })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(Limit)
    }
  }
}

///|
/// Snapshot the same live Job before its original POST is attempted. This
/// neither issues a request nor marks an attempt or confirms journal storage.
pub fn job_original_record(
  value : JobRead,
  limits : JobRecordLimits,
) -> Result[JobOriginalRecord, JobRecordIssue] {
  if !job_live(value) {
    return Err(Closed)
  }
  let first = match value.pending {
    Some(request) =>
      value.issued == 1 &&
      request.sequence == 0 &&
      request.kind is Submit &&
      !request.attempted &&
      !request.observed &&
      job_original_request(value, request)
    None => value.issued == 0 && value.next is Some(Submit)
  }
  if !first || value.pending_response is Some(_) {
    return Err(NotOriginalSubmit)
  }
  build_job_original_record(
    job_read_original(value),
    value.submit_path,
    @catalog.query_job_material_body(value.material),
    limits,
  )
}

///|
pub fn job_original_record_wire(value : JobOriginalRecord) -> String {
  value.wire
}

///|
pub fn job_original_record_material(
  value : JobOriginalRecord,
) -> (String, String, String, String, String, String) {
  let (project, job_id, location) = @catalog.query_job_reference(value.job)
  (project, job_id, location, "POST", value.path, value.body)
}

///|
fn job_record_text(object : @decode.ObjectView, key : String) -> String? {
  match @decode.lookup(object, key) {
    Some(value) => @decode.text(value).to_option()
    None => None
  }
}

///|
/// Bounded cold DATA observation. It establishes no original custody/current,
/// Run, reservation, launch, stop or settlement, even for byte-equal material.
pub fn read_job_original_record(
  bytes : Bytes,
  limits : JobRecordLimits,
) -> Result[JobOriginalRecord, JobRecordIssue] {
  if !valid_job_record_limits(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(Limit)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err({ issue: InputLimit | NodeLimit | DepthLimit, .. }) => return Err(Limit)
    Err(_) => return Err(InvalidRecord)
  }
  guard @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.closed_object(root, [
      "body", "format", "jobId", "location", "method", "path", "project",
    ])
    is Ok(object) &&
    job_record_text(object, "format") == Some("actql.bigquery-job-original/0.1") &&
    job_record_text(object, "method") == Some("POST") &&
    job_record_text(object, "project") is Some(project) &&
    job_record_text(object, "jobId") is Some(job_id) &&
    job_record_text(object, "location") is Some(location) &&
    job_record_text(object, "path") is Some(path) &&
    job_record_text(object, "body") is Some(body) else {
    return Err(InvalidRecord)
  }
  let job = match
    @catalog.query_job(project, job_id, location, limits.max_job_bytes) {
    Ok(value) => value
    Err(_) => return Err(InvalidRecord)
  }
  build_job_original_record(job, path, body, limits)
}

///|
/// Compare DATA to the actual nominal first request of this live Job. A true
/// result is not a COMMIT receipt or dispatch authority. The Host must confirm
/// its same-owner journal CAS before invoking the existing AttemptRequest.
pub fn job_original_record_matches_request(
  value : JobRead,
  request : JobRequest,
  record : JobOriginalRecord,
) -> Bool {
  job_live(value) &&
  job_original_request(value, request) &&
  request.kind is Submit &&
  request.sequence == 0 &&
  !request.attempted &&
  !request.observed &&
  @catalog.query_job_reference(job_read_original(value)) ==
  @catalog.query_job_reference(record.job) &&
  request.http_method == "POST" &&
  request.path == record.path &&
  request.body == Some(record.body)
}
