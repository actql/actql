///|
pub fn key_append_producer(key : KeyedRelation) -> @append.CheckedAppend? {
  match key.producer {
    Some(AppendProducer(op, _, _, _, _, _)) => Some(op)
    _ => None
  }
}

///|
pub fn key_append_input(
  key : KeyedRelation,
  side : @row.Side,
) -> KeyedRelation? {
  match key.producer {
    Some(AppendProducer(_, left, right, _, _, _)) =>
      Some(if side == Left { left } else { right })
    _ => None
  }
}

///|
pub fn key_append_domain(
  key : KeyedRelation,
  side : @row.Side,
) -> LiteralDomain? {
  match key.producer {
    Some(AppendProducer(_, _, _, _, left, right)) =>
      Some(if side == Left { left } else { right })
    _ => None
  }
}

///|
pub fn key_append_discriminator(key : KeyedRelation) -> @row.FieldName? {
  match key.producer {
    Some(AppendProducer(_, _, _, field, _, _)) => Some(field)
    _ => None
  }
}

///|
fn disjoint_domains(
  b : TransferBudget,
  source : @decode.Cursor,
  left : LiteralDomain,
  right : LiteralDomain,
) -> Bool raise Stop {
  for l in left.values {
    literal_charge(b, source, l)
    for r in right.values {
      literal_charge(b, source, r)
      if l == r {
        return false
      }
    }
  }
  true
}

///|
fn residual_components(
  b : TransferBudget,
  source : @decode.Cursor,
  key : KeyedRelation,
  discriminator : @row.FieldName,
) -> Array[Array[KeyField]] raise Stop {
  spend(b, source, key.aliases.length())
  let groups = []
  for aliases in key.aliases {
    let mut covered = false
    spend(b, source, aliases.length())
    for component in aliases {
      charge(b, source, component.name)
      if component.name == discriminator {
        covered = true
      }
    }
    if !covered {
      groups.push(aliases)
    }
  }
  groups
}

///|
priv struct AppendMatching {
  used : Array[Bool]
  groups : Array[Array[KeyField]]
}

///|
fn append_pair(
  b : TransferBudget,
  op : @append.CheckedAppend,
  records : @carrier.Knowledge,
  left : KeyedRelation,
  right : KeyedRelation,
  discriminator : @row.FieldName,
  ld : LiteralDomain,
  rd : LiteralDomain,
  output : Array[KeyedRelation],
) -> Unit raise Stop {
  let source = @append.source(op)
  let ls = residual_components(b, source, left, discriminator)
  let rs = residual_components(b, source, right, discriminator)
  if ls.length() != rs.length() {
    return
  }
  spend(b, source, rs.length())
  let names : Map[String, (Int, KeyField)] = Map([])
  for i in 0..<rs.length() {
    spend(b, source, rs[i].length())
    for field in rs[i] {
      charge(b, source, field.name)
      names[field_key(field.name)] = (i, field)
    }
  }
  let schema = @append.output_schema(op)
  let adjacency : Array[Array[(Int, Array[KeyField])]] = []
  spend(b, source, ls.length())
  for group in ls {
    let matches : Map[Int, Array[KeyField]] = Map([])
    let choices : Array[(Int, Array[KeyField])] = []
    spend(b, source, group.length())
    for field in group {
      charge(b, source, field.name)
      if names.get(field_key(field.name)) is Some((i, r)) {
        let aliases = match matches.get(i) {
          Some(v) => v
          None => {
            let v = []
            matches[i] = v
            choices.push((i, v))
            v
          }
        }
        let c = @row.lookup(schema, field.name).unwrap()
        let nullable = field.contract.map(c => c.nullable).unwrap_or(true) ||
          r.contract.map(c => c.nullable).unwrap_or(true)
        aliases.push(
          plain_key_field(
            field.name,
            Some(@contract.with_nullability(c, nullable)),
          ),
        )
      }
    }
    if choices.is_empty() {
      return
    }
    adjacency.push(choices)
  }
  spend(b, source, rs.length() + 1)
  let stack : Array[AppendMatching] = [
    { used: Array::make(rs.length(), false), groups: [], },
  ]
  while stack.pop() is Some(state) {
    spend(b, source, 1)
    if state.groups.length() == adjacency.length() {
      spend(b, source, state.groups.length() + 2)
      let before = b.text
      charge(b, source, discriminator)
      let c = @row.lookup(schema, discriminator).unwrap()
      let field = plain_key_field(
        discriminator,
        Some(@contract.with_nullability(c, false)),
      )
      let aliases = [[field]]
      for group in state.groups {
        charge(b, source, group[0].name)
        aliases.push(group)
      }
      let fields = aliases.map(group => group[0])
      output.push({
        origin: AppendResult,
        producer: Some(AppendProducer(op, left, right, discriminator, ld, rd)),
        records,
        declared_records: records,
        declared_fields: fields,
        source,
        fields,
        aliases,
        usage: { fields: fields.length(), name_bytes: before - b.text, },
      })
    } else {
      for (index, aliases) in adjacency[state.groups.length()] {
        spend(b, source, 1)
        if !state.used[index] {
          spend(b, source, state.used.length() + state.groups.length() + 1)
          let used = state.used.copy()
          used[index] = true
          let groups = state.groups.copy()
          groups.push(aliases)
          stack.push({ used, groups, })
        }
      }
    }
  }
}

///|
pub fn append_keys(
  left : KeySet?,
  right : KeySet?,
  ld : LiteralDomains?,
  rd : LiteralDomains?,
  op : @append.CheckedAppend,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @append.source(op)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    for
      (side, keys, domains) in [(@row.Left, left, ld), (@row.Right, right, rd)] {
      if keys is Some(keys) {
        guard @carrier.complete_schema(keys.records) is Some(s) &&
          physical_equal(s, @append.input_schema(op, side)) else {
          fail(source, InputContractMismatch)
        }
      }
      if domains is Some(d) &&
        !physical_equal(d.schema, @append.input_schema(op, side)) {
        fail(source, InputContractMismatch)
      }
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let schema = @append.output_schema(op)
    let records = @carrier.typed_rows(schema)
    let witnesses = []
    spend(b, source, @row.field_count(schema))
    if left is Some(left) &&
      right is Some(right) &&
      ld is Some(ld) &&
      rd is Some(rd) {
      for i in 0..<@row.field_count(schema) {
        let name = @row.field_at(schema, i).unwrap().name
        charge(b, source, name)
        if literal_domain(ld, name) is Some(l) &&
          literal_domain(rd, name) is Some(r) &&
          disjoint_domains(b, source, l, r) {
          for lk in left.witnesses {
            spend(b, source, 1)
            for rk in right.witnesses {
              spend(b, source, 1)
              append_pair(b, op, records, lk, rk, name, l, r, witnesses)
            }
          }
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
