///|
fn event_or_relation_records(input : @carrier.Carrier) -> @carrier.Knowledge? {
  match input {
    Relation(records) => Some(records)
    EventValue(event) => Some(event.records)
    _ => None
  }
}

///|
fn preserve_record_keys(
  previous : KeySet,
  input : @carrier.Carrier,
  output : @carrier.Carrier,
  source : @decode.Cursor,
  limits : TransferLimits,
) -> KeySetTransfer raise Stop {
  if limits.max_work < 0 || limits.max_name_bytes < 0 {
    fail(source, InvalidLimits)
  }
  guard event_or_relation_records(input) is Some(input) &&
    same_records(previous.records, input) else {
    fail(source, InputContractMismatch)
  }
  guard event_or_relation_records(output) is Some(records) else {
    fail(source, InputContractMismatch)
  }
  let b : TransferBudget = {
    work: limits.max_work,
    text: limits.max_name_bytes,
  }
  spend(b, source, 1)
  spend(b, source, previous.witnesses.length())
  let witnesses = previous.witnesses.map(key => { ..key, records, })
  let work = limits.max_work - b.work
  { keys: { records, witnesses, work, name_bytes: 0, }, work, name_bytes: 0, }
}

///|
/// Checked event operations preserve or select occurrences without changing
/// existing fields. Roles alone do not supply a missing uniqueness witness.
pub fn transfer_event_keys(
  previous : KeySet,
  operation : @event.CheckedEvent,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  Ok(
    preserve_record_keys(
      previous,
      @event.input(operation),
      @event.output(operation),
      @event.source(operation),
      limits,
    ),
  ) catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn transfer_events_projection_keys(
  previous : KeySet,
  operation : @projection.CheckedProjection,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    if @projection.operation(operation) != @projection.Events {
      fail(@projection.source(operation), InputContractMismatch)
    }
    Ok(
      preserve_record_keys(
        previous,
        @projection.input(operation),
        @projection.output(operation),
        @projection.source(operation),
        limits,
      ),
    )
  } catch {
    Stop(e) => Err(e)
  }
}
