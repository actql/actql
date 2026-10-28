///|
// Installed constructor census, not a semantic limit or a second tariff.
// The same receipt/current/resize/finish frame as Context entry surrounds this
// sequential entrance. Its temporary driver retires only after it unwinds.
let program_topology_entry_retained_bytes : Int64 = program_source_extent_cost(
  @context.sourceview_context_topology_entry_construction_extent(),
).unwrap()

///|
let program_topology_entry_peak_bytes : Int64 = program_topology_entry_retained_bytes +
  program_context_input_driver_bytes

///|
/// Start only the original topology preflight/empty staging collections on the
/// SAME parent. The returned LocalInputs phase has not typed a Pipeline, bound
/// Parameters or constructed Result ports. Each later body needs its own quote.
pub fn[I, P] prepare_program_check_source_topology_entry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceContextInputPrepared {
    match reconcile_program_check_source_context_input(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceContextInputComplete {
    owner.source_body_quote = None
    owner.phase = SourceTopologyEntryInitial
  }
  guard !owner.busy &&
    owner.phase == SourceTopologyEntryInitial &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) &&
    @checked.parsed_source_context_input(original) is Some(Ok(context)) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_topology_entry_owned(
    owner, input, context,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_topology_entry_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  context : @context.SourceViewContextInput,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  match
    grow_program_check_source_body(
      owner, input, program_topology_entry_peak_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @context.sourceview_context_topology_entry_work_bound(context)
    is Some(bound) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceTopologyEntry,
      bound.to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(work) => work
  }
  owner.work = Some(work)
  let read = match @context.begin_sourceview_context_topology_read(context) {
    Err(issue) => {
      // No complete nested Usage is invented. The original failed entrance
      // stays in this Context until clear; its work receipt remains pending.
      owner.phase = SourceTopologyEntryFailed
      return Err(TopologyEntry(issue))
    }
    Ok(read) => read
  }
  guard @stage_results.local_program_read_owned_work(read) is Some(spent) else {
    owner.phase = SourceTopologyEntryFailed
    return Err(WrongPhase)
  }
  match finish_program_check_source_work(owner, work, spent) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.environment_scratch = Some(program_context_input_driver_bytes)
  owner.phase = SourceTopologyEntryPrepared
  Ok(())
}

///|
pub fn[I, P] reconcile_program_check_source_topology_entry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceTopologyEntryPrepared,
    SourceTopologyEntryComplete,
  )
}
