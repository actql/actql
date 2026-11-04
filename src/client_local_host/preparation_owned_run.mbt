///|
/// Fixed Local cleanup custody, not a new Resource or callback authority.
/// The holder owns this Run's heavy fields; its admission owns a separate
/// original holder. Existing output/operation/handler holders remain distinct.
priv struct ClientManagedPreparationRetirement[P] {
  retirement : @resources.PreparationRetirement
  admission : @resources.PreparedRunAdmission[P]
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
/// Dormant fixed-Root entry. The supplier must fund constructor coexistence
/// and retain every original dependency before calling; no SDK path currently
/// selects it. Unlike the legacy entry, this consumes the already started
/// input admission and never starts a second imported child.
fn[I] begin_preparation_owned_installed_managed_run_original(
  initial : ClientPreparationInitial[I],
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
  if original._observed_query_time is Some((_, bound_request)) &&
    !physical_equal(bound_request, request) {
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
  match check_preparation_owned_body_limits(initial, input, capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  adopt_preparation_owned_pure_plan(
    initial,
    input,
    capacity,
    prepared,
    request,
    Some(original),
    None,
  )
}

///|
/// Captured Pure preparation keeps the same prepared body and two original
/// Resource holders. Its retained Source Plan belongs to these same Run fields.
fn[I] begin_preparation_owned_installed_capture_run_original(
  initial : ClientPreparationInitial[I],
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
  // Both fixed constructors now retain this opaque body type. The ordinary
  // entry must still refuse Model rather than discarding its Scope census.
  if !installed_managed_run_purpose_supported(prepared) {
    return Err(Unsupported)
  }
  match check_preparation_owned_body_limits(initial, input, capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // This existing opaque constructor already selected ordinary, non-Model
  // capture. Disposal changes no byte debit or consumed input history.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  adopt_preparation_owned_pure_plan(
    initial,
    input,
    capacity,
    prepared,
    request,
    None,
    Some(plan),
  )
}

///|
// Fixed Pure constructors have checked their actual ordinary/Model purpose
// and Scope obligation. Share the same adoption and two lifetime holders;
// neither a new initial admission nor a cleanup owner is constructed here.
fn[I] adopt_preparation_owned_pure_plan(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  source_free : ClientInstalledManagedSourceFreePreparation?,
  captured : ClientInstalledManagedCapturePlan?,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  let (admission, ledger, retirement, holder) = match
    adopt_preparation_initial(initial, input, capacity, prepared) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let run = new_installed_managed_run_owned(
    PureManaged(admission, prepared),
    request,
    ledger,
  )
  run.source_free_preparation = source_free
  run.captured_preparation = captured
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
fn[I] begin_preparation_owned_installed_effect_managed_run_original(
  initial : ClientPreparationInitial[I],
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
  match check_preparation_owned_effect_limits(initial, input, capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The original plan.model guard above already selected this non-Model
  // constructor. No operation-name or graph reconstruction is needed.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  adopt_preparation_owned_installed_effect_plan(
    initial, input, capacity, request, plan,
  )
}

///|
/// The Model owner retained this Scope before completing the same Plan. Keep
/// its census and original cleanup obligation through the existing adoption.
/// No Scope, bootstrap reservation, compiler or Model resource is issued here.
fn[I] begin_preparation_owned_installed_effect_model_run(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  scope : @publication_host.ClientModelReadScope,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  if !installed_effect_plan_matches(plan, prepared, request) {
    return Err(ForeignOriginal)
  }
  guard plan.model is Some(selected) else { return Err(Unsupported) }
  let identity = match
    @resources.preparation_capacity_inventory_original(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  if !@publication_host.client_model_read_scope_original_inventory(
      scope, ledger, identity,
    ) ||
    !@publication_host.client_model_read_scope_live(
      scope,
      selected.compiled,
      selected.definition,
      selected.graph,
    ) {
    return Err(ForeignOriginal)
  }
  match check_preparation_owned_effect_limits(initial, input, capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  adopt_preparation_owned_installed_effect_plan(
    initial, input, capacity, request, plan,
  )
}

///|
fn[I] check_preparation_owned_effect_limits(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  check_preparation_owned_body_limits(initial, input, capacity)
}

///|
fn[I, P] check_preparation_owned_body_limits(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, P],
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let limits = match preparation_initial_limits(initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let (retained, execution) = match
    @resources.preparation_capacity_reserved_extents(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  // This route adopts the already backed Request body. Runtime task/operation
  // maxima are policy DATA, not simultaneous startup allocations. Their actual
  // constructors must reserve/grow on this SAME finite Ledger before work.
  if retained > limits.retained_bytes || execution > limits.execution_bytes {
    return Err(InsufficientCapacity)
  }
  Ok(())
}

///|
// Both fixed purposes already checked their original Plan/bounds and selected
// their actual Scope/ordinary obligation. Share the exact original holders and
// retirement engine without another current callback or admission.
fn[I] adopt_preparation_owned_installed_effect_plan(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  let (admission, ledger, retirement, holder) = match
    adopt_preparation_initial(initial, input, capacity, plan) {
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
// Call only after the original Run/admission current fence. The same retained
// body holder supplies ownership; usage DATA cannot replace it. Both Pure and
// Effect preparation routes keep this original finite Ledger for later growth.
fn[P] preparation_owned_run_limits_fit(
  original : ClientManagedPreparationRetirement[P],
  admission : @resources.PreparedRunAdmission[P],
  selected : P,
  ledger : @resources.Ledger,
) -> Bool {
  let limits = @resources.ledger_limits(ledger)
  guard physical_equal(original.admission, admission) &&
    original.holder is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, selected) &&
    @resources.preparation_body_borrow_reserved_extents(holder)
    is Ok((retained, execution)) &&
    retained <= limits.retained_bytes &&
    execution <= limits.execution_bytes else {
    return false
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
/// The fixed dispatch owner invokes this only after operation quiescence and
/// existing physical stop/output-close witnesses. Isolated usage below is an
/// additional accounting check, never a replacement for those witnesses.
fn[P] retire_preparation_owned_installed_run(
  value : ClientInstalledManagedRun,
  original : ClientManagedPreparationRetirement[P],
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.ledger is Some(ledger) else { return Ok(()) }
  if value.preparation is Some(_) &&
    !@resources.prepared_run_usage_isolated(original.admission, ledger) {
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
  value.content = NoContent
  value.serialization_prefix = None
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
  match @resources.release_prepared_run_holder(original.admission) {
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
  match @resources.cleanup_prepared_run_admission(original.admission) {
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
  @resources.check_prepared_run_cleanup_original(original.admission, ledger)
  is Ok(_)
}

///|
/// The fixed Content constructor has already retained its selected keyed and
/// serialization material under the same Request construction borrow. Adopt
/// that exact preparation without selecting the legacy Content Root or scope.
/// The complete provider/output/constructor overlap must already be funded;
/// numerical compatibility here does not issue that physical backing.
fn[I] begin_preparation_owned_installed_content_run_original(
  initial : ClientPreparationInitial[I],
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
  adopt_preparation_owned_content_original(
    initial,
    input,
    capacity,
    prepared,
    request,
    KeyedContent(selected, None),
    selected.limits,
  )
}

///|
/// The existing terminal Serialization purpose adopts its same parent and
/// compiler, without a keyed input, Pure module or independent Content Ledger.
fn[I] begin_preparation_owned_installed_serialization_run_original(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  selected : ClientInstalledManagedSerializationPreparation,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  if !physical_equal(selected.prepared, prepared) ||
    !physical_equal(selected.request, request) {
    return Err(ForeignOriginal)
  }
  adopt_preparation_owned_content_original(
    initial,
    input,
    capacity,
    prepared,
    request,
    SerializationContent(selected),
    selected.limits,
  )
}

///|
// Both original Content constructors share the SAME transfer and retirement
// engine. Numeric compatibility neither allocates backing nor authorizes IO.
fn[I] adopt_preparation_owned_content_original(
  initial : ClientPreparationInitial[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  content : ClientInstalledContentPreparation,
  required : @resources.LedgerLimits,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  let limits = match preparation_initial_limits(initial, input) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !installed_effect_limits_fit(required, limits) {
    return Err(InsufficientCapacity)
  }
  // This actual Content constructor excludes Model. Retire only its unused
  // input census metadata; consumed IO/work and byte debit are unchanged.
  match
    @resources.discard_unbound_preparation_capacity_inventory(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  let (admission, ledger, retirement, holder) = match
    adopt_preparation_initial(initial, input, capacity, prepared) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let run = new_installed_managed_run_owned(
    PreparationContentManaged(admission, prepared),
    request,
    ledger,
  )
  run.content = content
  run.preparation_retirement = Some(
    PurePreparation({ retirement, admission, holder: Some(holder), }),
  )
  Ok(run)
}

///|
// Original Node entry; no backing or purpose is replaced.
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
  begin_preparation_owned_installed_managed_run_original(
    NodeRequestInitial(initial),
    input,
    capacity,
    prepared,
    request,
    original,
  )
}

///|
// Original Node entry; no backing or purpose is replaced.
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
  begin_preparation_owned_installed_capture_run_original(
    NodeRequestInitial(initial),
    input,
    capacity,
    prepared,
    request,
    plan,
  )
}

///|
// Original Node entry; no backing or purpose is replaced.
pub fn[I] begin_preparation_owned_installed_effect_managed_run(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  begin_preparation_owned_installed_effect_managed_run_original(
    NodeRequestInitial(initial),
    input,
    capacity,
    prepared,
    request,
    plan,
  )
}

///|
// Original Node entry; no backing or purpose is replaced.
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
  begin_preparation_owned_installed_content_run_original(
    NodeRequestInitial(initial),
    input,
    capacity,
    prepared,
    request,
    selected,
  )
}

///|
// Original Node entry; no backing or purpose is replaced.
pub fn[I] begin_preparation_owned_installed_serialization_run(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  selected : ClientInstalledManagedSerializationPreparation,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  begin_preparation_owned_installed_serialization_run_original(
    NodeRequestInitial(initial),
    input,
    capacity,
    prepared,
    request,
    selected,
  )
}
