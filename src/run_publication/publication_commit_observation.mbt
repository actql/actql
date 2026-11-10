///|
/// Reuse the complete bounded validator with the original completed evidence
/// and admitted physical Store contracts. The view permits one validation only;
/// equal-looking later inputs cannot replace it or restart its logical work.
/// This does not inspect a Store, grant publisher access or acknowledge a Run.
pub fn PublicationCommitPreparation::begin_observed_commit(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  stored_request : PublicationContract,
  stored_attempt : PublicationContract,
  stored_index : PublicationContract,
) -> Result[Unit, PublicationCommitIssue] {
  let inputs = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(issue)
  }
  if view.observed is Some(_) {
    return Err(CommitEncoding)
  }
  if stored_request.identity != inputs.request.identity {
    return Err(CommitReferenceMismatch("stored_request"))
  }
  let remaining = preparation.max_workspace - preparation.live
  if remaining < 12 {
    return Err(CommitEncoding)
  }
  if preparation.retained_effectful is Some(_) && remaining < 13 {
    return Err(CommitEncoding)
  }
  let child = new_publication_commit_preparation(
    {
      ..inputs,
      origin: BorrowedInputs,
      request: stored_request,
      attempt: stored_attempt,
      index_entry: stored_index,
    },
    remaining,
  )
  child.retained_effectful = preparation.retained_effectful
  if child.retained_effectful is Some(_) {
    child.live += 1
    child.peak = child.live
  }

  // A stored read or an owned Plan may observe the exact three immutable
  // contracts its completed view just fully validated. Both own private copied
  // inventories. General borrowed arrays, copied contracts and changed
  // observations still take the complete validator above. Physical reads,
  // current checks, the observed child and separate cleanup remain unchanged.
  let stored_inputs = match inputs.origin {
    StoredInputs | OwnedInputs => true
    BorrowedInputs => false
  }
  if stored_inputs &&
    physical_equal(stored_request, inputs.request) &&
    physical_equal(stored_attempt, inputs.attempt) &&
    physical_equal(stored_index, inputs.index_entry) {
    child.phase = OriginalStored
  }
  view.observed = Some(child)
  preparation.peak = Int::max(preparation.peak, preparation.live + child.peak)
  Ok(())
}

///|
/// The caller charges returned work to the same original invocation limit and
/// retains physical input/output loans. No new work budget is issued here.
pub fn PublicationCommitPreparation::advance_observed_commit(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  quantum : Int,
) -> Result[(Bool, Int), PublicationCommitIssue] {
  match preparation.read_view_inputs(view) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard view.observed is Some(child) else { return Err(CommitEncoding) }
  let result = child.advance(quantum)
  preparation.peak = Int::max(preparation.peak, preparation.live + child.peak)
  result
}

///|
/// Return the actually stored index after complete original-chain validation.
/// Different attempt/time is allowed by the existing committed-content rule;
/// the candidate is never re-issued or substituted for this stored contract.
/// Current six physical facts/publisher authority and durable ACK remain separate.
pub fn PublicationCommitPreparation::finish_observed_commit(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
) -> Result[PublicationContract, PublicationCommitIssue] {
  let original = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(issue)
  }
  guard view.observed is Some(child) &&
    !child.closed &&
    child.phase is Done &&
    child.inputs is Some(stored) else {
    return Err(CommitEncoding)
  }
  if !public_index_same_committed_content(
      stored.index_entry,
      original.index_entry,
    ) {
    return Err(CommitReferenceMismatch("stored_index"))
  }
  Ok(stored.index_entry)
}

///|
/// Retire only the same stored-chain borrow after physical loan/output cleanup.
/// Cancellation prevents reads but does not itself prove that physical cleanup
/// completed. The original view remains held until release_view succeeds.
pub fn PublicationCommitPreparation::release_observed_commit(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
) -> Result[Unit, PublicationCommitIssue] {
  guard preparation.view is Some(original) &&
    physical_equal(original, view) &&
    !view.released &&
    view.owner is Some(owner) &&
    physical_equal(owner, preparation) &&
    view.observed is Some(child) else {
    return Err(CommitEncoding)
  }
  child.cancel()
  Ok(())
}
