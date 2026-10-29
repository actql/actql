///|
/// Continue this SAME original holder/capacity. Observation survives an atomic
/// failed grow; no registry/hash reader or metadata inspection is replayed.
pub fn[I, P] prepare_program_check_registry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == PreludePrepared || owner.phase == CatalogInspected) &&
    owner.input is Some(input) &&
    owner.check_prelude is Some(prelude) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_program_check_registry_owned(owner, input, prelude)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_registry_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  prelude : @checked.ParsedCheckPrelude,
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  if owner.phase == PreludePrepared {
    match current_program_check_preparation(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.CatalogInspection,
        @checked.parsed_check_prelude_registry_members(prelude).to_int64(),
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    let observed = @checked.prepare_parsed_catalog_input(prelude)
    let spent = match observed {
      Ok(value) => {
        owner.catalog_input = Some(value)
        @checked.parsed_catalog_inspection_work(value)
      }
      Err(_) => 0
    }
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
    match observed {
      Err(issue) => {
        owner.phase = Failed
        return Err(Prelude(issue))
      }
      Ok(_) => ()
    }
    owner.phase = CatalogInspected
  }
  let prepared = owner.catalog_input.unwrap()
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  let extent = @checked.parsed_catalog_construction_extent(prepared)
  guard program_catalog_extent_cost(extent) is Some(bytes) &&
    program_catalog_extent_cost(
      @checked.parsed_catalog_retained_extent(prepared),
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
      @resources.CatalogAdmission,
      @checked.parsed_catalog_semantic_work(prepared).to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let (result, spent) = @checked.observe_parsed_check_registry(prepared)
  if result is Ok(value) {
    owner.check_registry = Some(value)
    owner.environment_scratch = Some(bytes - retained)
  }
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
    Ok(value) => {
      owner.phase = RegistryPrepared
      Ok(value)
    }
  }
}

///|
/// Transfer this SAME actual continuation once after the original current gate.
/// The parent stays reserved until the next funded constructor/real cleanup.
pub fn[I, P] take_program_check_registry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    (
      owner.phase == RegistryPrepared ||
      owner.phase == RegistryRetained ||
      owner.phase == ContentsPrepared ||
      owner.phase == ContentsRetained ||
      owner.phase == ReferencesPrepared ||
      owner.phase == ReferencesRetained ||
      owner.phase == PoliciesPrepared ||
      owner.phase == PoliciesRetained ||
      owner.phase == ValuesPrepared ||
      owner.phase == ValuesRetained ||
      owner.phase == ViewsPrepared ||
      owner.phase == ViewsRetained ||
      owner.phase == CarriersPrepared ||
      owner.phase == CarriersRetained ||
      owner.phase == RequestsPrepared ||
      owner.phase == RequestsRetained
    ) &&
    owner.check_registry is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let current = current_program_check_preparation(owner)
  owner.busy = false
  match current {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  transfer_program_check_input(owner)
  Ok(original)
}

///|
fn program_catalog_extent_cost(
  extent : @environment.RegistryConstructionExtent,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: extent.owned_utf16_units,
    owned_wire_bytes: extent.owned_wire_bytes,
  })
}

///|
/// Only this constructor's returned hash/view/emitter frame is removed. The
/// actual registry, input, budget, metadata, outside debit and parent survive.
pub fn[I, P] reconcile_program_check_registry(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    RegistryPrepared,
    RegistryRetained,
  )
}

///|
fn[I, P] reconcile_program_check_environment_scratch(
  owner : ClientProgramCheckPreparation[I, P],
  expected : ProgramCheckPreparationPhase,
  next : ProgramCheckPreparationPhase,
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  guard !owner.busy &&
    owner.phase == expected &&
    owner.input is Some(input) &&
    owner.check_registry is Some(_) &&
    owner.environment_scratch is Some(scratch) else {
    return Err(WrongPhase)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  if scratch < 0L || scratch >= r || scratch > e {
    return Err(Overflow)
  }
  owner.busy = true
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    r - scratch,
    e - scratch,
  )
  owner.busy = false
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.environment_scratch = None
      owner.phase = next
      Ok(())
    }
  }
}
