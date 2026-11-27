///|
let captured_run_read_slot_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 1L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
/// Complete the actual captured Plan on the existing Pure prepared capacity.
/// The Run fields/manager borrow own its Plan dependency until actual cleanup.
fn[I] complete_request_capture_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedCapturePlan,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ProgramPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(plan.prepared, prepared) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  // The retained Whole Plan counts input occurrences, while the original
  // Run's base read array was priced per captured task. Several Whole inputs
  // can feed one task. Fund just the extra slots before adopting the Run.
  let extra_reads = Int::max(
    0,
    plan.whole_sources.length() -
    @strategy.graph_captured_prefix(
      @publication_host.prepared_client_graph(prepared),
    ),
  ).to_int64()
  guard @execution.checked_preparation_add_product(
      r, extra_reads, captured_run_read_slot_bytes,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      e, extra_reads, captured_run_read_slot_bytes,
    )
    is Some(execution) else {
    return Err(Policy)
  }
  owner.program_captured = Some(plan)
  owner.phase = Selecting
  if extra_reads > 0L {
    match
      @resources.reserve_working_preparation_phase(
        capacity, input, retained, execution,
      ) {
      Err(issue) => {
        owner.phase = ProgramBodyFailed
        return Err(Capacity(issue))
      }
      Ok(_) => ()
    }
  }
  // A refused grow leaves the capacity working. The Request must abort
  // that owner after its borrowers return, as for other pre-completion errors.
  owner.program_body_attempted = true
  let result = @resources.complete_preparation_capacity(
    capacity, input, prepared, retained, execution,
  )
  owner.phase = if result is Ok(_) {
    ProgramBodyReady
  } else {
    ProgramBodyFailed
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Original cleanup ownership for a transferred captured Plan. A pending
/// holder cannot adopt a second Run after an interrupted transition.
struct ClientRequestCaptureTransfer[I] {
  parent : ClientRequestPreparation[I]
  mut attempted : Bool
  mut run : ClientInstalledManagedRun?
}

///|
pub fn[I] retain_request_capture_transfer(
  parent : ClientRequestPreparation[I],
) -> Result[ClientRequestCaptureTransfer[I], ClientInstalledManagedRunIssue] {
  guard parent.phase == ProgramBodyReady else { return Err(ForeignOriginal) }
  Ok({ parent, attempted: false, run: None, })
}

///|
pub fn[I] begin_request_capture_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
  transfer? : ClientRequestCaptureTransfer[I]? = None,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard !owner.debug_plan_read &&
    owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_captured is Some(plan) else {
    return Err(ForeignOriginal)
  }
  if transfer is Some(original) {
    guard physical_equal(original.parent, owner) && !original.attempted &&
      original.run is None else { return Err(ForeignOriginal) }
    original.attempted = true
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_capture_run_original(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan,
  )
  match result {
    Err(issue) => {
      owner.phase = ProgramBodyReady
      Err(issue)
    }
    Ok(run) => {
      // Publish custody BEFORE clearing any original parent aliases. If the
      // caller was interrupted after adoption, only this owner can retire it.
      if transfer is Some(original) { original.run = Some(run) }
      clear_transferred_request_capture(owner)
      Ok(run)
    }
  }
}

///|
fn[I] clear_transferred_request_capture(owner : ClientRequestPreparation[I]) -> Unit {
  owner.program_capacity = None
  owner.program_normalization = None
  owner.program_authoring = None
  owner.compiled_program = None
  owner.program_data = None
  owner.program_plan_quote = None
  owner.program_captured = None
  owner.program_model_direct = None
  owner.native_parameters = None
  owner.native_query_declarations = None
  owner.native_parameters_ready = false
  owner.held_program = None
  clear_request_source_input(owner)
  owner.submitted_intent = None
  owner.intent_base = None
  owner.intent_peak_live = false
  owner.input = None
  owner.query_syntax = None
  owner.phase = Selected
}

///|
/// Resolve cleanup custody on the original parent. An interrupted lower
/// adoption without an observed owner remains pending; it is never replayed.
pub fn[I] observe_request_capture_transfer(
  transfer : ClientRequestCaptureTransfer[I],
) -> Result[ClientInstalledManagedRun?, ClientInstalledManagedRunIssue] {
  let parent = transfer.parent
  match transfer.run {
    Some(run) => {
      if parent.phase == Selecting { clear_transferred_request_capture(parent) }
      guard parent.phase == Selected else { return Err(ForeignOriginal) }
      Ok(Some(run))
    }
    None =>
      if parent.phase == ProgramBodyReady {
        Ok(None)
      } else {
        Err(CleanupPending)
      }
  }
}
