///|
pub fn key_unpivot_input(key : KeyedRelation) -> KeyedRelation? {
  match key.producer {
    Some(UnpivotProducer(_, parent)) => Some(parent)
    _ => None
  }
}

///|
fn unpivot_mapping(
  operation : @relation.CheckedOperation,
  b : TransferBudget,
) -> KeyMapping raise Stop {
  let source = @relation.source(operation)
  let count = @relation.unpivot_columns_count(operation)
  spend(b, source, count)
  let sources : Map[String, Bool] = Map([])
  let labels : Map[String, Bool] = Map([])
  for i in 0..<count {
    let field = @relation.unpivot_column_at(operation, i).unwrap().field
    charge(b, source, field)
    let key = field_key(field)
    let label = @row.reference_name(field)
    if sources.contains(key) || labels.contains(label) {
      return Forget
    }
    sources[key] = true
    labels[label] = true
  }
  if count == 0 {
    return Forget
  }
  let mapping : Map[String, Array[KeyField]] = Map([])
  spend(b, source, @relation.unpivot_keep_count(operation))
  let output = @relation.output_schema(operation)
  for i in 0..<@relation.unpivot_keep_count(operation) {
    let field = @relation.unpivot_keep_at(operation, i).unwrap().field
    charge(b, source, field)
    mapping[field_key(field)] = [
      plain_key_field(field, @row.lookup(output, field)),
    ]
  }
  Project(mapping)
}

///|
fn unpivot_key(
  operation : @relation.CheckedOperation,
  parent : KeyedRelation,
  mapped : KeyedRelation,
  b : TransferBudget,
) -> KeyedRelation raise Stop {
  let source = @relation.source(operation)
  let (name, _) = @relation.unpivot_outputs(operation).unwrap()
  let field = @row.Unqualified(name)
  let before = b.text
  charge(b, source, field)
  spend(b, source, mapped.fields.length() + mapped.aliases.length() + 1)
  let component = plain_key_field(
    field,
    @row.lookup(@relation.output_schema(operation), field),
  )
  let fields = mapped.fields.copy()
  fields.push(component)
  let aliases = mapped.aliases.copy()
  aliases.push([component])
  {
    ..mapped,
    origin: UnpivotResult,
    producer: Some(UnpivotProducer(operation, parent)),
    declared_records: mapped.records,
    declared_fields: fields,
    source,
    fields,
    aliases,
    usage: { fields: fields.length(), name_bytes: before - b.text, },
  }
}
