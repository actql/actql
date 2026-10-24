///|
pub(all) enum ResidentEffectSourceDispatchIssue {
  Refused(@resident.ResidentDispatchRefusal)
  Materials(@host.ClientEffectRunMaterialsIssue)
  Dispatch(@host.ClientEffectSourceDispatchIssue)
  Source(ResidentSourceIssue)
}

///|
/// Rebuild the original Effect Run and admit only its initial Source dispatch.
/// Every check is performed before physical acquisition. This does not acquire
/// a start claim, approve an Effect or grant execution: the existing journal
/// and runtime must do so, and recheck current authority/lifetime before I/O.
pub fn admit_resident_effect_source_dispatch(
  admission : ResidentRunAdmission,
  effect_limits : @host.ClientEffectComputationLimits,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  request : @remote.DispatchRequest,
  wire : String,
  binding : @remote.RemoteInputBinding,
  now : String,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_contract_body : String,
) -> Result[@host.PreparedClientEffectRun, ResidentEffectSourceDispatchIssue] {
  admit_resident_effect_source_dispatch_owned(
    admission, effect_limits, delegation, site_generation, request, wire, binding,
    now, installed_contracts, values_body, fragment_contract_body,
  ).map(pair => pair.1)
}

///|
fn admit_resident_effect_source_dispatch_owned(
  admission : ResidentRunAdmission,
  effect_limits : @host.ClientEffectComputationLimits,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  request : @remote.DispatchRequest,
  wire : String,
  binding : @remote.RemoteInputBinding,
  now : String,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_contract_body : String,
  require_current? : Bool = true,
) -> Result[
  (@host.ClientEffectRunMaterials, @host.PreparedClientEffectRun),
  ResidentEffectSourceDispatchIssue,
] {
  match
    @resident.check_resident_dispatch_delegation(
      delegation, request, site_generation,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Refused(issue))
  }
  let expected_request = match
    @host.client_effect_source_binding_request(binding, request) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  let materials = match
    @host.admit_client_effect_run_materials(
      wire,
      @remote.dispatch_request_task_scope(request).0,
      admission.expressions,
      admission.operations,
      admission.manifests,
      admission.limits,
      effect_limits,
      expected_request~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Materials(issue))
  }
  let bound = match
    @host.bind_client_effect_source_dispatch(materials, request, binding) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  if require_current &&
    !@host.client_effect_run_start_current(
      materials.allowed,
      materials.run_definition,
      now,
    ) {
    return Err(Refused(@resident.NotCurrent))
  }
  guard admission.source is Some((source_ref, source_contract_cid)) else {
    return Err(Refused(@resident.ForeignSource))
  }
  match
    prepare_resident_effect_source_requirement(
      materials.prepared,
      0,
      0,
      installed_contracts,
      values_body,
      Some(fragment_contract_body),
      source_ref,
      source_contract_cid,
    ) {
    Ok(_) => Ok((materials, bound))
    Err(issue) => Err(Source(issue))
  }
}
