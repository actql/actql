///|
pub(all) enum NativeClientLocalPreparationTargetIssue {
  Original(NativeClientPreparationFenceIssue)
  ForeignCatalog
  Target(@effect_resolution.NativeResidentEffectTargetIssue)
  Request(@catalog.WriteRequestIssue)
}

///|
// Original target material from the same capture and checked Mapping. It is
// not a credential grant, issuer/read decision or mutation approval. Retaining
// identity alone cannot renew its opaque Work token after closure or restart.
struct NativeClientLocalPreparationTarget {
  fence : NativeClientEffectPreparationFence
  binding : @catalog.LocalCatalogObservationBinding
  catalog : @catalog.CatalogObservation
  request : @catalog.LocalTargetReadRequest
  row_index : Int
}

///|
fn local_preparation_catalog_matches_original(
  identity : @credential.LocalPreparationFenceIdentity,
  binding : @catalog.LocalCatalogObservationBinding,
) -> Bool {
  let fields = @credential.local_preparation_fence_fields(identity)
  fields.client_request_intent_cid == binding.client_request_intent_cid &&
  fields.client_request_scope_cid == binding.client_request_scope_cid &&
  fields.run_invocation_cid == binding.run_invocation_cid
}

///|
fn NativeClientLocalPreparationTarget::require_current(
  self : NativeClientLocalPreparationTarget,
) -> Result[Unit, NativeClientLocalPreparationTargetIssue] {
  match self.fence.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  if self.row_index < 0 ||
    !local_preparation_catalog_matches_original(
      self.fence.identity,
      self.binding,
    ) ||
    !@catalog.catalog_observation_matches_local_binding(
      self.catalog,
      self.binding,
    ) ||
    @catalog.local_target_read_request_binding(self.request) != self.binding ||
    @catalog.recheck_single_write_request(
      @catalog.local_target_read_request_candidate(self.request),
      self.catalog,
    )
    is Err(_) {
    return Err(ForeignCatalog)
  }
  self.fence.require_current().map_err(issue => Original(issue))
}

///|
/// Visit the original captured proposals through the existing checked request
/// Owner. No selector, body, occurrence or capture index is supplied by a CLI
/// caller. Trusted installation/current Catalog admission remains independent.
/// The callback receives identity material only; issuance and I/O must use
/// their separate current permissions and durable acknowledgements.
pub fn NativeClientEffectPreparationFence::visit_local_targets(
  self : NativeClientEffectPreparationFence,
  binding : @catalog.LocalCatalogObservationBinding,
  current_catalog : @catalog.CatalogObservation,
  mapping : @catalog.ExecutionMapping,
  projection : @catalog.WriteProjection,
  api_version : String,
  credential_org_id : String,
  export_limits : @host.PublicationOutputExportLimits,
  body_limits : @catalog.WriteBodyLimits,
  request_limits : @catalog.WriteRequestLimits,
  max_identity_bytes : Int,
  max_rows : Int,
  max_fields : Int,
  max_work : Int,
  max_utf16_units : Int,
  accept : (NativeClientLocalPreparationTarget) -> Result[
    Unit,
    NativeClientLocalPreparationTargetIssue,
  ],
) -> Result[Int, NativeClientLocalPreparationTargetIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  if !local_preparation_catalog_matches_original(self.identity, binding) ||
    !@catalog.catalog_observation_matches_local_binding(
      current_catalog, binding,
    ) {
    return Err(ForeignCatalog)
  }
  guard self.context.facts() is Some(facts) else {
    return Err(Original(Unavailable))
  }
  let mut own_failure : NativeClientLocalPreparationTargetIssue? = None
  let current = () => {
    match self.require_current() {
      Ok(_) => true
      Err(issue) => {
        own_failure = Some(Original(issue))
        false
      }
    }
  }
  let visited = @effect_resolution.visit_native_effect_target_requests(
    self.work.owner,
    self.work.materials,
    self.inputs,
    self.stage,
    self.effect_id,
    facts.consumer_index,
    mapping,
    projection,
    api_version,
    export_limits,
    body_limits,
    request_limits,
    max_rows,
    max_fields,
    max_work,
    max_utf16_units,
    current,
    (index, candidate) => {
      let request = match
        @catalog.prepare_local_target_read_request(
          candidate, binding, current_catalog, credential_org_id, max_identity_bytes,
        ) {
        Ok(value) => value
        Err(issue) => {
          own_failure = Some(Request(issue))
          return Err(@effect_resolution.ForeignMapping)
        }
      }
      let target : NativeClientLocalPreparationTarget = {
        fence: self,
        binding,
        catalog: current_catalog,
        request,
        row_index: index,
      }
      let received = match target.require_current() {
        Ok(_) => accept(target)
        Err(issue) => Err(issue)
      }
      match received {
        Ok(_) => ()
        Err(issue) => {
          own_failure = Some(issue)
          return Err(@effect_resolution.ForeignMapping)
        }
      }
      match target.require_current() {
        Ok(_) => Ok(())
        Err(issue) => {
          own_failure = Some(issue)
          Err(@effect_resolution.ForeignMapping)
        }
      }
    },
  )
  match visited {
    Ok(count) => Ok(count)
    Err(issue) => Err(own_failure.unwrap_or(Target(issue)))
  }
}

///|
/// Project the exact original call identity through its still-live Work. This
/// performs no grant issuance, new start, allowance refresh or Provider entry.
pub fn NativeClientLocalPreparationTarget::credential_scope(
  self : NativeClientLocalPreparationTarget,
  attempt_id : String,
) -> Result[
  @credential.LocalPreparationCredentialScope,
  NativeClientLocalPreparationTargetIssue,
] {
  self
  .require_current()
  .map(_ => {
    let fields = @credential.local_preparation_fence_fields(self.fence.identity)
    {
      account_configuration_cid: self.binding.account_configuration_cid,
      account_id: self.binding.account_id,
      attempt_id,
      authority_scope_cid: self.binding.authority_scope_cid,
      connector_registration: self.binding.connector_registration,
      connector_revision: self.binding.connector_revision,
      preparation_fence: self.fence.identity,
      host_adoption_cid: self.binding.host_adoption_cid,
      operation: "salesforce:record:observe",
      operation_occurrence_cid: fields.operation_occurrence_cid,
      principal: self.binding.principal,
      request_body_cid: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      request_cid: @catalog.local_target_read_request_cid(self.request),
      request_method: "GET",
      request_path: @catalog.local_target_read_request_path(self.request),
      resource_origin: self.binding.resource_origin,
      run_invocation_cid: fields.run_invocation_cid,
      submission_scope_cid: fields.client_request_scope_cid,
      unit_definition_cid: fields.unit_definition_cid,
    }
  })
}
