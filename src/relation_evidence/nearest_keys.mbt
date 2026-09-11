///|
/// Retains exact semantic identity domains, not arbitrary object comparability.
pub fn nearest_keys(
  operation : CheckedNearest,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = nearest_source(nearest_pair_options(nearest_pair(operation)))
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    let records = @carrier.relation_rows(nearest_output(operation)).unwrap()
    let fields : Array[KeyField] = []
    let mut complete = true
    let sides : Array[(String, NearestSide)] = [
      ("query_id", Queries),
      ("candidate_id", Candidates),
    ]
    for (name, side) in sides {
      spend(b, source, 1)
      let name = @row.Unqualified(name)
      charge(b, source, name)
      let input = nearest_pair_input(nearest_pair(operation), side)
      match nearest_input_vectors(input) {
        Some(vectors) => {
          let contract = match @carrier.lookup(records, name) {
            Present(field) => field.contract
            _ => None
          }
          if contract is None {
            complete = false
          }
          fields.push({
            name,
            contract,
            positional_identity: if @carrier.vector_identity_count(vectors) > 1 {
              Some(vectors)
            } else {
              None
            },
          })
        }
        None => complete = false
      }
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    let witnesses : Array[KeyedRelation] = if complete {
      [
        {
          origin: NearestResult,
          producer: Some(NearestProducer(operation)),
          records,
          declared_records: records,
          declared_fields: fields,
          source,
          fields,
          aliases: fields.map(f => [f]),
          usage: { fields: 2, name_bytes, },
        },
      ]
    } else {
      []
    }
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn key_nearest_producer(key : KeyedRelation) -> CheckedNearest? {
  match key.producer {
    Some(NearestProducer(op)) => Some(op)
    _ => None
  }
}
