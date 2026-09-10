///|
pub(all) struct TransferLimits {
  max_work : Int
  max_name_bytes : Int
}

///|
pub struct Transfer {
  key : KeyedRelation?
  work : Int
  name_bytes : Int
}

///|
priv struct TransferBudget {
  mut work : Int
  mut text : Int
}

///|
fn spend(
  b : TransferBudget,
  source : @decode.Cursor,
  amount : Int,
) -> Unit raise Stop {
  if amount > b.work {
    fail(source, LimitExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : TransferBudget,
  source : @decode.Cursor,
  field : @row.FieldName,
) -> Unit raise Stop {
  let size = match
    @scalar.admit_utf8_length(@row.reference_name(field), b.text) {
    Ok(n) => n
    Err(_) => fail(source, LimitExceeded)
  }
  b.text -= size
}

///|
/// Transfers a conditional key through a checked unary operation on the exact
/// retained schema handle. Equal but unrelated schemas are not interchangeable.
/// Alternative aliases are retained per component, without a Cartesian product.
pub fn transfer_unary(
  previous : KeyedRelation,
  operation : @relation.CheckedOperation,
  limits : TransferLimits,
) -> Result[Transfer, Issue] {
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
    let mut preserved = true
    let mut aliases = previous.aliases
    match @relation.operation(operation) {
      Filter
      | Sort
      | Take
      | AssertRows
      | DedupeRows
      | TopK
      | TopKBy
      | Lag
      | WatermarkRows => ()
      Derive => {
        spend(b, source, @relation.binding_count(operation))
        let overwritten : Map[String, Bool] = Map([])
        for i in 0..<@relation.binding_count(operation) {
          if @relation.binding_at(operation, i).unwrap().name is Some(name) {
            overwritten[name] = true
          }
        }
        aliases = []
        spend(b, source, previous.aliases.length())
        for group in previous.aliases {
          spend(b, source, group.length())
          let remaining = group.filter(f => {
            match f.name {
              Unqualified(name) => !overwritten.contains(name)
              _ => true
            }
          })
          if remaining.is_empty() {
            preserved = false
          }
          aliases.push(remaining)
        }
      }
      Select | Rename | Drop | Distinct =>
        if @relation.row_operation(operation) is Some(DistinctRows) {
          ()
        } else {
          spend(b, source, previous.aliases.length())
          let components : Map[String, Int] = Map([])
          for i in 0..<previous.aliases.length() {
            let group = previous.aliases[i]
            spend(b, source, group.length())
            for field in group {
              charge(b, source, field.name)
              components[@row.reference_name(field.name)] = i
            }
          }
          aliases = previous.aliases.map(_ => [])
          let projection = @relation.projection(operation)
          spend(b, source, projection.length())
          let output = @relation.output_schema(operation)
          for p in projection {
            if components.get(@row.reference_name(p.input)) is Some(i) {
              charge(b, source, p.output)
              aliases[i].push({
                name: p.output,
                contract: @row.lookup(output, p.output),
              })
            }
          }
          for group in aliases {
            if group.is_empty() {
              preserved = false
            }
          }
        }
      _ => preserved = false
    }
    let key = if preserved {
      let output = @relation.output_schema(operation)
      spend(b, source, @row.field_count(output))
      spend(b, source, aliases.length())
      Some({
        records: @carrier.typed_rows(output),
        declared_records: previous.declared_records,
        declared_fields: previous.declared_fields,
        source: previous.source,
        fields: aliases.map(a => a[0]),
        aliases,
        usage: previous.usage,
      })
    } else {
      None
    }
    Ok({
      key,
      work: limits.max_work - b.work,
      name_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
