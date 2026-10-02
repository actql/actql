///|
/// Bind the installed physical reservation envelope before any prefix work.
/// This cannot authorize Model dispatch; the existing account and dependency
/// admission remain independent. The selected execution Contract is a ceiling,
/// not a request to widen a smaller installed Host budget.
pub fn bind_quantity_capacity(
  active : Execution,
  installed : @model.ModelQuantityCapacity,
) -> Result[Unit, Issue] {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.source is Physical(_)) ||
    !(active.phase is Input) ||
    active.work != 0L ||
    active.quantity_capacity is Some(_) {
    return Err(InvalidAdvance)
  }
  guard active.plan is Some(plan) else {
    return Err(Model(@model.RequestIdentity))
  }
  if installed.limits.tokens < 0L ||
    installed.limits.cost_units < 0L ||
    installed.limits.duration_ms < 0L ||
    installed.per_attempt.tokens < 0L ||
    installed.per_attempt.cost_units < 0L ||
    installed.per_attempt.duration_ms < 0L ||
    installed.per_attempt.tokens > 9007199254740991L ||
    installed.per_attempt.cost_units > 9007199254740991L ||
    installed.per_attempt.duration_ms > 9007199254740991L {
    return Err(Model(@model.InvalidLimits))
  }
  let execution = @publication_host.client_infer_plan_graph_execution_contract(
    plan,
  )
  active.quantity_capacity = Some({
    ..installed,
    limits: {
      tokens: Int64::min(
        installed.limits.tokens,
        @environment.model_execution_ceiling(
          execution,
          @environment.TotalTokenReservation,
        ),
      ),
      cost_units: Int64::min(
        installed.limits.cost_units,
        @environment.model_execution_ceiling(
          execution,
          @environment.TotalCostUnits,
        ),
      ),
      duration_ms: Int64::min(
        installed.limits.duration_ms,
        @environment.model_execution_ceiling(
          execution,
          @environment.TotalDurationMs,
        ),
      ),
    },
  })
  Ok(())
}

///|
/// Retain the installed adapter's bounded physical preparation before any
/// prefix work. Dispatch still requires the ordinary current authority owner.
pub fn bind_physical_preflight(
  active : Execution,
  prepare : @model.ModelPhysicalPreflight,
) -> Result[Unit, Issue] {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.source is Physical(_)) ||
    !(active.phase is Input) ||
    active.work != 0L ||
    active.physical_preflight is Some(_) {
    return Err(InvalidAdvance)
  }
  active.physical_preflight = Some(prepare)
  Ok(())
}

///|
/// The actual shared ledger observation remains available after failed or
/// cancelled cleanup. Reservations for dispatched unknown usage are retained.
pub fn execution_quantity_usage(
  active : Execution,
) -> @resources.QuantityUsage? {
  match active.model {
    Some(model) => Some(@model.model_execution_quantity_usage(model))
    None => active.final_quantity_usage
  }
}

///|
pub fn bind_egress_admission(
  active : Execution,
  admission : @publication_host.ClientInferEgressAdmission,
) -> Result[Unit, Issue] {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.source is Physical(_)) ||
    !(active.phase is Input) ||
    active.work != 0L ||
    active.egress_admission is Some(_) {
    return Err(InvalidAdvance)
  }
  guard active.plan is Some(plan) &&
    @publication_host.client_infer_egress_matches(
      admission,
      active.prepared,
      plan,
    ) else {
    return Err(Model(@model.Egress(@publication_host.ForeignOwner)))
  }
  active.egress_admission = Some(admission)
  Ok(())
}
