///|
/// Same Request continuation. Fixed controls reserve separately before this
/// record; the original Source and all previously retained normalization remain
/// in baseline. No caller byte policy, second Ledger or admission is created.
priv struct ClientRequestProgramAuthoring {
  original : @publication_host.PreparedClientProgram
  compiler : @publication_host.ClientProgramPreparationLimits
  baseline : (Int64, Int64)
  mut inventory : @publication_host.ClientAuthoringCollectionGeometry?
  mut collection_quote : (Int64, Int64)?
  mut preparation : @publication_host.ClientAuthoringContextPreparation?
  mut construction : @publication_host.ClientAuthoringContextConstruction?
  mut publication_quote : (Int64, Int64, Int64)?
  mut work : @resources.PreparationPhaseWorkContinuation64?
  mut returned : Bool
  mut charged_work : Int64
  mut result : Result[
    @publication_host.ClientAuthoringContextPreparation,
    ClientRequestAuthoringIssue,
  ]?
}

///|
pub suberror ClientRequestAuthoringIssue {
  Preparation(ClientRequestPreparationIssue)
  Authoring(@publication_host.ClientAuthoringContextIssue)
}

///|
fn request_authoring_targets(
  original : ClientRequestProgramAuthoring,
  retained : Int64,
  execution : Int64,
) -> (Int64, Int64)? {
  guard @execution.checked_preparation_add_product(
      original.baseline.0,
      request_authoring_control_bytes(),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(r, retained, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(
      original.baseline.1,
      request_authoring_control_bytes(),
      1L,
    )
    is Some(e) &&
    @execution.checked_preparation_add_product(e, execution, 1L) is Some(e) else {
    return None
  }
  Some((r, e))
}

///|
fn[I] grow_request_authoring(
  input : I,
  state : ClientRequestProgramAuthoring,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ClientRequestAuthoringIssue] {
  if state.work is Some(work) && !state.returned {
    match @resources.return_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Preparation(Work(issue)))
      Ok(_) => state.returned = true
    }
  }
  match
    @resources.reserve_working_preparation_phase(
      capacity, input, retained, execution,
    ) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(_) => ()
  }
  if state.work is Some(work) && state.returned {
    match @resources.resume_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Preparation(Work(issue)))
      Ok(_) => state.returned = false
    }
  }
  Ok(())
}

///|
fn authoring_spend(
  state : ClientRequestProgramAuthoring,
  units : Int64,
) -> Result[Unit, ClientRequestAuthoringIssue] {
  guard state.work is Some(work) else { return Err(Preparation(WrongPhase)) }
  guard @execution.checked_preparation_add_product(
      state.charged_work,
      units,
      1L,
    )
    is Some(total) else {
    return Err(Preparation(Policy))
  }
  state.charged_work = total
  @resources.spend_preparation_phase_work_continuation64(work, units).map_err(issue => {
    Preparation(Work(issue))
  })
}

///|
/// Retain actual annotations/output before any Plan borrow on this SAME input.
/// A retry reuses original measured/constructed stages; it cannot re-read a
/// Source or replace an original after failed work/current/constructor return.
pub fn[I] prepare_request_program_authoring_context(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.ClientAuthoringContextPreparation,
  ClientRequestAuthoringIssue,
] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard owner.phase == ProgramCompiled &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.computation_limits is Some(compiler) else {
    return Err(Preparation(WrongPhase))
  }
  owner.phase = Selecting
  defer {
    owner.phase = ProgramCompiled
  }
  if owner.program_authoring is None {
    let base = match
      @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(
        base.0,
        request_authoring_control_bytes(),
        1L,
      )
      is Some(r) &&
      @execution.checked_preparation_add_product(
        base.1,
        request_authoring_control_bytes(),
        1L,
      )
      is Some(e) else {
      return Err(Preparation(Policy))
    }
    // No observer, state record, path, collection or work cell exists before
    // this grow/current callback. The initial Request already backs its field.
    match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(_) => ()
    }
    owner.program_authoring = Some({
      original: prepared,
      compiler,
      baseline: base,
      inventory: None,
      collection_quote: None,
      preparation: None,
      construction: None,
      publication_quote: None,
      work: None,
      returned: false,
      charged_work: 0L,
      result: None,
    })
  }
  let state = owner.program_authoring.unwrap()
  if !physical_equal(state.original, prepared) ||
    !physical_equal(state.compiler, compiler) {
    return Err(Preparation(ForeignOriginal))
  }
  if state.result is Some(result) {
    if result is Ok(_) {
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(_) => ()
      }
    }
    return result
  }
  let result = prepare_request_program_authoring_owned(
    owner, input, state, capacity,
  )
  if result is Err(issue) {
    state.result = Some(Err(issue))
    ignore(finish_request_program_authoring_work(owner))
  }
  result
}

