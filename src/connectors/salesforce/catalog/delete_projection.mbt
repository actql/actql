///|
pub(all) enum DeleteProjectionIssue {
  Observation(CatalogObservationIssue)
  DeletionNotProved
  NoRecordIdentity
  ForeignCurrentObservation
} derive(Eq, Debug)

///|
// One pure operation projection from an original Describe observation. This
// proves neither current authority nor the before/version/absence facts of a
// sealed DELETE Preview, and carries no proposed value or writable fields.
pub struct DeleteProjection {
  observation_cid : String
  binding : CatalogExecutionBinding
  resource : String
}

///|
pub fn prepare_delete_projection(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  resource : String,
) -> Result[DeleteProjection, DeleteProjectionIssue] {
  prepare_owned_delete_projection(observation, SiteCatalog(current), resource)
}

///|
pub fn prepare_local_delete_projection(
  observation : CatalogObservation,
  current : LocalCatalogObservationBinding,
  resource : String,
) -> Result[DeleteProjection, DeleteProjectionIssue] {
  prepare_owned_delete_projection(
    observation,
    DirectLocalCatalog(current),
    resource,
  )
}

///|
fn prepare_owned_delete_projection(
  observation : CatalogObservation,
  current : CatalogExecutionBinding,
  resource_name : String,
) -> Result[DeleteProjection, DeleteProjectionIssue] {
  let resource = match
    catalog_owned_observation_resource(observation, current, resource_name) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if resource.deletable != Some(true) {
    return Err(DeletionNotProved)
  }
  if !record_identity(resource) {
    return Err(NoRecordIdentity)
  }
  Ok({
    observation_cid: observation.cid,
    binding: current,
    resource: resource.name,
  })
}

///|
// Keep the existing Site/Local execution-binding rule. A new refresh may use
// its own observation occurrence, but never another org, connection revision,
// original Run or authority scope. The operation still needs its own grant.
pub fn recheck_delete_projection(
  value : DeleteProjection,
  current : CatalogObservation,
) -> Result[Unit, DeleteProjectionIssue] {
  if !catalog_execution_binding_matches(value.binding, current.binding) {
    return Err(ForeignCurrentObservation)
  }
  prepare_owned_delete_projection(current, current.binding, value.resource).map(_ => {
      ()
    },
  )
}

///|
pub fn delete_projection_observation(value : DeleteProjection) -> String {
  value.observation_cid
}

///|
pub fn delete_projection_resource(value : DeleteProjection) -> String {
  value.resource
}

///|
pub fn delete_projection_matches_binding(
  value : DeleteProjection,
  current : CatalogObservationBinding,
) -> Bool {
  value.binding == SiteCatalog(current)
}

///|
pub fn delete_projection_matches_local_binding(
  value : DeleteProjection,
  current : LocalCatalogObservationBinding,
) -> Bool {
  value.binding == DirectLocalCatalog(current)
}
