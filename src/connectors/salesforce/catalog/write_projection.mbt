///|
pub(all) enum WriteOperation {
  WriteCreate
  WriteUpdateById
  WriteUpsertByExternalId(String)
} derive(Eq, Debug)

///|
pub(all) enum WriteProjectionIssue {
  Observation(CatalogObservationIssue)
  Requirement(ResourceRequirementIssue)
  FieldLimit
  EmptyUpdate
  TargetFieldInBody(String)
} derive(Eq, Debug)

///|
/// A pure candidate from one exact Resource Catalog observation. This is not
/// an Effect preview, current grant, write attempt, or dispatch permission.
pub struct WriteProjection {
  observation_cid : String
  binding : CatalogObservationBinding
  resource : String
  operation : WriteOperation
  field_names : Array[String]
}

///|
pub fn prepare_write_projection(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  resource_name : String,
  operation : WriteOperation,
  field_names : Array[String],
  max_fields : Int,
) -> Result[WriteProjection, WriteProjectionIssue] {
  if max_fields < 0 || field_names.length() > max_fields {
    return Err(FieldLimit)
  }
  let resource = match
    catalog_observation_resource(observation, current, resource_name) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let admitted = match operation {
    WriteCreate => require_create_fields(resource, field_names)
    WriteUpdateById => {
      if field_names.is_empty() {
        return Err(EmptyUpdate)
      }
      require_update_fields(resource, field_names)
    }
    WriteUpsertByExternalId(target) => {
      if field_names.is_empty() {
        return Err(EmptyUpdate)
      }
      if field_names.contains(target) {
        return Err(TargetFieldInBody(target))
      }
      require_upsert_fields(resource, target, field_names)
    }
  }
  if admitted is Err(issue) {
    return Err(Requirement(issue))
  }
  Ok({
    observation_cid: catalog_observation_identity(observation),
    binding: current,
    resource: resource.name,
    operation,
    field_names: field_names.copy(),
  })
}

///|
pub fn write_projection_observation(value : WriteProjection) -> String {
  value.observation_cid
}

///|
pub fn write_projection_resource(value : WriteProjection) -> String {
  value.resource
}

///|
pub fn write_projection_operation(value : WriteProjection) -> WriteOperation {
  value.operation
}

///|
pub fn write_projection_fields(value : WriteProjection) -> Array[String] {
  value.field_names.copy()
}

///|
pub fn write_projection_matches_binding(
  value : WriteProjection,
  current : CatalogObservationBinding,
) -> Bool {
  value.binding == current
}
