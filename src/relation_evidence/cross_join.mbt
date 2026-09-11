///|
pub fn key_cross_join_producer(key : KeyedRelation) -> @join.CheckedCrossJoin? {
  match key.producer {
    Some(CrossJoinProducer(op, _)) => Some(op)
    _ => None
  }
}

///|
pub fn key_cross_join_dependency_count(key : KeyedRelation) -> Int {
  match key.producer {
    Some(CrossJoinProducer(_, parents)) => parents.length()
    _ => 0
  }
}

///|
pub fn key_cross_join_dependency_at(
  key : KeyedRelation,
  index : Int,
) -> KeyedRelation? {
  match key.producer {
    Some(CrossJoinProducer(_, parents)) => parents.get(index).map(p => p.1)
    _ => None
  }
}

///|
pub fn key_cross_join_dependency_side(
  key : KeyedRelation,
  index : Int,
) -> @row.Side? {
  match key.producer {
    Some(CrossJoinProducer(_, parents)) => parents.get(index).map(p => p.0)
    _ => None
  }
}

///|
fn cross_witness(
  op : @join.CheckedCrossJoin,
  mapped : KeyedRelation,
  parents : Array[(@row.Side, KeyedRelation)],
  name_bytes : Int,
) -> KeyedRelation {
  {
    ..mapped,
    origin: CrossJoinResult,
    producer: Some(CrossJoinProducer(op, parents)),
    declared_records: mapped.records,
    declared_fields: mapped.fields,
    source: @join.cross_source(op),
    usage: { fields: mapped.fields.length(), name_bytes, },
  }
}

///|
pub fn transfer_cross_join_keys(
  left : KeySet?,
  right : KeySet?,
  op : @join.CheckedCrossJoin,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @join.cross_source(op)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    for (side, keys) in [(@row.Left, left), (@row.Right, right)] {
      if keys is Some(keys) {
        guard @carrier.complete_schema(keys.records) is Some(schema) &&
          physical_equal(schema, @join.cross_input_schema(op, side)) else {
          fail(source, InputContractMismatch)
        }
      }
    }
    let output = @join.cross_output_schema(op)
    let records = @carrier.typed_rows(output)
    let projection = @join.cross_projection(op)
    let lm = binary_projection_mapping(source, output, projection, Left, b)
    let rm = binary_projection_mapping(source, output, projection, Right, b)
    let ls = match left {
      Some(k) => k.witnesses
      None => []
    }
    let rs = match right {
      Some(k) => k.witnesses
      None => []
    }
    let mapped_left : Array[(KeyedRelation, KeyedRelation)] = []
    let mapped_right : Array[(KeyedRelation, KeyedRelation)] = []
    let witnesses : Array[KeyedRelation] = []
    spend(b, source, ls.length())
    spend(b, source, rs.length())
    for key in ls {
      if mapped_key(key, lm, records, source, b) is Some(mapped) {
        mapped_left.push((key, mapped))
        if @join.cross_requires_one_right_row(op) {
          witnesses.push(
            cross_witness(
              op,
              mapped,
              [(Left, key)],
              limits.max_name_bytes - b.text,
            ),
          )
        }
      }
    }
    for key in rs {
      if mapped_key(key, rm, records, source, b) is Some(mapped) {
        mapped_right.push((key, mapped))
      }
    }
    for (lp, l) in mapped_left {
      for (rp, r) in mapped_right {
        spend(b, source, 1)
        spend(b, source, l.fields.length() + r.fields.length())
        let fields = l.fields.copy()
        for f in r.fields {
          fields.push(f)
        }
        let aliases = l.aliases.copy()
        for a in r.aliases {
          aliases.push(a)
        }
        witnesses.push(
          cross_witness(
            op,
            { ..l, fields, aliases, },
            [(Left, lp), (Right, rp)],
            limits.max_name_bytes - b.text,
          ),
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
