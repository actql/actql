///|
fn scalar_key(field : @evidence.KeyField) -> Bool {
  guard field.contract is Some(c) &&
    !c.nullable &&
    field.positional_identity is None else {
    return false
  }
  match c.shape {
    @contract.Text(_) | Number | Boolean | Decimal(..) | Date | Timestamp =>
      true
    _ => false
  }
}

///|
fn same_records(a : @carrier.Knowledge, b : @carrier.Knowledge) -> Bool {
  if physical_equal(a, b) {
    return true
  }
  match (@carrier.complete_schema(a), @carrier.complete_schema(b)) {
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn read_key(
  b : Budget,
  source : @decode.Cursor,
  schema : @schema.Schema,
) -> Array[KeyBinding] raise Stop {
  let count = match @decode.view(source) {
    TextValue(_) => 1
    ArrayValue(_) => {
      let count = @decode.array_length(source).unwrap()
      if count < 2 {
        fail(source, InvalidKeyTuple)
      }
      count
    }
    _ => fail(source, InvalidKeyTuple)
  }
  if count > b.limits.max_key_fields {
    fail(source, BudgetExceeded)
  }
  spend(b, source, count~)
  let fields : Array[KeyBinding] = []
  let seen : Map[String, Bool] = Map([])
  for i in 0..<count {
    let item = if count == 1 {
      source
    } else {
      @decode.element_at(source, i).unwrap()
    }
    let name = decoded(item, @decode.text(item))
    charge(b, item, name)
    if seen.contains(name) {
      fail(item, InvalidKeyTuple)
    }
    seen[name] = true
    if name == "outcome" || name == "value" {
      fail(item, KeyRoleCollision(name))
    }
    let field = match @schema.lookup_reference(schema, name) {
      Some(field) => field
      None => fail(item, UnknownKeyField(name))
    }
    let c = field.contract
    if c.nullable ||
      !(c.shape is @contract.Text(_) ||
      c.shape is Number ||
      c.shape is Boolean ||
      c.shape is Decimal(..) ||
      c.shape is Date ||
      c.shape is Timestamp) {
      fail(item, InvalidKeyType(name))
    }
    fields.push({ field: field.name, contract: c, })
  }
  fields
}

///|
/// Exact tuple equality, not covered-key selection or an alias cross product.
fn matches_key(
  b : Budget,
  source : @decode.Cursor,
  witness : @evidence.KeyedRelation,
  fields : Array[KeyBinding],
) -> Bool raise Stop {
  let count = @evidence.key_field_count(witness)
  if count != fields.length() {
    return false
  }
  spend(b, source, count~)
  let used = Array::make(count, false)
  for field in fields {
    let mut found = false
    for component in 0..<count {
      spend(b, source)
      if !used[component] {
        for alias_index in 0..<@evidence.key_alias_count(witness, component) {
          spend(b, source)
          let candidate = @evidence.key_alias_at(
            witness, component, alias_index,
          ).unwrap()
          charge(b, source, @schema.reference_name(candidate.name))
          if candidate.name == field.field && scalar_key(candidate) {
            used[component] = true
            found = true
            break
          }
        }
      }
      if found {
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn same_tuple(
  b : Budget,
  source : @decode.Cursor,
  a : Array[KeyBinding],
  c : Array[KeyBinding],
) -> Bool raise Stop {
  if a.length() != c.length() {
    return false
  }
  for field in a {
    let mut found = false
    for candidate in c {
      spend(b, source)
      charge(b, source, @schema.reference_name(field.field))
      charge(b, source, @schema.reference_name(candidate.field))
      if field.field == candidate.field {
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn resolve_key(
  b : Budget,
  source : @decode.Cursor,
  authored : @decode.Cursor?,
  records : @carrier.Knowledge,
  schema : @schema.Schema,
  keys : @evidence.KeySet?,
) -> (@evidence.KeyedRelation, Array[KeyBinding]) raise Stop {
  let keys = match keys {
    Some(keys) => keys
    None => fail(source, CandidateKeyRequired)
  }
  if !same_records(records, @evidence.key_set_records(keys)) {
    fail(source, InputKeyOwnerMismatch)
  }
  if authored is Some(authored) {
    let fields = read_key(b, authored, schema)
    for i in 0..<@evidence.key_witness_count(keys) {
      spend(b, source)
      let witness = @evidence.key_witness_at(keys, i).unwrap()
      if matches_key(b, source, witness, fields) {
        return (witness, fields)
      }
    }
    fail(authored, CandidateKeyRequired)
  } else {
    let mut chosen : (@evidence.KeyedRelation, Array[KeyBinding])? = None
    for i in 0..<@evidence.key_witness_count(keys) {
      spend(b, source)
      let witness = @evidence.key_witness_at(keys, i).unwrap()
      let count = @evidence.key_field_count(witness)
      if count > b.limits.max_key_fields {
        fail(source, BudgetExceeded)
      }
      spend(b, source, count~)
      let fields : Array[KeyBinding] = []
      let mut multiple = false
      for component in 0..<count {
        let mut selected : @evidence.KeyField? = None
        for alias_index in 0..<@evidence.key_alias_count(witness, component) {
          spend(b, source)
          let candidate = @evidence.key_alias_at(
            witness, component, alias_index,
          ).unwrap()
          charge(b, source, @schema.reference_name(candidate.name))
          if scalar_key(candidate) {
            match selected {
              Some(prior) => if prior.name != candidate.name { multiple = true }
              None => selected = Some(candidate)
            }
          }
        }
        if selected is Some(field) {
          fields.push({ field: field.name, contract: field.contract.unwrap(), })
        }
      }
      if count == 0 || fields.length() != count {
        continue
      }
      if multiple {
        fail(source, AmbiguousCandidateKey)
      }
      for field in fields {
        let name = @schema.reference_name(field.field)
        if name == "outcome" || name == "value" {
          fail(source, KeyRoleCollision(name))
        }
      }
      match chosen {
        None => chosen = Some((witness, fields))
        Some((_, prior)) =>
          if !same_tuple(b, source, prior, fields) {
            fail(source, AmbiguousCandidateKey)
          }
      }
    }
    match chosen {
      Some(value) => value
      None => fail(source, CandidateKeyRequired)
    }
  }
}
