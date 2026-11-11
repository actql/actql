///|
/// Persistence observations are not transport outcomes or send permission.
/// NotRecorded requires an affirmative observation of absence; an exception
/// or a missing acknowledgement is Unknown, never NotRecorded.
pub(all) enum ModelEntryPersistenceObservation {
  Pending
  NotRecorded
  Unknown
  Saved(ModelCallEntryAcknowledgement)
}

///|
/// A physical adapter view of one retained original Entry, not a second owner.
/// The installed adapter must fund its descriptor and closure captures before
/// installation. This carrier alone does not enable asynchronous dispatch.
pub struct ModelCallEntryPersistence {
  mut entry : ModelCallEntry?
  mut poll : (() -> ModelEntryPersistenceObservation)?
  mut terminal : Result[ModelEntryPersistenceObservation, ModelExecutionIssue]?
  mut polling : Bool
  mut refused : Bool
}

///|
/// Begin only from a currently owned entry. A pending save may later complete
/// after stop or revocation, but cannot reconstruct a reclaimed entry.
pub fn model_call_entry_persistence(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
  poll : () -> ModelEntryPersistenceObservation,
) -> ModelCallEntryPersistence? {
  if !model_call_entry_current(entry, prepared) || entry.send_started {
    return None
  }
  if entry.persistence is Some(original) {
    return Some(original)
  }
  if check_model_original_resources_mutable(entry.prepared.owner.state)
    is Err(_) {
    return None
  }
  let operation : ModelCallEntryPersistence = {
    entry: Some(entry),
    poll: Some(poll),
    terminal: None,
    polling: false,
    refused: false,
  }
  entry.persistence = Some(operation)
  Some(operation)
}

///|
/// Polling never re-enters a save or issues a transport claim. A terminal
/// result is immutable; the original ACK is checked by physical identity.
pub fn poll_model_call_entry_persistence(
  operation : ModelCallEntryPersistence,
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
) -> Result[ModelEntryPersistenceObservation, ModelExecutionIssue] {
  if operation.polling ||
    !(operation.entry is Some(original) && physical_equal(original, entry)) ||
    !(entry.persistence is Some(original) && physical_equal(original, operation)) ||
    !model_call_entry_persistence_owned(entry, prepared) ||
    entry.send_started {
    return Err(CallEntryRefused)
  }
  if operation.terminal is Some(original) {
    return original
  }
  if check_model_original_resources_mutable(entry.prepared.owner.state)
    is Err(issue) {
    return Err(issue)
  }
  guard operation.poll is Some(poll) else { return Err(CallEntryRefused) }
  operation.polling = true
  let observed = poll()
  operation.polling = false
  if check_model_original_resources_mutable(entry.prepared.owner.state)
    is Err(issue) {
    return Err(issue)
  }
  // The callback may deliver cancellation/revocation but cannot replace the
  // original retained owner while this observation is being adopted.
  if !model_call_entry_persistence_owned(entry, prepared) || entry.send_started {
    return Err(CallEntryRefused)
  }
  match observed {
    Pending => ()
    Saved(acknowledgement) => {
      guard physical_equal(acknowledgement.entry, entry) &&
        entry.acknowledgement is Some(original) &&
        physical_equal(acknowledgement, original) else {
        operation.terminal = Some(Err(CallEntryRefused))
        operation.poll = None
        return Err(CallEntryRefused)
      }
      operation.terminal = Some(Ok(observed))
    }
    NotRecorded | Unknown => operation.terminal = Some(Ok(observed))
  }
  if operation.terminal is Some(_) {
    if operation.refused {
      operation.terminal = Some(Err(CallEntryRefused))
    }
    // Cached terminal observation needs no adapter closure or its captures.
    operation.poll = None
  }
  match operation.terminal {
    Some(result) => result
    None => Ok(observed)
  }
}

///|
// Only the existing Entry owner retires its view before releasing entering.
// A view escaped by an adapter can neither retain its closure nor poll again.
fn retire_model_call_entry_persistence(entry : ModelCallEntry) -> Unit {
  if entry.persistence is Some(operation) {
    operation.poll = None
    operation.entry = None
    entry.persistence = None
  }
}

///|
fn retire_model_entering(state : ModelState) -> Unit {
  if state.progress.entry is Some(entry) {
    retire_model_call_entry_persistence(entry)
    // The owner is retiring this entering slot after send/terminal cleanup.
    // An escaped ACK keeps its original Entry, but the Entry must not retain
    // its ACK in return. This severs no pending persistence or physical duty.
    entry.acknowledgement = None
    state.progress.entry = None
  }
}

///|
fn retain_model_entry_attempt(
  state : ModelState,
  entry : ModelCallEntry,
) -> Unit {
  if !state.attempts.contains(entry.slot) {
    state.attempts[entry.slot] = entry.trace
    state.attempt_slots.push(entry.slot)
  }
}

///|
// Adopt persistence responsibility before any final stop or current check.
// The actual send gate still distinguishes an acknowledged save from permission.
fn model_entry_persistence_issue(state : ModelState) -> ModelExecutionIssue? {
  guard state.progress.entry is Some(entry) &&
    entry.persistence is Some(operation) else {
    return None
  }
  match operation.terminal {
    Some(Ok(NotRecorded)) => Some(CallEntryRefused)
    Some(Ok(Saved(_))) => {
      retain_model_entry_attempt(state, entry)
      None
    }
    Some(Ok(Unknown)) => {
      retain_model_entry_attempt(state, entry)
      Some(UnknownCalls)
    }
    Some(Err(issue)) => {
      retain_model_entry_attempt(state, entry)
      Some(issue)
    }
    _ => {
      // A malformed returned handle never proves an absent durable entry.
      retain_model_entry_attempt(state, entry)
      Some(CallEntryRefused)
    }
  }
}
