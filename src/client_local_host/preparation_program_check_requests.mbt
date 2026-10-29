///|
/// Continue the SAME original request/registry/parent. Metadata returns and
/// retires before the body grow; neither grow failure can repeat observation
/// or original semantic work. Current/retirement remain Resource boundaries.
pub fn[I, P] prepare_program_check_requests(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  if owner.phase == CarriersPrepared {
    match reconcile_program_check_carriers(owner) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if owner.phase == RequestsInspected {
    match
      reconcile_program_check_environment_scratch(
        owner,
        RequestsInspected,
        RequestsMetadataRetained,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  guard !owner.busy &&
    (
      owner.phase == CarriersRetained ||
      owner.phase == RequestsObservationFunded ||
      owner.phase == RequestsMetadataRetained
    ) &&
    owner.input is Some(input) &&
    owner.check_registry is Some(original) else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let observed = prepare_program_check_requests_owned(owner, input, original)
  owner.busy = false
  if observed is Err(issue) {
    return Err(issue)
  }
  if owner.phase != RequestsInspected {
    return observed
  }
  match
    reconcile_program_check_environment_scratch(
      owner,
      RequestsInspected,
      RequestsMetadataRetained,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.busy = true
  let result = prepare_program_check_requests_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_program_check_requests_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  original : @checked.ParsedCheckRegistry,
) -> Result[@checked.ParsedCheckRegistry, ClientProgramCheckPreparationIssue] {
  if owner.phase == CarriersRetained {
    if owner.requests_quote is None {
      guard program_catalog_extent_cost(
          @checked.parsed_requests_inspection_extent(original),
        )
        is Some(peak) &&
        program_catalog_extent_cost(
          @checked.parsed_requests_inspection_retained_extent(),
        )
        is Some(held) &&
        held <= peak else {
        return Err(Overflow)
      }
      owner.requests_quote = Some((peak, held))
    }
    let (metadata, _) = owner.requests_quote.unwrap()
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(r, metadata, 1L)
      is Some(r1) &&
      @execution.checked_preparation_add_product(e, metadata, 1L) is Some(e1) else {
      return Err(Overflow)
    }
    match
      @resources.reserve_working_preparation_phase(
        owner.capacity,
        input,
        r1,
        e1,
      ) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => owner.phase = RequestsObservationFunded
    }
  }
  if owner.phase == RequestsObservationFunded {
    let work = match
      @resources.begin_preparation_phase_work64(
        owner.capacity,
        input,
        @resources.CatalogRequestsInspection,
        @checked.parsed_check_requests_inspection_bound(original),
      ) {
      Err(issue) => {
        owner.phase = Failed
        return Err(Work(issue))
      }
      Ok(value) => value
    }
    owner.work = Some(work)
    let observed = @checked.prepare_parsed_requests_input(original)
    let spent = match observed {
      Ok(value) => {
        owner.requests_input = Some(value)
        @checked.parsed_requests_inspection_work(value)
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
    let (metadata, held) = owner.requests_quote.unwrap()
    owner.environment_scratch = Some(metadata - held)
    owner.phase = RequestsInspected
    // Return the entire observation/Map frame before reconciliation. The
    // immutable input remains retained and is reused after a failed grow.
    return Ok(original)
  }
  guard owner.phase == RequestsMetadataRetained else { return Err(WrongPhase) }
  let prepared = owner.requests_input.unwrap()
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  if owner.requests_body_quote is None {
    guard program_catalog_extent_cost(
        @checked.parsed_requests_construction_extent(prepared),
      )
      is Some(bytes) &&
      program_catalog_extent_cost(
        @checked.parsed_requests_retained_extent(prepared),
      )
      is Some(retained) &&
      retained <= bytes else {
      return Err(Overflow)
    }
    owner.requests_body_quote = Some((bytes, retained))
  }
  let (bytes, retained) = owner.requests_body_quote.unwrap()
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r1) &&
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
      @resources.CatalogRequestsAdmission,
      @checked.parsed_requests_semantic_work(prepared).to_int64(),
    ) {
    Err(issue) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Ok(value) => value
  }
  owner.work = Some(work)
  let (result, spent) = @checked.observe_parsed_check_requests(prepared)
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
      owner.phase = RequestsPrepared
      Ok(original)
    }
  }
}

///|
/// Only after the original reader returned; the same typed outputs, original
/// budget/metadata and outside debit remain held on this request's parent.
pub fn[I, P] reconcile_program_check_requests(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[Unit, ClientProgramCheckPreparationIssue] {
  reconcile_program_check_environment_scratch(
    owner,
    RequestsPrepared,
    RequestsRetained,
  )
}
