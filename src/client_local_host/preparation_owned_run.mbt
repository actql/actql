///|
/// Fixed Local cleanup custody, not a new Resource or callback authority.
/// The holder owns this Run's heavy fields; its admission owns a separate
/// original holder. Existing output/operation/handler holders remain distinct.
priv struct ClientManagedPreparationRetirement[P] {
  retirement : @resources.PreparationRetirement
  admission : @resources.NodeManagedRunAdmission[P]
  mut holder : @resources.PreparationBodyBorrow[P]?
}

///|
/// A closed typed choice on the same Run cleanup field. Both cases use the
/// same generic retirement below; no second cleanup engine or resource owner.
priv enum ClientManagedPreparationCustody {
  PurePreparation(
    ClientManagedPreparationRetirement[@publication_host.PreparedClientProgram]
  )
  EffectPlanPreparation(
    ClientManagedPreparationRetirement[ClientInstalledEffectManagedPlan]
  )
}

///|
/// Fixed Request entry. The supplier funds constructor coexistence and retains
/// every original dependency before calling. This consumes the already started
/// input admission and never starts a second imported child.
pub fn[I] begin_preparation_owned_installed_managed_run(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  original : ClientInstalledManagedSourceFreePreparation,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard original.owner is Pure(owner) && physical_equal(owner, prepared) else {
    return Err(ForeignOriginal)
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  if !installed_managed_run_purpose_supported(prepared) ||
    @strategy.graph_captured_prefix(
      @publication_host.prepared_client_graph(prepared),
    ) !=
    0 {
    return Err(Unsupported)
  }
  // The existing original ordinary-purpose proof excludes Model. Retiring
  // this unused initial census is metadata disposal, never a new admission.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let (admission, ledger, retirement, holder) = match
    @resources.adopt_node_preparation_admission(
      initial, input, capacity, prepared,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let value = new_installed_managed_run(admission, prepared, request, ledger)
  value.source_free_preparation = Some(original)
  value.preparation_retirement = Some(
    PurePreparation({ retirement, admission, holder: Some(holder), }),
  )
  Ok(value)
}

///|
/// Captured Pure preparation keeps the same prepared body and two original
/// Resource holders. Its retained Source Plan belongs to these same Run fields.
pub fn[I] begin_preparation_owned_installed_capture_run(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledManagedCapturePlan,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  if !physical_equal(plan.prepared, prepared) ||
    !physical_equal(plan.request, request) {
    return Err(ForeignOriginal)
  }
  let limits = match @resources.node_local_preparation_limits(initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(plan.limits, limits) {
    return Err(InsufficientCapacity)
  }
  // This opaque capture Plan was constructed under the unchanged ordinary
  // purpose predicate; no Model/serialization fallback is introduced here.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let (admission, ledger, retirement, holder) = match
    @resources.adopt_node_preparation_admission(
      initial, input, capacity, prepared,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let run = new_installed_managed_run(admission, prepared, request, ledger)
  run.captured_preparation = Some(plan)
  run.preparation_retirement = Some(
    PurePreparation({ retirement, admission, holder: Some(holder), }),
  )
  Ok(run)
}

///|
/// Adopt the original staged Effect plan without coercing it to a pure
/// Program or starting another child. The fixed initial owner must have
/// reserved the complete construction/Run-holder overlap before this call.
/// Numeric compatibility is checked before transferring cleanup responsibility.
pub fn[I] begin_preparation_owned_installed_effect_managed_run(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  if !installed_effect_plan_matches(plan, prepared, request) {
    return Err(ForeignOriginal)
  }
  // The ordinary entry cannot spend a separately selected Model purpose or
  // begin Source reads before that plan's original Scope is installed.
  if plan.model is Some(_) {
    return Err(Unsupported)
  }
  let limits = match @resources.node_local_preparation_limits(initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(plan.limits, limits) {
    return Err(InsufficientCapacity)
  }
  // The original plan.model guard above already selected this non-Model
  // constructor. No operation-name or graph reconstruction is needed.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let (admission, ledger, retirement, holder) = match
    @resources.adopt_node_preparation_admission(initial, input, capacity, plan) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let value = new_installed_managed_run_owned(
    PlannedEffectManaged(admission, plan),
    request,
    ledger,
  )
  value.source_free_preparation = plan.source_free
  value.preparation_retirement = Some(
    EffectPlanPreparation({ retirement, admission, holder: Some(holder), }),
  )
  Ok(value)
}

///|
/// The fixed dispatch owner invokes this only after operation quiescence and
/// existing physical stop/output-close witnesses. Isolated usage below is an
/// additional accounting check, never a replacement for those witnesses.
fn[P] retire_preparation_owned_installed_run(
  value : ClientInstalledManagedRun,
  original : ClientManagedPreparationRetirement[P],
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.ledger is Some(ledger) else { return Ok(()) }
  if value.preparation is Some(_) &&
    !@resources.node_preparation_usage_isolated(original.admission, ledger) {
    return Err(CleanupPending)
  }
  match @resources.retire_transferred_preparation(original.retirement) {
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      return Err(Ledger(issue))
    Err(_) => return Err(CleanupPending)
    Ok(_) => ()
  }
  clear_managed_run_publication(value)
  // Fence new Run borrows and remove actual raw owners before returning either
  // durable holder. An existing operation must use its own registered borrow.
  value.preparation = None
  value.source_free_preparation = None
  value.captured_preparation = None
  value.source_free_captured = None
  value.keyed = None
  value.reads.clear()
  value.keyed_reads.clear()
  if original.holder is Some(holder) {
    original.holder = None
    match @resources.return_preparation_body_borrow(holder) {
      Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
        return Err(Ledger(issue))
      Err(_) => return Err(CleanupPending)
      Ok(_) => ()
    }
  }
  match @resources.release_node_preparation_holder(original.admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match @resources.retire_transferred_preparation(original.retirement) {
    Ok(true) => ()
    Ok(false) => return Err(CleanupPending)
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      return Err(Ledger(issue))
    Err(_) => return Err(CleanupPending)
  }
  match @resources.cleanup_node_managed_run_admission(original.admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  value.ledger = None
  value.preparation_retirement = None
  Ok(())
}

///|
/// The fixed manager may switch from heavy payload currentness to its original
/// light receipt only after this same Run has entered retirement and severed
/// its own fields. This read-only phase witness grants no stop/release ACK.
pub fn installed_preparation_payload_severed(
  value : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    physical_equal(value.request, request) &&
    value.ledger is Some(ledger) &&
    value.preparation_retirement is Some(retirement) &&
    value.preparation is None &&
    value.source_free_preparation is None &&
    value.captured_preparation is None &&
    value.source_free_captured is None else {
    return false
  }
  match retirement {
    PurePreparation(original) =>
      preparation_retirement_payload_severed(original, ledger)
    EffectPlanPreparation(original) =>
      preparation_retirement_payload_severed(original, ledger)
  }
}

///|
fn[P] preparation_retirement_payload_severed(
  original : ClientManagedPreparationRetirement[P],
  ledger : @resources.Ledger,
) -> Bool {
  original.holder is None &&
  @resources.check_node_preparation_cleanup_original(original.admission, ledger)
  is Ok(_)
}

///|
/// The fixed Content constructor has already retained its selected keyed and
/// serialization material under the same Request construction borrow. Adopt
/// that exact preparation without selecting the legacy Content Root or scope.
/// The complete provider/output/constructor overlap must already be funded;
/// numerical compatibility here does not issue that physical backing.
pub fn[I] begin_preparation_owned_installed_content_run(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  selected : ClientInstalledManagedKeyedPreparation,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  let identity = @publication_host.prepared_client_identity(prepared)
  if !physical_equal(selected.prepared, prepared) ||
    identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  let limits = match @resources.node_local_preparation_limits(initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(selected.limits, limits) {
    return Err(InsufficientCapacity)
  }
  // The selected keyed Content constructor already required explicit empty
  // Infer inventory. Its original prepared/request/declaration remain bound.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let (admission, ledger, retirement, holder) = match
    @resources.adopt_node_preparation_admission(
      initial, input, capacity, prepared,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let run = new_installed_managed_run_owned(
    PreparationContentManaged(admission, prepared),
    request,
    ledger,
  )
  run.keyed = Some(selected)
  run.preparation_retirement = Some(
    PurePreparation({ retirement, admission, holder: Some(holder), }),
  )
  Ok(run)
}
