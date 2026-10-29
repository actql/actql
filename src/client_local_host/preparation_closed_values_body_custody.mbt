///|
pub fn[I] complete_closed_values_body(
  owner : ClientClosedValuesPreparation[I],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientClosedValuesPreparationIssue,
] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) &&
    owner.prepared is Some(prepared) &&
    owner.source_free is Some(source_free) &&
    source_free.configuration is Some(_) &&
    owner.compilation is Some(_) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring || owner.manager_issued || owner.module_constructing {
    return Err(WrongPhase)
  }
  if !owner.body_ready {
    match
      @resources.complete_preparation_capacity(
        owner.capacity,
        input,
        prepared,
        owner.retained_quote,
        0L,
      ) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => {
        owner.body_ready = true
        owner.execution_quote = 0L
      }
    }
  }
  match @resources.borrow_preparation_body(owner.capacity) {
    Err(issue) => Err(Capacity(issue))
    Ok(holder) => {
      owner.manager_issued = true
      owner.manager_original = Some(holder)
      Ok(holder)
    }
  }
}

///|
pub fn[I] begin_closed_values_owned_run(
  owner : ClientClosedValuesPreparation[I],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) &&
    owner.prepared is Some(body) &&
    physical_equal(body, prepared) &&
    owner.source_free is Some(source_free) &&
    owner.compilation is Some(_) &&
    owner.body_ready &&
    owner.manager_issued &&
    !owner.retiring &&
    !owner.module_constructing &&
    !owner.adopted else {
    return Err(ForeignOriginal)
  }
  match
    begin_preparation_owned_installed_managed_run(
      owner.initial,
      input,
      owner.capacity,
      prepared,
      request,
      source_free,
    ) {
    Err(issue) => Err(issue)
    Ok(run) => {
      owner.adopted = true
      Ok(run)
    }
  }
}

///|
/// Fixed manager cut only after Core retirement has blocked new borrowers.
/// The caller must also sever its JS source/body/plan aliases before returning
/// its original holder. This function never returns that holder or settles it.
pub fn[I] sever_closed_values_body(
  owner : ClientClosedValuesPreparation[I],
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Bool {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.manager_original is Some(issued) &&
    physical_equal(issued, holder) &&
    owner.prepared is Some(prepared) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(prepared, body) &&
    @resources.preparation_body_retirement_started(holder) else {
    return false
  }
  owner.retiring = true
  owner.document = None
  owner.parsed = None
  owner.program = None
  owner.prepared = None
  owner.submitted_intent = None
  owner.compilation = None
  owner.source_free = None
  owner.shape = None
  owner.lexical = None
  owner.envelope = None
  true
}

///|
/// Same original manager token and a completed raw-reference cut. Pending
/// cleanup errors alone are never evidence that retirement began.
pub fn[I] closed_values_initial_retirement_started(
  owner : ClientClosedValuesPreparation[I],
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Bool {
  owner.original is Some(original) &&
  physical_equal(original, owner) &&
  owner.manager_original is Some(issued) &&
  physical_equal(issued, holder) &&
  !owner.adopted &&
  owner.retiring &&
  owner.prepared is None &&
  owner.source_free is None &&
  owner.compilation is None &&
  owner.document is None &&
  owner.parsed is None &&
  owner.program is None &&
  owner.submitted_intent is None &&
  @resources.preparation_body_retirement_started(holder)
}

///|
/// Fixed diagnostics only: scalar observations from the SAME original Ledger.
/// The execution maximum is derived by the observer across phases; the Ledger
/// stores only retention peak, not an execution peak counter.
pub fn[I] closed_values_preparation_accounting(
  owner : ClientClosedValuesPreparation[I],
) -> Result[
  (Int64, Int64, Int64, Int64, Int64, Int64),
  ClientClosedValuesPreparationIssue,
] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  Ok(@resources.preparation_capacity_accounting(owner.capacity))
}

///|
/// Borrow only the request-independent artifact staged by this original owner.
/// A foreign or severed preparation cannot resurrect an artifact by identity.
pub fn[I] closed_values_compilation_original(
  owner : ClientClosedValuesPreparation[I],
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.ClientValuesCompilation? {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    !owner.retiring &&
    owner.body_ready &&
    owner.prepared is Some(issued) &&
    physical_equal(issued, prepared) else {
    return None
  }
  owner.compilation
}