///|
fn[I] prepare_request_program_authoring_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  state : ClientRequestProgramAuthoring,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
) -> Result[
  @publication_host.ClientAuthoringContextPreparation,
  ClientRequestAuthoringIssue,
] {
  let codec = state.compiler.checking.compilation.artifacts
  if state.work is None {
    let work = match
      @resources.begin_preparation_phase_work_continuation64(
        capacity,
        input,
        @resources.AuthoringContext,
        state.compiler.checking.compilation.work.to_int64(),
      ) {
      Err(issue) => return Err(Preparation(Work(issue)))
      Ok(value) => value
    }
    state.work = Some(work)
  }
  if state.inventory is None {
    let (result, known) = @publication_host.observe_client_authoring_collection_geometry(
      state.original,
      state.compiler.checking.compilation.work.to_int64(),
    )
    if result is Ok(original) {
      state.inventory = Some(original)
    }
    let charged = authoring_spend(state, known)
    if result is Err(issue) {
      return Err(Authoring(issue))
    }
    match charged {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let inventory = state.inventory.unwrap()
  if state.collection_quote is None {
    guard request_authoring_collection_extents(inventory) is Some((r, e)) &&
      request_authoring_targets(state, r, e) is Some(quote) else {
      return Err(Preparation(Policy))
    }
    state.collection_quote = Some(quote)
  }
  if state.preparation is None {
    let quote = state.collection_quote.unwrap()
    match grow_request_authoring(input, state, capacity, quote.0, quote.1) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    // Declared original visit/path construction dimensions, not VM/CPU time.
    guard @execution.checked_preparation_add_product(0L, inventory.work, 2L)
      is Some(work) &&
      @execution.checked_preparation_add_product(work, inventory.path_utf16, 6L)
      is Some(work) &&
      @execution.checked_preparation_add_product(
        work,
        inventory.items.to_int64(),
        1L,
      )
      is Some(work) else {
      return Err(Preparation(Policy))
    }
    match authoring_spend(state, work) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let original = match
      @publication_host.prepare_client_authoring_context(
        state.original,
        codec.bytes,
        codec.nodes,
        codec.depth,
      ) {
      Err(issue) => return Err(Authoring(issue))
      Ok(value) => value
    }
    state.preparation = Some(original)
  }
  let original = state.preparation.unwrap()
  if state.construction is None {
    let construction = match
      @publication_host.measure_prepared_client_authoring_context(original) {
      Err(issue) => return Err(Authoring(issue))
      Ok(value) => value
    }
    state.construction = Some(construction)
    let known = construction.body.bytes.to_int64() +
      construction.body.nodes.to_int64() +
      construction.complete.bytes.to_int64() +
      construction.complete.nodes.to_int64()
    match authoring_spend(state, known) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let construction = state.construction.unwrap()
  if state.publication_quote is None {
    guard request_evidence_publication_extents(construction.complete)
      is Some((output, scratch)) &&
      state.collection_quote is Some(collection) &&
      @execution.checked_preparation_add_product(collection.0, output, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(collection.1, output, 1L)
      is Some(e) &&
      @execution.checked_preparation_add_product(e, scratch, 1L) is Some(e) else {
      return Err(Preparation(Policy))
    }
    state.publication_quote = Some((r, e, output))
  }
  let quote = state.publication_quote.unwrap()
  match grow_request_authoring(input, state, capacity, quote.0, quote.1) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match authoring_spend(state, construction.body.bytes.to_int64() * 4L) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @publication_host.finish_prepared_client_authoring_context(original) {
    Err(issue) => return Err(Authoring(issue))
    Ok(_) => ()
  }
  match finish_request_program_authoring_work(owner) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  // Finished proof:1H/4R/3W + cached result/Some2H/2R/2W. Heavy vector,
  // paths, initial Writer and failed-child construction are cut ONLY on success.
  guard @execution.checked_preparation_add_product(quote.2, 136L, 1L)
    is Some(held) &&
    request_authoring_targets(state, held, held) is Some(retained) else {
    return Err(Preparation(Policy))
  }
  match
    @resources.reconcile_working_preparation_phase(
      capacity,
      input,
      retained.0,
      retained.1,
    ) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(_) => ()
  }
  state.result = Some(Ok(original))
  state.preparation = None
  state.inventory = None
  state.construction = None
  state.collection_quote = None
  state.publication_quote = None
  state.result.unwrap()
}

///|
fn[I] finish_request_program_authoring_work(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.program_authoring is Some(state) && state.work is Some(work) {
    match @resources.finish_preparation_phase_work_continuation64(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => state.work = None
    }
  }
  Ok(())
}
