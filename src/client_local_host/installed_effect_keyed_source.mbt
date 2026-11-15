///|
// Observe the existing managed parent's current admission, then validate the
// same checked Source binding after that callback. Historical receipt DATA
// and an equal request wire cannot replace this original keyed request.
fn installed_effect_keyed_source_ledger(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  original : @publication_host.ClientEffectKeyedOriginal,
  request : @publication_host.ClientKeyedRequest,
) -> Result[@resources.Ledger, ClientInstalledSourceReadIssue] {
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(ManagedRun(issue))
    Ok(value) => value
  }
  guard value.preparation is Some(PlannedEffectManaged(_, selected)) &&
    physical_equal(selected, plan) &&
    plan.model is None &&
    physical_equal(value.request, plan.request) &&
    plan.keyed_original is Some(retained) &&
    physical_equal(retained, original) &&
    @publication_host.client_effect_keyed_request_retained_parent(
      request, original, ledger,
    ) else {
    return Err(ForeignOriginal)
  }
  Ok(ledger)
}

///|
/// The Source-only case uses the same spent-request history, accounted Row
/// receiver and physical retirement engine as the existing Pure/Model cases.
/// Its opaque original comes from this Run's Request preparation, not a Model
/// graph or caller-provided current flag.
pub fn begin_installed_managed_effect_keyed_source_read(
  value : ClientInstalledManagedRun,
  keyed : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  declaration : @row_source_host.RowDeclaration,
  row_limits : @row_source_host.RowKeyedLimits,
) -> Result[ClientInstalledKeyedSourceRead, ClientInstalledSourceReadIssue] {
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(ManagedRun(issue))
    Ok(value) => value
  }
  guard value.preparation is Some(PlannedEffectManaged(_, plan)) &&
    plan.model is None &&
    plan.keyed_original is Some(original) &&
    @publication_host.client_keyed_acquisition_matches_effect_program(
      keyed,
      plan.prepared,
    ) &&
    @publication_host.client_effect_keyed_request_matches_parent(
      request, original, ledger,
    ) &&
    @publication_host.client_effect_keyed_request_rows(
      request, original, ledger,
    )
    is Some(max_requests) &&
    max_requests > 0 &&
    @publication_host.client_keyed_request_value(request, keyed) is Some(input) else {
    return Err(ForeignOriginal)
  }
  match installed_keyed_source_request_available(value, request, max_requests) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let acquisition = match
    @row_source_host.prepare_keyed_row_acquisition(
      @publication_host.client_keyed_acquisition_owner(keyed),
      @publication_host.client_keyed_acquisition_facts(keyed),
      input,
      declaration,
      row_limits,
      input_available=Some(() => {
        installed_effect_keyed_source_ledger(value, plan, original, request)
        is Ok(_)
      }),
    ) {
    Err(issue) => return Err(Acquisition(issue))
    Ok(value) => value
  }
  match installed_effect_keyed_source_ledger(value, plan, original, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Reentrant current/reader preparation may have spent this request. Never
  // publish another receiver or reset its cumulative request allowance.
  match installed_keyed_source_request_available(value, request, max_requests) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let read : ClientInstalledKeyedSourceRead = {
    original: None,
    parent: Some(value),
    selected: None,
    model: None,
    request: Some(request),
    acquisition: Some(acquisition),
    run: None,
    start: Unstarted,
    retired: false,
  }
  read.original = Some(read)
  value.keyed_reads.push(read)
  Ok(read)
}
