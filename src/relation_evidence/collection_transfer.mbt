///|
pub struct KeySetTransfer {
  keys : KeySet
  work : Int
  name_bytes : Int
}

///|
priv enum KeyMapping {
  Keep
  Project(Map[String, Array[KeyField]])
  Forget
}

///|
fn field_key(field : @row.FieldName) -> String {
  match field {
    Unqualified(name) => "u:" + name
    Qualified(Left, name) => "l:" + name
    Qualified(Right, name) => "r:" + name
  }
}

///|
fn prepare_mapping(
  operation : @relation.CheckedOperation,
  b : TransferBudget,
) -> KeyMapping raise Stop {
  let source = @relation.source(operation)
  match @relation.operation(operation) {
    Filter
    | Sort
    | Take
    | AssertRows
    | DedupeRows
    | TopK
    | TopKBy
    | Lag
    | Analytic
    | JsonPick
    | WatermarkRows => Keep
    Derive => {
      spend(b, source, @relation.binding_count(operation))
      let origins : Array[@row.FieldName?] = []
      let outputs : Map[String, @row.FieldName?] = Map([])
      for i in 0..<@relation.binding_count(operation) {
        let binding = @relation.binding_copy_at(operation, i).unwrap()
        let origin = match binding.input {
          Some(InputField(field)) => Some(field)
          Some(PriorSlot(slot)) => origins[slot]
          None => None
        }
        origins.push(origin)
        if binding.output is Some(name) {
          charge(b, source, Unqualified(name))
          outputs[field_key(Unqualified(name))] = origin
        }
      }
      let output = @relation.output_schema(operation)
      spend(b, source, @row.field_count(output))
      let mapping : Map[String, Array[KeyField]] = Map([])
      for i in 0..<@row.field_count(output) {
        let field = @row.field_at(output, i).unwrap()
        charge(b, source, field.name)
        let origin = match outputs.get(field_key(field.name)) {
          Some(origin) => origin
          None => Some(field.name)
        }
        if origin is Some(origin) {
          charge(b, source, origin)
          let key = field_key(origin)
          let entries = match mapping.get(key) {
            Some(entries) => entries
            None => {
              let entries = []
              mapping[key] = entries
              entries
            }
          }
          entries.push({ name: field.name, contract: Some(field.contract), })
        }
      }
      Project(mapping)
    }
    Select | Rename | Drop | Distinct => {
      if @relation.row_operation(operation) is Some(DistinctRows) {
        return Keep
      }
      let projection = @relation.projection(operation)
      spend(b, source, projection.length())
      let mapping : Map[String, Array[KeyField]] = Map([])
      let output = @relation.output_schema(operation)
      for p in projection {
        charge(b, source, p.input)
        charge(b, source, p.output)
        let key = field_key(p.input)
        let entries = match mapping.get(key) {
          Some(v) => v
          None => {
            let v = []
            mapping[key] = v
            v
          }
        }
        entries.push({
          name: p.output,
          contract: @row.lookup(output, p.output),
        })
      }
      Project(mapping)
    }
    _ => Forget
  }
}

///|
fn mapped_key(
  previous : KeyedRelation,
  mapping : KeyMapping,
  records : @carrier.Knowledge,
  source : @decode.Cursor,
  b : TransferBudget,
) -> KeyedRelation? raise Stop {
  if mapping is Forget {
    return None
  }
  let aliases : Array[Array[KeyField]] = []
  spend(b, source, previous.aliases.length())
  let mut valid = true
  for group in previous.aliases {
    let remaining : Array[KeyField] = []
    spend(b, source, group.length())
    for field in group {
      charge(b, source, field.name)
      match mapping {
        Keep => remaining.push(field)
        Project(names) =>
          if names.get(field_key(field.name)) is Some(mapped) {
            spend(b, source, mapped.length())
            for output in mapped {
              charge(b, source, output.name)
              // The mapping only admits exact copies. A wider row schema does
              // not erase the non-null fact attached to a retained key value.
              let contract = match (field.contract, output.contract) {
                (Some(input), Some(result)) =>
                  Some(
                    @contract.with_nullability(
                      result,
                      input.nullable && result.nullable,
                    ),
                  )
                (Some(input), None) => Some(input)
                (None, result) => result
              }
              remaining.push({ name: output.name, contract, })
            }
          }
        Forget => ()
      }
    }
    if remaining.is_empty() {
      valid = false
    }
    aliases.push(remaining)
  }
  if !valid {
    return None
  }
  Some({ ..previous, records, aliases, fields: aliases.map(group => group[0]), })
}

///|
/// Transfers all witnesses using one prepared mapping and one output contract.
/// Losing a component removes only that witness, not other independent keys.
pub fn transfer_keys(
  previous : KeySet,
  operation : @relation.CheckedOperation,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @relation.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @carrier.complete_schema(previous.records) is Some(input) &&
      physical_equal(input, @relation.input_schema(operation)) else {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, previous.witnesses.length())
    let mapping = prepare_mapping(operation, b)
    let output = @relation.output_schema(operation)
    spend(b, source, @row.field_count(output))
    let records = @carrier.typed_rows(output)
    let witnesses : Array[KeyedRelation] = []
    for key in previous.witnesses {
      if mapped_key(key, mapping, records, source, b) is Some(next) {
        witnesses.push(next)
      }
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
