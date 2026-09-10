///|
fn producer_key(
  operation : @relation.CheckedOperation,
  records : @carrier.Knowledge,
  b : TransferBudget,
) -> KeyedRelation? raise Stop {
  let source = @relation.source(operation)
  let output = @relation.output_schema(operation)
  let (origin, names) : (KeyOrigin, Array[@row.FieldName]) = match
    @relation.row_operation(operation) {
    Some(AssertUnique(keys)) => {
      spend(b, source, keys.length())
      (UniqueAssertion, keys.map(key => key.field))
    }
    Some(DistinctKeys(keys)) => {
      spend(b, source, keys.length())
      (DistinctResult, keys.map(key => key.field))
    }
    Some(DedupeRows(by~, ..)) => {
      spend(b, source, by.length())
      (DedupeResult, by.map(key => key.field))
    }
    Some(DistinctRows) => {
      let n = @row.field_count(output)
      spend(b, source, n)
      (
        DistinctResult,
        Array::makei(n, i => @row.field_at(output, i).unwrap().name),
      )
    }
    _ =>
      match @relation.group(operation) {
        Some(group) => {
          let keys = @relation.group_keys(group)
          spend(b, source, keys.length())
          (GroupResult, keys.map(key => key.field))
        }
        None =>
          match @relation.pivot(operation) {
            Some(pivot) => {
              let keys = @relation.pivot_index(pivot)
              spend(b, source, keys.length())
              (PivotResult, keys.map(key => key.field))
            }
            None => return None
          }
      }
  }
  spend(b, source, names.length())
  // Empty tuples belong to row-cardinality evidence, not a fabricated field ID.
  if names.is_empty() {
    return None
  }
  let fields : Array[KeyField] = []
  let seen : Map[String, Bool] = Map([])
  let before = b.text
  for name in names {
    charge(b, source, name)
    let encoded = field_key(name)
    if !seen.contains(encoded) {
      seen[encoded] = true
      fields.push({ name, contract: @row.lookup(output, name), })
    }
  }
  Some({
    origin,
    producer: Some(RelationProducer(operation)),
    records,
    declared_records: records,
    declared_fields: fields,
    source,
    fields,
    aliases: fields.map(field => [field]),
    usage: { fields: fields.length(), name_bytes: before - b.text, },
  })
}

///|
/// Retains existing witnesses and adds keys established by the checked operation.
/// Operation provenance, not an input-declaration assertion, supports new keys.
pub fn advance_keys(
  previous : KeySet?,
  operation : @relation.CheckedOperation,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @relation.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let (records, witnesses) = match previous {
      Some(previous) => {
        let transfer = match transfer_keys(previous, operation, limits) {
          Ok(v) => v
          Err(e) => raise Stop(e)
        }
        b.work -= transfer.work
        b.text -= transfer.name_bytes
        (transfer.keys.records, transfer.keys.witnesses.copy())
      }
      None => {
        let output = @relation.output_schema(operation)
        spend(b, source, @row.field_count(output))
        (@carrier.typed_rows(output), [])
      }
    }
    if producer_key(operation, records, b) is Some(key) {
      witnesses.push(key)
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
