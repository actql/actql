///|
/// A nominal read-only borrow of the original, fully validated commit inputs.
/// This is neither current publisher authority nor physical Store completion.
struct PublicationCommitReadView {
  mut owner : PublicationCommitPreparation?
  mut released : Bool
  mut observed : PublicationCommitPreparation?
}

///|
/// Retain one descriptor within the original workspace budget. No contract is
/// copied, re-admitted, re-issued or written to a Store by this operation.
pub fn PublicationCommitPreparation::finish_view(
  preparation : PublicationCommitPreparation,
) -> Result[PublicationCommitReadView, PublicationCommitIssue] {
  if preparation.closed ||
    preparation.view is Some(_) ||
    preparation.inputs is None ||
    !(preparation.phase is Done) ||
    preparation.live >= preparation.max_workspace ||
    (preparation.retained_capture is Some(original) && original.closed) {
    return Err(CommitEncoding)
  }
  // The new fully checked commit view retains its own original inputs. It no
  // longer needs to borrow the earlier capture's computation-fact holder.
  if preparation.retained_capture is Some(_) {
    preparation.retained_capture = None
    preparation.live -= 1
  }
  let view = { owner: Some(preparation), released: false, observed: None, }
  preparation.view = Some(view)
  preparation.live += 1
  preparation.peak = Int::max(preparation.peak, preparation.live)
  Ok(view)
}

///|
fn PublicationCommitPreparation::read_view_inputs(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
) -> Result[PublicationCommitInputs, PublicationCommitIssue] {
  guard !preparation.closed &&
    !view.released &&
    view.owner is Some(owner) &&
    physical_equal(preparation, owner) &&
    preparation.view is Some(original) &&
    physical_equal(original, view) &&
    preparation.phase is Done &&
    preparation.inputs is Some(inputs) else {
    return Err(CommitEncoding)
  }
  Ok(inputs)
}

///|
/// Fixed eight root references and six original inventories, in argument order.
/// Counting touches six lengths, never the inventory contents or wire bytes.
pub fn PublicationCommitPreparation::view_count(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
) -> Result[Int, PublicationCommitIssue] {
  let inputs = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(issue)
  }
  let chain = inputs.computation
  let count = 8L +
    chain.definitions.length().to_int64() +
    chain.artifacts.length().to_int64() +
    inputs.derivations.length().to_int64() +
    inputs.orderings.length().to_int64() +
    inputs.retentions.length().to_int64() +
    inputs.bindings.length().to_int64()
  if count > 2147483647L {
    return Err(CommitEncoding)
  }
  Ok(count.to_int())
}

///|
/// Return one original immutable contract. Selection has six fixed inventory
/// boundaries, independent of inventory size, and never scans contract bytes.
pub fn PublicationCommitPreparation::view_contract(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  ordinal : Int,
) -> Result[PublicationContract, PublicationCommitIssue] {
  let inputs = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(issue)
  }
  if ordinal < 0 {
    return Err(CommitEncoding)
  }
  let chain = inputs.computation
  match ordinal {
    0 => return Ok(chain.run_definition)
    1 => return Ok(chain.invocation)
    2 => return Ok(chain.manifest)
    3 => return Ok(chain.receipt)
    4 => return Ok(chain.captured_run)
    5 => return Ok(inputs.request)
    6 => return Ok(inputs.attempt)
    7 => return Ok(inputs.index_entry)
    _ => ()
  }
  let mut offset = ordinal - 8
  if offset < chain.definitions.length() {
    return Ok(chain.definitions[offset])
  }
  offset -= chain.definitions.length()
  if offset < chain.artifacts.length() {
    return Ok(chain.artifacts[offset])
  }
  offset -= chain.artifacts.length()
  if offset < inputs.derivations.length() {
    return Ok(inputs.derivations[offset])
  }
  offset -= inputs.derivations.length()
  if offset < inputs.orderings.length() {
    return Ok(inputs.orderings[offset])
  }
  offset -= inputs.orderings.length()
  if offset < inputs.retentions.length() {
    return Ok(inputs.retentions[offset])
  }
  offset -= inputs.retentions.length()
  if offset < inputs.bindings.length() {
    return Ok(inputs.bindings[offset])
  }
  Err(CommitEncoding)
}

///|
/// Borrow one original binding by its supplied inventory index. This index is
/// independent of checked Result occurrence order. No scan, re-sealing or
/// inference of physical Store completion is performed.
pub fn PublicationCommitPreparation::view_binding(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  binding_index : Int,
) -> Result[PublicationContract, PublicationCommitIssue] {
  let inputs = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(issue)
  }
  if binding_index < 0 || binding_index >= inputs.bindings.length() {
    return Err(CommitEncoding)
  }
  Ok(inputs.bindings[binding_index])
}

///|
/// Release only after the original output/borrow owner confirms physical
/// cleanup. Cancellation blocks reads immediately but does not release inputs.
/// Retrying this release on the same owner/view is idempotent.
pub fn PublicationCommitPreparation::release_view(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
) -> Result[Unit, PublicationCommitIssue] {
  guard preparation.view is Some(original) && physical_equal(original, view) else {
    return Err(CommitEncoding)
  }
  if view.released {
    return Ok(())
  }
  guard view.owner is Some(owner) && physical_equal(preparation, owner) else {
    return Err(CommitEncoding)
  }
  // A live stored-chain validation still borrows the original inventories.
  if view.observed is Some(child) && !child.closed {
    return Err(CommitEncoding)
  }
  view.released = true
  // Preserve the exact retired token for idempotent cleanup. Break the owner
  // back-reference only after both nominal checks and successful cleanup.
  view.owner = None
  preparation.inputs = None
  preparation.retained_effectful = None
  preparation.live = 0
  preparation.closed = true
  Ok(())
}
