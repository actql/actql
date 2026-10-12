///|
/// Configure the original source-free plan on the installed Host root. This
/// introduces no Source, replacement Ledger, admission or dispatch decision.
pub fn configure_source_free_local_compute_on_ledger(
  plan : LocalRunPlan,
  ledger : @resources.Ledger,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  if !source_free_profile(plan.prepared) {
    return Err(UnsupportedCapability)
  }
  guard @local.open_source_free_local_retained_host_on_ledger(
      plan.prepared,
      ledger,
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(setup) else {
    return Err(Configuration)
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  @strategy.require_captured_task_activation(run)
  Ok({ plan, setup, })
}
