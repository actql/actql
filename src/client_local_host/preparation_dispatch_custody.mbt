///|
/// Register the fixed ordinary Local dispatch's dependency on the original
/// preparation before opening its configured Host. The holder covers that
/// Host's modules, operation closures and transitive completed-output anchors
/// until physical/output cleanup AND private alias severance have completed.
/// It is not a new byte grant, a stop acknowledgement, or a generic low-level
/// execution lifetime. A legacy Run without a preparation owner returns None.
pub fn borrow_installed_managed_dispatch_preparation(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram]?,
  ClientInstalledManagedRunIssue,
] {
  match check_installed_managed_run(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.preparation_retirement is Some(custody) else { return Ok(None) }
  guard custody is PurePreparation(original) else {
    return Err(ForeignOriginal)
  }
  guard original.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return Err(Retired)
  }
  // Sibling acquisition rechecks the same original Resource currentness and
  // claims its live borrower slot before callbacks; no adapter-owned count.
  match @resources.borrow_preparation_body_sibling(holder) {
    Ok(borrowed) => Ok(Some(borrowed))
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      Err(Ledger(issue))
    Err(_) => Err(CleanupPending)
  }
}

///|
/// Accounting correspondence for an already stopped fixed ordinary Host. The
/// captured DAG must use this exact Run Ledger, not an equal numeric profile.
/// A true result still requires the caller's actual stop/output-close proof.
pub fn installed_managed_preparation_usage_isolated(
  value : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedDAG,
) -> Bool {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    physical_equal(value.request, request) &&
    value.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(captured)) &&
    value.preparation_retirement is Some(retirement) else {
    return false
  }
  match retirement {
    PurePreparation(original) =>
      @resources.prepared_run_usage_isolated(original.admission, ledger)
    EffectPlanPreparation(original) =>
      @resources.prepared_run_usage_isolated(original.admission, ledger)
  }
}

///|
/// The selected Effect dispatch and its operations borrow the same plan body
/// before opening the Host. No equal Program/request or copied plan can select
/// this holder; retirement fences new siblings on the existing capacity owner.
pub fn borrow_installed_effect_dispatch_preparation(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan]?,
  ClientInstalledManagedRunIssue,
] {
  guard value.preparation is Some(PlannedEffectManaged(_, original)) &&
    physical_equal(original, plan) &&
    physical_equal(value.request, request) else {
    return Err(ForeignOriginal)
  }
  match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.preparation_retirement is Some(custody) else { return Ok(None) }
  guard custody is EffectPlanPreparation(original) &&
    original.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, plan) &&
    !@resources.preparation_body_retirement_started(holder) else {
    return Err(Retired)
  }
  match @resources.borrow_preparation_body_sibling(holder) {
    Ok(borrowed) => Ok(Some(borrowed))
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      Err(Ledger(issue))
    Err(_) => Err(CleanupPending)
  }
}
