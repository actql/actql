///|
pub fn key_join_producer(key : KeyedRelation) -> @join.CheckedJoin? {
  match key.producer {
    Some(JoinProducer(op, _)) => Some(op)
    _ => None
  }
}

///|
pub fn key_join_dependency_count(key : KeyedRelation) -> Int {
  match key.producer {
    Some(JoinProducer(_, parents)) => parents.length()
    _ => 0
  }
}

///|
pub fn key_join_dependency_at(
  key : KeyedRelation,
  index : Int,
) -> KeyedRelation? {
  match key.producer {
    Some(JoinProducer(_, parents)) => parents.get(index).map(p => p.1)
    _ => None
  }
}

///|
pub fn key_join_dependency_side(key : KeyedRelation, index : Int) -> @row.Side? {
  match key.producer {
    Some(JoinProducer(_, parents)) => parents.get(index).map(p => p.0)
    _ => None
  }
}

///|
fn join_covered(
  op : MatchedJoin,
  side : @row.Side,
  keys : KeySet?,
  b : TransferBudget,
) -> KeyedRelation? raise Stop {
  guard keys is Some(keys) else { return None }
  let source = matched_source(op)
  let n = matched_key_count(op)
  spend(b, source, n)
  let names = Array::makei(n, i => {
    let pair = matched_key_at(op, i).unwrap()
    if side == Left {
      pair.left
    } else {
      pair.right
    }
  })
  let result = match
    select_covered_key(source, keys, names, {
      max_work: b.work,
      max_name_bytes: b.text,
    }) {
    Ok(result) => result
    Err(e) => raise Stop(e)
  }
  b.work -= result.work
  b.text -= result.name_bytes
  result.key
}

///|
fn join_mapping(
  op : MatchedJoin,
  side : @row.Side,
  b : TransferBudget,
) -> KeyMapping raise Stop {
  binary_projection_mapping(
    matched_source(op),
    matched_output_schema(op),
    matched_projection(op),
    side,
    b,
  )
}

///|
fn binary_projection_mapping(
  source : @decode.Cursor,
  output : @row.Schema,
  projection : Array[@join.Projection]?,
  side : @row.Side,
  b : TransferBudget,
) -> KeyMapping raise Stop {
  let names : Map[String, Array[KeyField]] = Map([])
  let n = match projection {
    Some(p) => p.length()
    None => @row.field_count(output)
  }
  spend(b, source, n)
  for i in 0..<n {
    let (input, name) = match projection {
      Some(p) => (p[i].input, p[i].output)
      None => {
        let name = @row.field_at(output, i).unwrap().name
        (name, name)
      }
    }
    if input is Qualified(s, field) && s == side {
      charge(b, source, input)
      charge(b, source, name)
      let k = field_key(Unqualified(field))
      let entries = match names.get(k) {
        Some(v) => v
        None => {
          let v = []
          names[k] = v
          v
        }
      }
      entries.push({ name, contract: @row.lookup(output, name), })
    }
  }
  Project(names)
}

///|
fn join_mapped(
  key : KeyedRelation,
  mapping : KeyMapping,
  records : @carrier.Knowledge,
  nullable : Bool,
  source : @decode.Cursor,
  b : TransferBudget,
) -> KeyedRelation? raise Stop {
  // Exact-copy transfer must not restore a non-null fact on a null-extended side.
  let key = if nullable {
    spend(b, source, key.aliases.length())
    let aliases = key.aliases.map(group => {
      spend(b, source, group.length())
      group.map(f => {
        ..f,
        contract: f.contract.map(c => @contract.with_nullability(c, true)),
      })
    })
    { ..key, aliases, }
  } else {
    key
  }
  mapped_key(key, mapping, records, source, b)
}

///|
fn join_witness(
  op : MatchedJoin,
  mapped : KeyedRelation,
  parents : Array[(@row.Side, KeyedRelation)],
  name_bytes : Int,
) -> KeyedRelation {
  {
    ..mapped,
    origin: match op {
      Equality(_) => JoinResult
      Temporal(_) => IntervalJoinResult
    },
    producer: Some(
      match op {
        Equality(v) => JoinProducer(v, parents)
        Temporal(v) => IntervalJoinProducer(v, parents)
      },
    ),
    declared_records: mapped.records,
    declared_fields: mapped.fields,
    source: matched_source(op),
    usage: { fields: mapped.fields.length(), name_bytes, },
  }
}

///|
fn nonnull_component(
  key : KeyedRelation,
  b : TransferBudget,
  source : @decode.Cursor,
) -> Bool raise Stop {
  spend(b, source, key.fields.length())
  key.fields.any(f => f.contract is Some(c) && !c.nullable)
}

///|
/// Conditional join-output keys; original producers and cardinality assertions
/// remain validation dependencies. Every supplied input is bound by identity.
fn transfer_matched_keys(
  left : KeySet?,
  right : KeySet?,
  op : MatchedJoin,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = matched_source(op)
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
          physical_equal(schema, matched_input_schema(op, side)) else {
          fail(source, InputContractMismatch)
        }
      }
    }
    let lcovered = join_covered(op, Left, left, b)
    let rcovered = join_covered(op, Right, right, b)
    let assertion = matched_assertion(op)
    let lu = lcovered is Some(_) || assertion is Some(OneToOne | OneToMany)
    let ru = rcovered is Some(_) || assertion is Some(OneToOne | ManyToOne)
    let kind = matched_kind(op)
    let records = @carrier.typed_rows(matched_output_schema(op))
    let lm = join_mapping(op, Left, b)
    let rm = join_mapping(op, Right, b)
    let ls = match left {
      Some(k) => k.witnesses
      None => []
    }
    let rs = match right {
      Some(k) => k.witnesses
      None => []
    }
    let witnesses : Array[KeyedRelation] = []
    let mapped_left : Array[(KeyedRelation, KeyedRelation)] = []
    let mapped_right : Array[(KeyedRelation, KeyedRelation)] = []
    spend(b, source, ls.length())
    spend(b, source, rs.length())
    for key in ls {
      if join_mapped(key, lm, records, kind == Full, source, b) is Some(mapped) {
        mapped_left.push((key, mapped))
        if kind == Semi ||
          kind == Anti ||
          ((kind == Inner || kind == Left) && ru) {
          let parents = [(@row.Left, key)]
          if (kind == Inner || kind == Left) && rcovered is Some(other) {
            parents.push((Right, other))
          }
          witnesses.push(
            join_witness(op, mapped, parents, limits.max_name_bytes - b.text),
          )
        }
      }
    }
    for key in rs {
      if join_mapped(key, rm, records, kind == Full || kind == Left, source, b)
        is Some(mapped) {
        mapped_right.push((key, mapped))
        if kind == Inner && lu {
          let parents = [(@row.Right, key)]
          if lcovered is Some(other) {
            parents.push((Left, other))
          }
          witnesses.push(
            join_witness(op, mapped, parents, limits.max_name_bytes - b.text),
          )
        }
      }
    }
    if kind == Inner || kind == Left || kind == Full {
      for (lp, l) in mapped_left {
        for (rp, r) in mapped_right {
          spend(b, source, 1)
          // Full-join unmatched rows from opposite sides must not collapse to
          // the same all-null tuple. A known non-null component on each side
          // distinguishes both missing-side sentinels.
          if kind == Full &&
            (
              !nonnull_component(lp, b, source) ||
              !nonnull_component(rp, b, source)
            ) {
            continue
          }
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
            join_witness(
              op,
              { ..l, fields, aliases, },
              [(Left, lp), (Right, rp)],
              limits.max_name_bytes - b.text,
            ),
          )
        }
      }
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
