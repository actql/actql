///|
/// Existing parent/holder through the next actual Catalog reader. Registry
/// scratch is reconciled only after its frame returned; failed growth retains
/// its SAME observed Contents inputs, without a registry/body replay.
pub fn[I, P] prepare_program_check_contents(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  if owner.phase == RegistryPrepared {
    match reconcile_program_check_registry(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (owner.phase == RegistryRetained || owner.phase == ContentsInspected) &&
    owner.input is Some(input) &&
    owner.check_registry is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_contents_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_contents_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckRegistry,
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  if owner.phase == RegistryRetained {
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.CatalogContentsInspection,
        @checked.parsed_check_contents_inspection_bound(original),
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    let observed = @checked.prepare_parsed_contents_input(original)
    let spent = match observed {
      Ok(value) => {
        owner.contents_input = Some(value)
        @checked.parsed_contents_inspection_work(value)
      }
      Err(_) => 0L
    }
    let charged = @resources.spend_preparation_phase_work64(work, spent)
    match @resources.finish_preparation_phase_work64(work) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => owner.work = None
    }
    match charged {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(_) => ()
    }
    match observed {
      Err(issue) => {
        owner.phase = Failed
        return Err(Prelude(issue))
      }
      Ok(_) => ()
    }
    owner.phase = ContentsInspected
  }
  let prepared = owner.contents_input.unwrap()
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard program_catalog_extent_cost(
      @checked.parsed_contents_construction_extent(prepared),
    )
    is Some(bytes) &&
    program_catalog_extent_cost(
      @checked.parsed_contents_retained_extent(prepared),
    )
    is Some(retained) &&
    retained <= bytes &&
    @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r1) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e1) else {
    return Err(Overflow)
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r1, e1) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.CatalogContentsAdmission,
      @checked.parsed_contents_semantic_work(prepared).to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let (result, spent) = @checked.observe_parsed_check_contents(prepared)
  let charged = @resources.spend_preparation_phase_work64(
    work,
    spent.to_int64(),
  )
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match charged {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  match result {
    Err(issue) => {
      owner.phase = Failed
      Err(Catalog(issue))
    }
    Ok(_) => {
      owner.environment_scratch = Some(bytes - retained)
      owner.phase = ContentsPrepared
      Ok(original)
    }
  }
}

///|
pub fn[I, P] reconcile_program_check_contents(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    ContentsPrepared,
    ContentsRetained,
  )
}
