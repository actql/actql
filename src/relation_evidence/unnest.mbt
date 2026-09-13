///|
/// Original input witness, including its admission or producer obligations.
pub fn key_unnest_input(key : KeyedRelation) -> KeyedRelation? {
  match key.producer {
    Some(UnnestProducer(_, parent)) => Some(parent)
    _ => None
  }
}

///|
fn unnest_key(
  operation : @relation.CheckedOperation,
  parent : KeyedRelation,
  mapped : KeyedRelation,
  b : TransferBudget,
) -> KeyedRelation raise Stop {
  let source = @relation.source(operation)
  guard @relation.reshape(operation)
    is Some(Unnest(index~, outer~, max_items~, ..)) else {
    fail(source, InputContractMismatch)
  }
  spend(b, source, mapped.fields.length() + mapped.aliases.length() + 1)
  let fields = mapped.fields.copy()
  let aliases = mapped.aliases.copy()
  if !outer && index is Some(name) {
    let field = @row.Unqualified(name)
    charge(b, source, field)
    let contract = @row.lookup(@relation.output_schema(operation), field)
    guard contract is Some(c) && !c.nullable else {
      fail(source, InputContractMismatch)
    }
    let item = plain_key_field(field, contract)
    fields.push(item)
    aliases.push([item])
  } else {
    // At most one output occurrence per admitted parent, including the single
    // synthetic outer row. This is conditional on array-bound admission, not
    // a claim that a nullable outer index is an identity component.
    guard outer && max_items is Some(n) && n <= 1L else {
      fail(source, InputContractMismatch)
    }
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
