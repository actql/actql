///|
// Original quotation tree:5 collection expansions including their9W input,
//9 extent sums, one direct Map/key quantity,3 checked sums,3 extent literals,
// width Some/key tuple and inventory/map returns. Parent conversion/tariff,
// debit and result carriers use the existing source-entry family21H2R46W.
// This fixed frame is backed before even the original geometry is observed.
let program_context_input_quote_bytes : Int64 = {
  let c = @shape.collection_construction_quotation_extent()
  program_source_extent_cost({
    record_headers: 5L * (c.record_headers + 1L) +
    9L * 5L +
    8L +
    2L +
    3L +
    3L +
    1L +
    1L +
    3L +
    21L,
    reference_slots: 5L * c.reference_slots + 9L + 1L + 1L + 4L + 2L,
    scalar_words: 5L * (c.scalar_words + 9L) +
    9L * 10L +
    16L +
    5L +
    6L +
    9L +
    2L +
    4L +
    1L +
    46L,
  }).unwrap()
}

///|
let program_context_input_driver_bytes : Int64 = {
  let work = @resources.preparation_phase_work_construction_inventory()
  program_source_extent_cost({
    record_headers: work.record_headers + 14L,
    reference_slots: work.reference_slots + 12L,
    scalar_words: work.scalar_words + 24L,
  }).unwrap()
}

///|
let program_context_input_inspection_bytes : Int64 = program_source_extent_cost(
    @context.sourceview_context_input_geometry_inspection_extent(),
  ).unwrap() +
  program_context_input_quote_bytes +
  program_context_input_driver_bytes

///|
let program_context_input_inspection_retained_bytes : Int64 = program_source_extent_cost(
    @context.sourceview_context_input_geometry_retained_extent(),
  ).unwrap() +
  program_context_input_quote_bytes

///|
// Original Registered variant1H6R1W and stored original result Some1H1R1W.
// Returned/catch alternatives live in the separately backed driver interval.
let program_context_input_store_bytes : Int64 = program_source_extent_cost({
  record_headers: 2L,
  reference_slots: 7L,
  scalar_words: 2L,
}).unwrap()

///|
fn[I, P] inspect_program_check_context_input(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceLocalTailPrepared {
    match reconcile_program_check_source_local_tail(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !owner.busy && owner.phase == SourceLocalTailComplete {
    owner.source_body_quote = None
    owner.phase = SourceContextInputInitial
  }
  guard !owner.busy &&
    (
      owner.phase == SourceContextInputInitial ||
      owner.phase == SourceContextInputInspected ||
      owner.phase == SourceContextInputRetained
    ) &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = inspect_program_check_context_input_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] inspect_program_check_context_input_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedSourceRegistration,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.phase == SourceContextInputInitial {
    match
      grow_program_check_source_body(
        owner, input, program_context_input_inspection_bytes,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let read = @checked.parsed_source_registration_read(original)
    guard @context.source_registration_context_input_inspection_bound(read)
      is Some(bound) else {
      owner.phase = Failed
      return Err(WrongPhase)
    }
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.SourceContextInputInspection,
        bound,
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    guard @checked.observe_parsed_source_context_input_geometry(original)
      is Some(g) else {
      owner.phase = Failed
      return Err(WrongPhase)
    }
    match finish_program_check_source_work(owner, work, g.inspection_work) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    owner.environment_scratch = Some(
      program_context_input_inspection_bytes -
      program_context_input_inspection_retained_bytes,
    )
    owner.phase = SourceContextInputInspected
  }
  if owner.phase == SourceContextInputInspected {
    match reconcile_program_check_source_body_metadata(owner, input) {
      Err(issue) => return Err(issue)
      Ok(_) => owner.phase = SourceContextInputRetained
    }
  }
  Ok(())
}

///|
fn[I, P] quote_program_check_context_input(
  owner : ClientProgramCheckPreparation[I, P],
  original : @checked.ParsedSourceRegistration,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  if owner.source_body_quote is None {
    guard @checked.parsed_source_context_input_geometry(original) is Some(g) &&
      @context.sourceview_context_input_construction_inventory(g) is Some(q) &&
      program_source_extent_cost(q.peak) is Some(peak) &&
      program_source_extent_cost(q.retained) is Some(held) &&
      @execution.checked_preparation_add_product(
        held, program_context_input_store_bytes, 1L,
      )
      is Some(held) &&
      @execution.checked_preparation_add_product(
        peak, program_context_input_store_bytes, 1L,
      )
      is Some(peak) &&
      @execution.checked_preparation_add_product(
        peak, program_context_input_driver_bytes, 1L,
      )
      is Some(peak) else {
      return Err(Overflow)
    }
    owner.source_body_quote = Some((peak, held))
  }
  Ok(())
}

///|
/// Continue the original completed Source result into the original Context
/// registration entrance on the SAME parent. This does not run topology,
/// Parameter binding, Stage capacities, identity/check or issue a ready Plan.
pub fn[I, P] prepare_program_check_source_context_input(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  match inspect_program_check_context_input(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !owner.busy &&
    owner.phase == SourceContextInputRetained &&
    owner.input is Some(input) &&
    owner.source_registration is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_source_context_input_owned(
    owner, input, original,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_source_context_input_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedSourceRegistration,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  match quote_program_check_context_input(owner, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (peak, held) = owner.source_body_quote.unwrap()
  match grow_program_check_source_body(owner, input, peak) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @checked.parsed_source_context_input_work_bound(original) is Some(bound) else {
    owner.phase = Failed
    return Err(WrongPhase)
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SourceContextInputBody,
      bound.to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  match @checked.prepare_parsed_source_context_input(original) {
    Err(issue) => {
      // Original nested failure has no complete Usage. Retain its typed result,
      // earlier debits and receipt until the actual clear, never invent zero.
      owner.phase = SourceContextInputFailed
      return Err(SourceRegistration(issue))
    }
    Ok(value) =>
      match
        finish_program_check_source_work(
          owner,
          work,
          @context.sourceview_context_input_work(value).to_int64(),
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
  }
  owner.environment_scratch = Some(
    peak - held + program_context_input_quote_bytes,
  )
  owner.phase = SourceContextInputPrepared
  Ok(())
}

///|
pub fn[I, P] reconcile_program_check_source_context_input(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    SourceContextInputPrepared,
    SourceContextInputComplete,
  )
}
