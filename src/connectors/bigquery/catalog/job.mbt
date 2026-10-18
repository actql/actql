///|
/// Bounded original query request material. No credential, launch, capacity or
/// recovery authority is issued by constructing or observing this DATA.
pub struct QueryJobMaterial {
  priv job : QueryJob
  priv sql : String
  priv maximum_bytes_billed : Int64
  priv body : String
}

///|
pub struct QueryJobObservation {
  priv original : QueryJobMaterial
  priv done : Bool
  priv failed : Bool
  priv response_sha256 : String
}

///|
fn quoted_query_identifier(value : String) -> String {
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  out.write_char('`')
  for character in value.to_array() {
    let code = character.to_int()
    if character == '\\' || character == '`' {
      out.write_char('\\')
      out.write_char(character)
    } else if code < 32 || code == 127 {
      out.write_string("\\x")
      out.write_char(hex[code / 16].to_int().to_char().unwrap())
      out.write_char(hex[code % 16].to_int().to_char().unwrap())
    } else {
      out.write_char(character)
    }
  }
  out.write_char('`')
  out.to_string()
}

///|
/// Emit only the original selected fields and table. This is not caller SQL.
pub fn read_projection_statement(value : ReadProjection) -> String {
  let target = value.original.target
  "SELECT " + value.fields.map(quoted_query_identifier).join(", ") +
  " FROM " + [target.project, target.dataset, target.table]
  .map(quoted_query_identifier).join(".")
}

///|
pub fn query_job_reference(value : QueryJob) -> (String, String, String) {
  (value.project, value.job_id, value.location)
}

///|
pub fn prepare_query_job_material(
  projection : ReadProjection,
  job : QueryJob,
  maximum_bytes_billed : Int64,
  max_bytes : Int,
) -> Result[QueryJobMaterial, QueryIssue] {
  if max_bytes <= 0 || maximum_bytes_billed < 0L {
    return Err(InvalidQueryLimits)
  }
  let sql = read_projection_statement(projection)
  try {
    let writer = @encode.writer(max_bytes, 32, 8)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "configuration")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "query")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "maximumBytesBilled")
    @encode.string_value(writer, maximum_bytes_billed.to_string())
    @encode.ordered_key(writer, "query")
    @encode.string_value(writer, sql)
    @encode.ordered_key(writer, "useLegacySql")
    @encode.bool_value(writer, false)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.ordered_key(writer, "jobReference")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "jobId")
    @encode.string_value(writer, job.job_id)
    @encode.ordered_key(writer, "location")
    @encode.string_value(writer, job.location)
    @encode.ordered_key(writer, "projectId")
    @encode.string_value(writer, job.project)
    @encode.end_object(writer)
    @encode.end_object(writer)
    Ok({ job, sql, maximum_bytes_billed, body: @encode.finish(writer), })
  } catch {
    _ => Err(QueryLimit)
  }
}

///|
pub fn query_job_material_body(value : QueryJobMaterial) -> String {
  value.body
}

///|
fn matches_job_reference(object : @decode.ObjectView, job : QueryJob) -> Bool {
  let location = match @decode.lookup(object, "location") {
    None => Some("US")
    Some(_) => required_text(object, "location")
  }
  required_text(object, "projectId") == Some(job.project) &&
  required_text(object, "jobId") == Some(job.job_id) &&
  location == Some(job.location)
}

///|
/// Status is admitted only for the same Job and submitted configuration.
/// DONE confirms provider execution ended, but errorResult still means failure;
/// warnings alone never become a final failure or successful result receipt.
pub fn project_query_job_observation(
  original : QueryJobMaterial,
  bytes : Bytes,
  limits : QueryLimits,
) -> Result[QueryJobObservation, QueryIssue] {
  let root = match query_root(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(root) is Ok(object) &&
    required_text(object, "kind") == Some("bigquery#job") &&
    @decode.lookup(object, "jobReference") is Some(reference) &&
    @decode.open_object(reference) is Ok(reference) else {
    return Err(InvalidQueryResponse)
  }
  if !matches_job_reference(reference, original.job) {
    return Err(ForeignQueryJob)
  }
  guard @decode.lookup(object, "configuration") is Some(configuration) &&
    @decode.open_object(configuration) is Ok(configuration) &&
    @decode.lookup(configuration, "query") is Some(query) &&
    @decode.open_object(query) is Ok(query) &&
    required_text(query, "query") == Some(original.sql) &&
    required_text(query, "maximumBytesBilled") ==
      Some(original.maximum_bytes_billed.to_string()) &&
    @decode.lookup(query, "useLegacySql") is Some(legacy) &&
    @decode.boolean(legacy) is Ok(false) else {
    return Err(ForeignQueryJob)
  }
  guard @decode.lookup(object, "status") is Some(status) &&
    @decode.open_object(status) is Ok(status) &&
    required_text(status, "state") is Some(state) &&
    ["PENDING", "RUNNING", "DONE"].contains(state) else {
    return Err(InvalidQueryResponse)
  }
  let failed = @decode.lookup(status, "errorResult") is Some(_)
  if failed && state != "DONE" {
    return Err(InvalidQueryResponse)
  }
  if @decode.lookup(status, "errorResult") is Some(error) {
    guard @decode.open_object(error) is Ok(error) &&
      required_text(error, "reason") is Some(_) else {
      return Err(InvalidQueryResponse)
    }
  }
  Ok({
    original,
    done: state == "DONE",
    failed,
    response_sha256: @sha.hex(bytes),
  })
}

///|
pub fn query_job_observation_state(
  value : QueryJobObservation,
  original : QueryJobMaterial,
) -> (Bool, Bool)? {
  if physical_equal(value.original, original) {
    Some((value.done, value.failed))
  } else {
    None
  }
}

///|
pub fn query_job_observation_sha256(value : QueryJobObservation) -> String {
  value.response_sha256
}
