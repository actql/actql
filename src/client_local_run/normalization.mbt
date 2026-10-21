///|
pub(all) enum LocalRunNormalizationIssue {
  Binding(@host.ClientTaskRunBindingIssue)
  Normalization(@host.ClientLocalNormalizationIssue)
  ForeignPlan
}

///|
/// Original admission and compiled Plan retain the original checked audit.
/// This is neither durable publication nor restoration of a saved Run.
pub struct LocalRunNormalization {
  plan : LocalRunPlan
  original : @host.ClientLocalNormalization
}

///|
pub fn issue_local_run_normalization(
  plan : LocalRunPlan,
) -> Result[LocalRunNormalization, LocalRunNormalizationIssue] {
  match
    @host.bind_client_task_run(
      plan.prepared,
      plan.compilation,
      plan.admission,
      plan.definition,
    ) {
    Err(issue) => return Err(Binding(issue))
    Ok(_) => ()
  }
  @host.issue_prepared_client_local_normalization(plan.prepared)
  .map(original => { plan, original, })
  .map_err(issue => Normalization(issue))
}

///|
pub fn local_run_normalization_evidence(
  plan : LocalRunPlan,
  value : LocalRunNormalization,
) -> Result[@publication.RunEvidenceValue, LocalRunNormalizationIssue] {
  if !physical_equal(plan, value.plan) {
    return Err(ForeignPlan)
  }
  @host.prepared_client_local_normalization_evidence(
    plan.prepared,
    value.original,
  ).map_err(issue => Normalization(issue))
}

///|
/// Match saved journal bytes only against retained original preparation,
/// reusing its admitted typed evidence after exact correspondence checks.
/// Cross-process adoption of durable materials remains a separate Owner path.
pub fn restore_local_run_normalization_evidence(
  plan : LocalRunPlan,
  value : LocalRunNormalization,
  wire : String,
  catalog_cid : String,
) -> Result[@publication.RunEvidenceValue, LocalRunNormalizationIssue] {
  if !physical_equal(plan, value.plan) {
    return Err(ForeignPlan)
  }
  @host.restore_prepared_client_local_normalization(
    plan.prepared,
    value.original,
    wire,
    catalog_cid,
  ).map_err(issue => Normalization(issue))
}
