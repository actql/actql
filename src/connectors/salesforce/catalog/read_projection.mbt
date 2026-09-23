///|
pub(all) enum ReadProjectionIssue {
  Observation(CatalogObservationIssue)
  Requirement(ResourceRequirementIssue)
  EmptyProjection
  QueryLimit
} derive(Eq, Debug)

///|
/// A provider-specific, pure candidate derived from one supplied observation.
/// It grants neither current source authority nor an executable acquisition.
pub struct ReadProjection {
  observation_cid : String
  binding : CatalogObservationBinding
  resource : String
  fields : Array[FieldMetadata]
  soql : String
}

///|
pub fn prepare_read_projection(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  resource_name : String,
  field_names : Array[String],
  max_soql_bytes : Int,
) -> Result[ReadProjection, ReadProjectionIssue] {
  let resource = match
    catalog_observation_resource(observation, current, resource_name) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if field_names.is_empty() {
    return Err(EmptyProjection)
  }
  let fields = match require_read_fields(resource, field_names) {
    Ok(value) => value
    Err(issue) => return Err(Requirement(issue))
  }
  // All identifiers came from the bounded describe projection. Its API-name
  // grammar excludes SOQL punctuation; no caller text is interpolated here.
  let mut bytes = 13 + resource.name.length()
  if max_soql_bytes < bytes {
    return Err(QueryLimit)
  }
  for field in fields {
    if field.name.length() > max_soql_bytes - bytes {
      return Err(QueryLimit)
    }
    bytes += field.name.length()
  }
  if fields.length() - 1 > max_soql_bytes - bytes {
    return Err(QueryLimit)
  }
  bytes += fields.length() - 1
  let sql = StringBuilder()
  sql.write_string("SELECT ")
  for index in 0..<fields.length() {
    if index != 0 {
      sql.write_string(",")
    }
    sql.write_string(fields[index].name)
  }
  sql.write_string(" FROM ")
  sql.write_string(resource.name)
  Ok({
    observation_cid: observation.cid,
    binding: current,
    resource: resource.name,
    fields,
    soql: sql.to_string(),
  })
}

///|
pub fn read_projection_soql(plan : ReadProjection) -> String {
  plan.soql
}

///|
pub fn read_projection_observation(plan : ReadProjection) -> String {
  plan.observation_cid
}

///|
/// The physical credential use must belong to the same observed Site and
/// dispatch. Credential control separately verifies the signed grant and
/// its current use conditions.
pub fn read_projection_matches_site_scope(
  plan : ReadProjection,
  tenant : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  let binding = plan.binding
  binding.tenant == tenant &&
  binding.principal == principal &&
  binding.environment == environment &&
  binding.site_key == site_key &&
  binding.site_generation == site_generation &&
  binding.connector_registration == connector_registration &&
  binding.connector_revision == connector_revision &&
  binding.resource_origin == resource_origin &&
  binding.run_invocation_cid == run_invocation_cid &&
  binding.dispatch_request_cid == dispatch_request_cid
}

///|
pub fn read_projection_fields(plan : ReadProjection) -> Array[String] {
  let names = []
  for field in plan.fields {
    names.push(field.name)
  }
  names
}
