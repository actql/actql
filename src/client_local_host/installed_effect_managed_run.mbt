///|
/// The same installed Run owner retains a checked Effect preparation without
/// coercing it to an Effect-free Program. Resource preparation is separate
/// from the existing allowed Run, Preview and physical Effect claims.
pub fn installed_effect_managed_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  installed_managed_run_requirements_owned(
    Effect(prepared),
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    false,
  )
}

///|
pub fn installed_effect_mock_model_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  installed_managed_run_requirements_owned(
    Effect(prepared),
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    true,
  )
}

///|
fn installed_effect_managed_request_matches(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  let identity = @publication_host.prepared_client_effect_identity(prepared)
  identity.program_definition_cid ==
  @publication_host.client_request_program_cid(request) &&
  identity.parameter_values_cid ==
  @publication_host.client_request_parameters_cid(request)
}

///|
pub fn check_installed_effect_managed_run(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  match check_installed_effect_managed_run_binding(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  require_installed_managed_run(value).map(_ => ())
}

///|
fn check_installed_effect_managed_run_binding(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.preparation is Some(preparation) else { return Err(Retired) }
  let original = match preparation {
    PlannedEffectManaged(_, plan) => {
      if !physical_equal(plan.request, request) {
        return Err(ForeignOriginal)
      }
      plan.prepared
    }
    _ => return Err(ForeignOriginal)
  }
  guard physical_equal(original, prepared) && value.request == request else {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
/// Install the same recorded Model Scope before any Source or Compute child.
/// No sequence/contract/provider is re-prepared here. The Host retains this
/// admission before calling: bootstrap/Scope failure keeps its original cleanup.
pub fn begin_prepared_installed_effect_mock_model_managed_run(
  admission : @resources.NodeManagedRunAdmission[
    ClientInstalledEffectManagedPlan,
  ],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[
  (ClientInstalledManagedRun, @publication_host.ClientModelReadScope),
  ClientInstalledManagedRunIssue,
] {
  if !installed_effect_plan_matches(plan, prepared, request) {
    return Err(ForeignOriginal)
  }
  guard plan.model is Some(selected) else { return Err(Unsupported) }
  match
    @resources.check_node_local_mock_model_run_preparation(admission, plan) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let ledger = match @resources.start_node_managed_run_admission(admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(plan.limits, @resources.ledger_limits(ledger)) {
    return Err(InsufficientCapacity)
  }
  let bootstrap = match
    @resources.reserve_node_managed_run_read_bootstrap(
      admission,
      plan,
      ledger,
      selected.bootstrap_retained_bytes,
      selected.bootstrap_execution_bytes,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let scope = match
    @publication_host.begin_client_model_read_scope(
      selected.compiled,
      selected.definition,
      selected.graph,
      ledger,
      bootstrap,
      selected.max_reservations,
      selected.max_holdings,
      selected.max_delegations,
    ) {
    Err(issue) => return Err(ModelRead(issue))
    Ok(value) => value
  }
  let run = new_installed_managed_run_owned(
    PlannedEffectManaged(
      @resources.node_prepared_run_admission(admission),
      plan,
    ),
    request,
    ledger,
  )
  run.source_free_preparation = plan.source_free
  require_installed_managed_run(run).map(_ => (run, scope))
}

///|
/// Borrow only the original plan retained by the admitted parent. Legacy
/// Compute-only Effect parents cannot fund a normal operation from spare bytes.
pub fn installed_effect_managed_operation_plan(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  require_installed_effect_operation_plan(value, prepared, request).map(pair => {
    pair.0
  })
}

///|
// One synchronous original-current boundary supplies both retained DATA and
// its Ledger. The existing require call checks the same original preparation
// again after its callback; this pair never escapes as a reusable proof.
fn require_installed_effect_operation_plan(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  (ClientInstalledEffectManagedPlan, @resources.Ledger),
  ClientInstalledManagedRunIssue,
] {
  guard value.preparation is Some(PlannedEffectManaged(_, plan)) else {
    return Err(Unsupported)
  }
  match check_installed_effect_managed_run_binding(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  require_installed_managed_run(value).map(ledger => (plan, ledger))
}

///|
/// Original implementation membership only, without another current callback.
/// The physical operation constructor still checks the same parent, reserves
/// on its Ledger and performs its own actual before-use/currentness boundary.
pub fn check_installed_effect_operation_extent(
  owner : ClientInstalledManagedRun,
  extent : ClientInstalledEffectOperationExtent,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.preparation is Some(PlannedEffectManaged(_, plan)) else {
    return Err(ForeignOriginal)
  }
  if !extent.physical_attempt {
    return Err(Unsupported)
  }
  for demand in plan.operations {
    for declared in demand.member_extents {
      if physical_equal(declared, extent) {
        return Ok(())
      }
    }
    for declared in demand.row_extents {
      if physical_equal(declared, extent) {
        return Ok(())
      }
    }
  }
  Err(ForeignOriginal)
}

///|
// Run before legacy derivation: selected capacities/acquisitions/sequences
// already belong to this same immutable plan, not a re-created scalar quote.
fn prepare_planned_installed_effect_ledger(
  value : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.preparation is Some(PlannedEffectManaged(_, original)) &&
    physical_equal(original, plan) &&
    physical_equal(value.request, plan.request) else {
    return Err(ForeignOriginal)
  }
  if !physical_equal(plan.installed_contracts, installed_contracts) ||
    plan.values_body != values_body ||
    plan.fragment_body != fragment_body ||
    plan.ordered_body != ordered_body ||
    plan.transport_bytes != transport_bytes ||
    plan.transport_execution_bytes != transport_execution_bytes ||
    capacities.length() != plan.captures.length() ||
    value.reads.length() != plan.declarations.length() {
    return Err(ForeignOriginal)
  }
  for index, capacity in capacities {
    if !physical_equal(capacity, plan.captures[index]) ||
      !capacity.original_input {
      return Err(ForeignOriginal)
    }
    guard value.reads[index] is Some(read) &&
      read.declaration is Some(declaration) &&
      physical_equal(declaration, plan.declarations[index]) &&
      read.acquisition is Some(acquisition) &&
      physical_equal(acquisition, plan.acquisitions[index]) &&
      read.requirement is Some(requirement) &&
      physical_equal(requirement, capacity.requirement) else {
      return Err(ForeignOriginal)
    }
    if capacity.provider is Some((selected, provider)) &&
      (
        !physical_equal(selected, acquisition) ||
        !installed_provider_row_capture_capacity_matches(
          capacity, acquisition, provider,
        )
      ) {
      return Err(ForeignOriginal)
    }
  }
  let ledger = match require_installed_managed_run(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  if !installed_effect_managed_limits_fit(value, plan, ledger) {
    return Err(InsufficientCapacity)
  }
  Ok(ledger)
}

///|
// Call only after the original admission/current fence. Preparation-owned
// Runs already retain their actual body and grow each later constructor/task
// on this same Ledger. Standalone admissions still fund the complete envelope.
// Usage below is accounting DATA, never an ownership or currentness witness.
fn installed_effect_managed_limits_fit(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
) -> Bool {
  let limits = @resources.ledger_limits(ledger)
  match owner.preparation_retirement {
    None => return installed_effect_limits_fit(plan.limits, limits)
    Some(PurePreparation(_)) => return false
    Some(EffectPlanPreparation(original)) => {
      guard owner.preparation is Some(PlannedEffectManaged(admission, selected)) &&
        physical_equal(selected, plan) &&
        physical_equal(original.admission, admission) &&
        original.holder is Some(holder) &&
        @resources.preparation_body_borrow_value(holder) is Some(body) &&
        physical_equal(body, plan) &&
        @resources.preparation_body_borrow_reserved_extents(holder)
        is Ok((retained, execution)) &&
        retained <= limits.retained_bytes &&
        execution <= limits.execution_bytes else {
        return false
      }
    }
  }
  // Preserve every consumed/reserved non-byte dimension and current holding.
  // Future work/attempts/allocations still debit the original finite limits;
  // a larger theoretical Plan cannot replace these amounts or the Ledger.
  let usage = @resources.ledger_usage(ledger)
  usage.planning_work <= limits.planning_work &&
  usage.attempts <= limits.attempts &&
  usage.reserved_attempts <= limits.attempts - usage.attempts &&
  usage.holdings <= limits.holdings &&
  usage.transferred_bytes <= limits.transfer_bytes &&
  usage.uncertain_transfer_bytes <=
  limits.transfer_bytes - usage.transferred_bytes &&
  usage.reserved_transfer_bytes <=
  limits.transfer_bytes -
  usage.transferred_bytes -
  usage.uncertain_transfer_bytes &&
  usage.held_bytes <= limits.retained_bytes &&
  usage.reserved_retention_bytes <= limits.retained_bytes - usage.held_bytes &&
  usage.reserved_execution_bytes <= limits.execution_bytes
}

///|
pub fn prepare_installed_effect_managed_run_ledger(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  match check_installed_effect_managed_run(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_installed_managed_run_ledger_owned(
    value, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}
