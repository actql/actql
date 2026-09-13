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
/// Preserves input witnesses and generates conditional operation keys.
pub fn transfer_event_keys(
  previous : KeySet,
  operation : @event.CheckedEvent,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  advance_event_keys(Some(previous), operation, limits)
}

///|
pub fn key_event_producer(key : KeyedRelation) -> @event.CheckedEvent? {
  match key.producer {
    Some(EventProducer(operation)) => Some(operation)
    _ => None
  }
}

///|
pub fn advance_event_keys(
  previous : KeySet?,
  operation : @event.CheckedEvent,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @event.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    guard event_or_relation_records(@event.output(operation)) is Some(records) else {
      fail(source, InputContractMismatch)
    }
    let witnesses : Array[KeyedRelation] = match previous {
      Some(previous) => {
        let transferred = preserve_record_keys(
          previous,
          @event.input(operation),
          @event.output(operation),
          source,
          limits,
        )
        b.work -= transferred.work
        b.text -= transferred.name_bytes
        transferred.keys.witnesses
      }
      None => {
        spend(b, source, 1)
        []
      }
    }
    let fields : Array[KeyField] = []
    let before = b.text
    let origin = match @event.options(operation) {
      ToEvents => {
        guard @event.output(operation) is @carrier.EventValue(event) else {
          fail(source, InputContractMismatch)
        }
        spend(b, source, 1)
        charge(b, source, event.identity.name)
        fields.push(
          plain_key_field(event.identity.name, event.identity.contract),
        )
        Some(EventIdentityResult)
      }
      Dedupe(spec) => {
        spend(b, source, @event.dedupe_key_count(spec))
        let seen : Map[String, Bool] = Map([])
        for i in 0..<@event.dedupe_key_count(spec) {
          let name = @event.dedupe_key_at(spec, i).unwrap()
          charge(b, source, name)
          let key = field_key(name)
          if !seen.contains(key) {
            seen[key] = true
            guard @carrier.lookup(records, name) is Present(field) else {
              fail(source, InputContractMismatch)
            }
            fields.push(plain_key_field(name, field.contract))
          }
        }
        Some(EventDedupeResult)
      }
      // A session labels several records; neither it nor a watermark readmits
      // record identity after a window has expanded membership occurrences.
      Session(_) | Watermark(_, _) => None
    }
    if origin is Some(origin) && !fields.is_empty() {
      spend(b, source, fields.length() + 1)
      witnesses.push({
        origin,
        producer: Some(EventProducer(operation)),
        records,
        declared_records: records,
        declared_fields: fields,
        source,
        fields,
        aliases: fields.map(field => [field]),
        usage: { fields: fields.length(), name_bytes: before - b.text, },
      })
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
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
