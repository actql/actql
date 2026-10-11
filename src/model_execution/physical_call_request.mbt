///|
// The fixed physical adapter already owns the original request. The consumed
// Entry carries its own original prepared call set; no late adapter callback
// or caller-supplied call-set alias is needed to register physical custody.
// Request equality is nominal, not matching wire bytes or a reported CID.
pub fn model_physical_call_for_request(
  entry : ModelCallEntry,
  request : ModelRequest,
  poll : () -> ModelPhysicalCallPoll,
  cancel : () -> Unit,
  cleanup : (Bool) -> Bool,
) -> ModelPhysicalCall? {
  guard entry.prepared.owner.state.requests.get(entry.slot) is Some(original) &&
    physical_equal(original.request, request) else {
    return None
  }
  // Preserve all existing consumed-entry, current phase, original attempt,
  // fixed asynchronous plan and open-reservation checks in the same Owner.
  model_physical_call(entry, entry.prepared, poll, cancel, cleanup)
}
