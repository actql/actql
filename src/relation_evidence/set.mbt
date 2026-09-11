///|
/// Both policies select left occurrences without changing their values. Wider
/// output field contracts do not invalidate the original left key witness.
pub fn transfer_set_keys(
  previous : KeySet,
  operation : @set.CheckedSet,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @set.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @carrier.complete_schema(previous.records) is Some(left) &&
      physical_equal(left, @set.input_schema(operation, Left)) else {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    spend(b, source, previous.witnesses.length())
    let records = @carrier.typed_rows(@set.output_schema(operation))
    let witnesses = previous.witnesses.map(key => { ..key, records, })
    let work = limits.max_work - b.work
    Ok({
      keys: { records, witnesses, work, name_bytes: 0, },
      work,
      name_bytes: 0,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
/// Adds whole-row uniqueness for DISTINCT without discarding left witnesses.
/// The checked producer still has execution and comparison obligations.
pub fn advance_set_keys(
  previous : KeySet?,
  operation : @set.CheckedSet,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @set.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let (records, witnesses) = match previous {
      Some(previous) => {
        let transfer = match transfer_set_keys(previous, operation, limits) {
          Ok(v) => v
          Err(e) => raise Stop(e)
        }
        b.work -= transfer.work
        b.text -= transfer.name_bytes
        (transfer.keys.records, transfer.keys.witnesses.copy())
      }
      None => {
        spend(b, source, 1)
        (@carrier.typed_rows(@set.output_schema(operation)), [])
      }
    }
    if @set.duplicates(operation) == @set.Distinct {
      let output = @set.output_schema(operation)
      let n = @row.field_count(output)
      spend(b, source, n)
      let fields : Array[KeyField] = []
      for i = 0; i < n; i = i + 1 {
        let field = @row.field_at(output, i).unwrap()
        charge(b, source, field.name)
        fields.push(plain_key_field(field.name, Some(field.contract)))
      }
      // An empty tuple is cardinality evidence, not a fabricated field ID.
      if !fields.is_empty() {
        witnesses.push({
          origin: SetDistinctResult,
          producer: Some(SetProducer(operation)),
          records,
          declared_records: records,
          declared_fields: fields,
          fields,
          aliases: fields.map(field => [field]),
          source,
          usage: { fields: n, name_bytes: limits.max_name_bytes - b.text, },
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

///|
pub fn key_set_producer(key : KeyedRelation) -> @set.CheckedSet? {
  match key.producer {
    Some(SetProducer(operation)) => Some(operation)
    _ => None
  }
}
