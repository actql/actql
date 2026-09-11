///|
/// Disallowing overlap preserves each label's event identity across matches.
/// Actual event uniqueness and matching semantics remain producer obligations.
pub fn sequence_keys(
  operation : @relation.CheckedSequence,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @relation.sequence_source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    let output = @relation.sequence_output(operation)
    let records = @carrier.typed_rows(output)
    let witnesses : Array[KeyedRelation] = []
    if @relation.sequence_overlap(operation) == Disallow {
      let n = @relation.sequence_pattern_count(operation)
      spend(b, source, n)
      for i in 0..<n {
        let name = @row.Unqualified(
          @relation.sequence_pattern_at(operation, i).unwrap().label + "_id",
        )
        let before = b.text
        charge(b, source, name)
        let fields : Array[KeyField] = [
          { name, contract: @row.lookup(output, name), },
        ]
        witnesses.push({
          origin: SequenceResult,
          producer: Some(SequenceProducer(operation)),
          records,
          declared_records: records,
          declared_fields: fields,
          source,
          fields,
          aliases: [fields],
          usage: { fields: 1, name_bytes: before - b.text, },
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
pub fn key_sequence_producer(key : KeyedRelation) -> @relation.CheckedSequence? {
  match key.producer {
    Some(SequenceProducer(op)) => Some(op)
    _ => None
  }
}
