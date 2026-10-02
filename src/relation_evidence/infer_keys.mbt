///|
fn infer_scalar_key(field : KeyField) -> Bool {
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
fn infer_same_records(a : @carrier.Knowledge, b : @carrier.Knowledge) -> Bool {
  if physical_equal(a, b) {
    return true
  }
  match (@carrier.complete_schema(a), @carrier.complete_schema(b)) {
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
fn infer_read_key(
  b : InferBudget,
  source : @decode.Cursor,
  schema : @row.Schema,
) -> Array[InferKeyBinding] raise InferStop {
  let count = match @decode.view(source) {
    TextValue(_) => 1
    ArrayValue(_) => {
      let count = @decode.array_length(source).unwrap()
      if count < 2 {
        infer_fail(source, InvalidKeyTuple)
      }
      count
    }
    _ => infer_fail(source, InvalidKeyTuple)
  }
  if count > b.limits.max_key_fields {
    infer_fail(source, BudgetExceeded)
  }
  infer_spend(b, source, count~)
  let fields : Array[InferKeyBinding] = []
  let seen : Map[String, Bool] = Map([])
  for i in 0..<count {
    let item = if count == 1 {
      source
    } else {
      @decode.element_at(source, i).unwrap()
    }
    let name = infer_decoded(item, @decode.text(item))
    infer_charge(b, item, name)
    if seen.contains(name) {
      infer_fail(item, InvalidKeyTuple)
    }
    seen[name] = true
    if name == "outcome" || name == "value" {
      infer_fail(item, KeyRoleCollision(name))
    }
    let field = match @row.lookup_reference(schema, name) {
      Some(field) => field
      None => infer_fail(item, UnknownKeyField(name))
    }
    let c = field.contract
    if c.nullable ||
      !(c.shape is @contract.Text(_) ||
      c.shape is Number ||
      c.shape is Boolean ||
      c.shape is Decimal(..) ||
      c.shape is Date ||
      c.shape is Timestamp) {
      infer_fail(item, InvalidKeyType(name))
    }
    fields.push({ field: field.name, contract: c, })
  }
  fields
}

///|
/// Exact tuple equality, not covered-key selection or an alias cross product.
fn infer_matches_key(
  b : InferBudget,
  source : @decode.Cursor,
  witness : KeyedRelation,
  fields : Array[InferKeyBinding],
) -> Bool raise InferStop {
  let count = key_field_count(witness)
  if count != fields.length() {
    return false
  }
  infer_spend(b, source, count~)
  let used = Array::make(count, false)
  for field in fields {
    let mut found = false
    for component in 0..<count {
      infer_spend(b, source)
      if !used[component] {
        for alias_index in 0..<key_alias_count(witness, component) {
          infer_spend(b, source)
          let candidate = key_alias_at(witness, component, alias_index).unwrap()
          infer_charge(b, source, @row.reference_name(candidate.name))
          if candidate.name == field.field && infer_scalar_key(candidate) {
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
fn infer_same_tuple(
  b : InferBudget,
  source : @decode.Cursor,
  a : Array[InferKeyBinding],
  c : Array[InferKeyBinding],
) -> Bool raise InferStop {
  if a.length() != c.length() {
    return false
  }
  for field in a {
    let mut found = false
    for candidate in c {
      infer_spend(b, source)
      infer_charge(b, source, @row.reference_name(field.field))
      infer_charge(b, source, @row.reference_name(candidate.field))
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
fn infer_resolve_key(
  b : InferBudget,
  source : @decode.Cursor,
  authored : @decode.Cursor?,
  records : @carrier.Knowledge,
  schema : @row.Schema,
  keys : KeySet?,
) -> (KeyedRelation, Array[InferKeyBinding]) raise InferStop {
  let keys = match keys {
    Some(keys) => keys
    None => infer_fail(source, CandidateKeyRequired)
  }
  if !infer_same_records(records, key_set_records(keys)) {
    infer_fail(source, InputKeyOwnerMismatch)
  }
  if authored is Some(authored) {
    let fields = infer_read_key(b, authored, schema)
    for i in 0..<key_witness_count(keys) {
      infer_spend(b, source)
      let witness = key_witness_at(keys, i).unwrap()
      if infer_matches_key(b, source, witness, fields) {
        return (witness, fields)
      }
    }
    infer_fail(authored, CandidateKeyRequired)
  } else {
    let mut chosen : (KeyedRelation, Array[InferKeyBinding])? = None
    for i in 0..<key_witness_count(keys) {
      infer_spend(b, source)
      let witness = key_witness_at(keys, i).unwrap()
      let count = key_field_count(witness)
      if count > b.limits.max_key_fields {
        infer_fail(source, BudgetExceeded)
      }
      infer_spend(b, source, count~)
      let fields : Array[InferKeyBinding] = []
      let mut multiple = false
      for component in 0..<count {
        let mut selected : KeyField? = None
        for alias_index in 0..<key_alias_count(witness, component) {
          infer_spend(b, source)
          let candidate = key_alias_at(witness, component, alias_index).unwrap()
          infer_charge(b, source, @row.reference_name(candidate.name))
          if infer_scalar_key(candidate) {
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
        infer_fail(source, AmbiguousCandidateKey)
      }
      for field in fields {
        let name = @row.reference_name(field.field)
        if name == "outcome" || name == "value" {
          infer_fail(source, KeyRoleCollision(name))
        }
      }
      match chosen {
        None => chosen = Some((witness, fields))
        Some((_, prior)) =>
          if !infer_same_tuple(b, source, prior, fields) {
            infer_fail(source, AmbiguousCandidateKey)
          }
      }
    }
    match chosen {
      Some(value) => value
      None => infer_fail(source, CandidateKeyRequired)
    }
  }
}
