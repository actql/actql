///|
pub fn key_window_producer(key : KeyedRelation) -> @window.CheckedWindow? {
  match key.producer {
    Some(WindowProducer(op, _)) => Some(op)
    _ => None
  }
}

///|
/// Retained parent witness; its own admission/producer obligations still apply.
pub fn key_window_input(key : KeyedRelation) -> KeyedRelation? {
  match key.producer {
    Some(WindowProducer(_, input)) => Some(input)
    _ => None
  }
}

///|
pub fn transfer_window_keys(
  previous : KeySet,
  operation : @window.CheckedWindow,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @window.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard event_or_relation_records(@window.input(operation)) is Some(input) &&
      same_records(previous.records, input) else {
      fail(source, InputContractMismatch)
    }
    let records = event_or_relation_records(@window.output(operation)).unwrap()
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    spend(b, source, previous.witnesses.length())
    let witnesses : Array[KeyedRelation] = []
    for parent in previous.witnesses {
      if @window.kind(@window.options(operation)) == @window.Fixed {
        witnesses.push({ ..parent, records, })
      } else {
        let (name, _) = @window.boundary_fields(@window.window_roles(operation))
        charge(b, source, name)
        let contract = match @carrier.lookup(records, name) {
          Present(field) => field.contract
          _ => fail(source, InputContractMismatch)
        }
        spend(b, source, parent.fields.length() + parent.aliases.length() + 1)
        let field : KeyField = plain_key_field(name, contract)
        let fields = parent.fields.copy()
        fields.push(field)
        let aliases = parent.aliases.copy()
        aliases.push([field])
        witnesses.push({
          origin: WindowMembershipResult,
          producer: Some(WindowProducer(operation, parent)),
          records,
          declared_records: records,
          declared_fields: fields,
          source,
          fields,
          aliases,
          usage: {
            fields: fields.length(),
            name_bytes: limits.max_name_bytes - b.text,
          },
        })
      }
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
