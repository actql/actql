///|
/// Execute the real next semantic prefix on the SAME original capacity. This
/// retains the completed support/declaration continuation on this SAME holder. The next full
/// Catalog/Context/Unit constructor and backend backing remain required.
pub fn[I, P] prepare_program_check_prelude(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.ParsedCheckPrelude, ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    owner.phase == CheckPrepared &&
    owner.input is Some(input) &&
    owner.check_input is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_prelude_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_prelude_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckInput,
) -> Result[@checked.ParsedCheckPrelude, ClientProgramCheckPreparationIssue] {
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  // Quote controls were funded at initial entry, not borrowed from old slack.
  // A failed atomic grow changes neither baseline nor phase: retry adds once.
  let inventory = @checked.parsed_check_prelude_construction_inventory(original)
  guard @shape.collection_construction_extent(inventory) is Some(extent) &&
    @execution.preparation_representation_cost(
      program_structure_units(
        extent.record_headers,
        extent.reference_slots,
        extent.scalar_words,
      ),
    )
    is Some(bytes) &&
    @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r1) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e1) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r1, e1) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  let maximum = Int::max(0, @checked.parsed_check_input_semantic_work(original))
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.SemanticPrelude,
      maximum.to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let (result, spent) = @checked.observe_parsed_check_prelude(original)
  let charge = @resources.spend_preparation_phase_work64(work, spent.to_int64())
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match charge {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  match result {
    Err(issue) => {
      owner.phase = Failed
      Err(Check(issue))
    }
    Ok(value) => {
      // Same original holder proceeds to Catalog admission. Returned DATA is a
      // borrowed continuation; clear never acknowledges parent/physical stop.
      owner.check_prelude = Some(value)
      owner.phase = PreludePrepared
      Ok(value)
    }
  }
}
