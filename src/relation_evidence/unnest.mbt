///|
/// Original input witness, including its admission or producer obligations.
pub fn key_unnest_input(key : KeyedRelation) -> KeyedRelation? {
  match key.producer {
    Some(UnnestProducer(_, parent)) => Some(parent)
    _ => None
  }
}

///|
// The optional index is the prepared key extension, not the authored option:
// an outer singleton can author an index while retaining only its parent key.
fn unnest_key(
  operation : @relation.CheckedOperation,
  parent : KeyedRelation,
  mapped : KeyedRelation,
  index : String?,
  b : TransferBudget,
) -> KeyedRelation raise Stop {
  let source = @relation.source(operation)
  spend(b, source, mapped.fields.length() + mapped.aliases.length() + 1)
  let fields = mapped.fields.copy()
  let aliases = mapped.aliases.copy()
  if index is Some(name) {
    let field = @row.Unqualified(name)
    charge(b, source, field)
    let contract = @row.lookup(@relation.output_schema(operation), field)
    guard contract is Some(c) && !c.nullable else {
      fail(source, InputContractMismatch)
    }
    let item = plain_key_field(field, contract)
    fields.push(item)
    aliases.push([item])
  }
  {
    ..mapped,
    origin: UnnestResult,
    producer: Some(UnnestProducer(operation, parent)),
    declared_records: mapped.records,
    declared_fields: fields,
    source,
    fields,
    aliases,
    usage: { ..mapped.usage, fields: fields.length(), },
  }
}
