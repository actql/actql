///|
/// Fixed Local cleanup custody, not a new Resource or callback authority.
/// The holder owns this Run's heavy fields; its admission owns a separate
/// original holder. Existing output/operation/handler holders remain distinct.
struct ClientManagedPreparationRetirement {
  retirement : @resources.PreparationRetirement
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ]
  mut holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]?
}

///|
/// Dormant fixed-Root entry. The supplier must fund constructor coexistence
/// and retain every original dependency before calling; no SDK path currently
/// selects it. Unlike the legacy entry, this consumes the already started
/// input admission and never starts a second imported child.
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
  guard original.owner is Pure(owner) && physical_equal(owner, prepared) else {
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
  let holder = match @resources.borrow_preparation_body(capacity) {
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      return Err(Ledger(issue))
    Err(_) => return Err(CleanupPending)
    Ok(value) => value
  }
  let (admission, ledger, retirement) = match
    @resources.adopt_node_preparation_admission(
      initial, input, capacity, prepared,
    ) {
    Err(issue) => {
      // The same initial owner retains failed adoption cleanup. This one
      // provisional Run holder must not strand another borrower on that owner.
      @resources.return_preparation_body_borrow(holder) |> ignore
      return Err(Resource(issue))
    }
    Ok(value) => value
  }
  let value = new_installed_managed_run(admission, prepared, request, ledger)
  value.source_free_preparation = Some(original)
  value.preparation_retirement = Some({
    retirement,
    admission,
    holder: Some(holder),
  })
  Ok(value)
}

///|
/// The fixed dispatch owner invokes this only after operation quiescence and
/// existing physical stop/output-close witnesses. Isolated usage below is an
/// additional accounting check, never a replacement for those witnesses.
fn retire_preparation_owned_installed_run(
  value : ClientInstalledManagedRun,
  original : ClientManagedPreparationRetirement,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.ledger is Some(ledger) else { return Ok(()) }
  if value.preparation is Some(_) &&
    !@resources.node_preparation_usage_isolated(original.admission, ledger) {
    return Err(CleanupPending)
  }
  match @resources.retire_transferred_preparation(original.retirement) {
    Err(@resources.PreparationCapacityIssue::Resource(issue)) =>
      return Err(Ledger(issue))
    Err(_) => return Err(CleanupPending)
    Ok(_) => ()
  }
  // Fence new Run borrows and remove actual raw owners before returning either
  // durable holder. An existing operation must use its own registered borrow.
  value.preparation = None
  value.source_free_preparation = None
  value.keyed = None
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
  match @resources.release_node_preparation_holder(original.admission) {
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
  match @resources.cleanup_node_managed_run_admission(original.admission) {
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
  guard value.original is Some(original) && physical_equal(original,value) &&
    physical_equal(value.request,request) && value.ledger is Some(ledger) &&
    value.preparation_retirement is Some(retirement) &&
    value.preparation is None && value.source_free_preparation is None &&
    retirement.holder is None else { return false }
  @resources.check_node_preparation_cleanup_original(retirement.admission,ledger) is Ok(_)
}
