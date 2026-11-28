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
    !execution_input_unadvanced(active) ||
    active.quantity_capacity is Some(_) {
    return Err(InvalidAdvance)
  }
  guard active.plan is Some(plan) else {
    return Err(Model(@model.RequestIdentity))
  }
  match original_model_quantity_capacity(plan, installed) {
    Err(issue) => Err(issue)
    Ok(capacity) => {
      active.quantity_capacity = Some(capacity)
      Ok(())
    }
  }
}

///|
// Use one existing installed/contract intersection both before original read
// and at Model binding. It creates no new quantity policy or capacity grant.
fn original_model_quantity_capacity(
  plan : @publication_host.ClientInferPlanGraph,
  installed : @model.ModelQuantityCapacity,
) -> Result[@model.ModelQuantityCapacity, Issue] {
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
  Ok({
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
    !execution_input_unadvanced(active) ||
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
    !execution_input_unadvanced(active) ||
    active.egress_admission is Some(_) {
    return Err(InvalidAdvance)
  }
  guard active.plan is Some(plan) &&
    @publication_host.client_infer_occurrence_matches_egress(
      active.occurrence,
      admission,
      plan,
    ) else {
    return Err(Model(@model.Egress(@publication_host.ForeignOwner)))
  }
  active.egress_admission = Some(admission)
  Ok(())
}

///|
/// Quote the simultaneous codec and original Model startup backing before
/// preparing the original Read Scope. The binder checks these same sums.
pub fn portable_chat_model_startup_capacity(
  limits : Limits,
  profile : @environment.ModelResponseProfile,
  scope? : @relation.ExecutionCapacity? = None,
) -> @relation.ExecutionCapacity? {
  let bounds = @environment.model_response_profile_limits(profile)
  let slots = Int::min(limits.model.max_items, limits.model.ledger.attempts)
  guard bounds.request_bytes.to_int64() <= limits.model.max_request_bytes &&
    bounds.response_bytes.to_int64() <= limits.model.max_response_bytes &&
    @model.model_http_chat_preflight_scope_capacity(
      profile,
      bounds.parse_nodes,
      slots,
      scope~,
    )
    is Some(codec) &&
    @relation.checked_preparation_add_product(
      limits.mapping.logical.max_live_value_bytes,
      @relation.execution_capacity_retained_bytes(codec),
      1L,
    )
    is Some(retained) &&
    @relation.checked_preparation_add_product(
      limits.identity.wire.max_bytes.to_int64(),
      @relation.execution_capacity_execution_bytes(codec),
      1L,
    )
    is Some(execution) else {
    return None
  }
  @relation.execution_capacity(retained, execution)
}

///|
/// Bind the installed Portable Chat codec before input advancement. Its
/// eventual cursor uses the same startup reservation retained by this Model.
/// The port receives the exact prepared material only at durable Call entry.
pub fn bind_original_portable_chat_preflight(
  active : Execution,
  provider : @model.AdmittedStructuredModelProvider,
  profile : @environment.ModelResponseProfile,
  installation : @environment.ModelResponseProfileInstallation,
  start : @model.ModelHttpChatStart?,
) -> Result[Unit, Issue] {
  guard active.original_preparation is Some(original) &&
    original.read is Claimed(_) &&
    original.shared_mock &&
    active.source is Physical(physical) &&
    active.plan is Some(plan) &&
    @model.admitted_model_http_chat_provider(
      provider,
      @publication_host.client_infer_plan_graph_execution_contract(plan),
      installation,
    )
    is Some(admitted) &&
    physical_equal(physical, admitted) &&
    active.quantity_capacity is Some(quantities) else {
    return Err(Model(@model.RequestIdentity))
  }
  guard @model.model_http_chat_installation_profile_matches(
    provider, profile, installation,
  ) else {
    return Err(Model(@model.RequestIdentity))
  }
  guard portable_chat_model_startup_capacity(active.limits, profile)
    is Some(capacity) else {
    return Err(Model(@model.InvalidLimits))
  }
  let retained = @relation.execution_capacity_retained_bytes(capacity)
  let execution = @relation.execution_capacity_execution_bytes(capacity)
  // The request/attempt reservations already cover wire and bookkeeping.
  // Only the excess simultaneous overlap belongs to the startup loan.
  if retained > original.retained_bytes {
    return Err(Model(@model.Ledger(@resources.RetentionLimit)))
  }
  if execution > original.execution_bytes {
    return Err(Model(@model.Ledger(@resources.ExecutionLimit)))
  }
  let max_frames = @environment.model_response_profile_limits(profile).parse_nodes
  bind_physical_preflight(active, request => {
    @model.start_model_http_chat_preflight(
      provider,
      request,
      installation,
      quantities.per_attempt,
      max_frames,
      _ => {
        guard original.startup is Some(startup) else {
          return Err(@model.RequestIdentity)
        }
        @model.check_original_model_http_chat_preflight_capacity(
          startup, provider, retained, execution,
        )
      },
      start,
    )
  })
}
