///|
pub fn key_asof_producer(key : KeyedRelation) -> CheckedAsOf? {
  match key.producer {
    Some(AsOfProducer(op, _)) => Some(op)
    _ => None
  }
}

///|
pub fn key_asof_parent(key : KeyedRelation) -> KeyedRelation? {
  match key.producer {
    Some(AsOfProducer(_, parent)) => parent
    _ => None
  }
}

///|
fn asof_witness(
  op : CheckedAsOf,
  mapped : KeyedRelation,
  parent : KeyedRelation?,
  name_bytes : Int,
) -> KeyedRelation {
  {
    ..mapped,
    origin: AsOfResult,
    producer: Some(AsOfProducer(op, parent)),
    declared_records: mapped.records,
    declared_fields: mapped.fields,
    source: op.source,
    usage: { fields: mapped.fields.length(), name_bytes, },
  }
}

///|
/// Each successful as-of emits at most one row per left occurrence. Only left
/// keys and the checked left identity can transfer; right-only keys cannot.
pub fn transfer_asof_keys(
  left : KeySet?,
  op : CheckedAsOf,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = op.source
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    if left is Some(keys) && !physical_equal(keys.records, op.left_records) {
      fail(source, InputContractMismatch)
    }
    let records = @carrier.typed_rows(op.output)
    let mapping = binary_projection_mapping(
      source,
      op.output,
      Some(op.projection),
      Left,
      b,
    )
    let witnesses : Array[KeyedRelation] = []
    let mut identity_covered = false
    if left is Some(keys) {
      let selected = match
        select_covered_key(source, keys, op.identity, {
          max_work: b.work,
          max_name_bytes: b.text,
        }) {
        Ok(v) => v
        Err(e) => raise Stop(e)
      }
      b.work -= selected.work
      b.text -= selected.name_bytes
      identity_covered = selected.key is Some(_)
      spend(b, source, keys.witnesses.length())
      for key in keys.witnesses {
        if mapped_key(key, mapping, records, source, b) is Some(mapped) {
          witnesses.push(
            asof_witness(op, mapped, Some(key), limits.max_name_bytes - b.text),
          )
        }
      }
    }
    if !identity_covered {
      let fields : Array[KeyField] = []
      spend(b, source, op.identity.length())
      for name in op.identity {
        charge(b, source, name)
        guard @carrier.lookup(op.left_records, name)
          is Present({ contract: Some(contract), .. }) else {
          fail(source, InputContractMismatch)
        }
        fields.push(plain_key_field(name, Some(contract)))
      }
      let identity : KeyedRelation = {
        origin: AsOfResult,
        producer: Some(AsOfProducer(op, None)),
        records: op.left_records,
        declared_records: op.left_records,
        declared_fields: fields,
        source,
        fields,
        aliases: fields.map(f => [f]),
        usage: {
          fields: fields.length(),
          name_bytes: limits.max_name_bytes - b.text,
        },
      }
      if mapped_key(identity, mapping, records, source, b) is Some(mapped) {
        witnesses.push(
          asof_witness(op, mapped, None, limits.max_name_bytes - b.text),
        )
      }
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
