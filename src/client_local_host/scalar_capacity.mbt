///|
// Only checked original scalar schemas justify this smaller value envelope.
// Unknown or nested contracts retain the general budget; no rows are sampled.
fn client_local_scalar_schema_width(schema : @schema.Schema) -> Int? {
  client_local_scalar_schema_precision(schema, false).map(_ => {
    @schema.field_count(schema)
  })
}

///|
// Optional quote evidence from the original Contract, not another admission.
// Strict callers keep Number/Boolean only. Decimal mode returns the greatest
// admitted precision and still refuses Text/nested/opaque row fields.
fn client_local_scalar_schema_precision(
  schema : @schema.Schema,
  decimal : Bool,
) -> Int? {
  let width = @schema.field_count(schema)
  if width > client_local_schema_proof_work() {
    return None
  }
  let mut precision = 0
  for index in 0..<width {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    match @schema.field_contract(field).shape {
      @contract.Number | @contract.Boolean => ()
      @contract.Decimal(precision=p, ..) => {
        if !decimal {
          return None
        }
        precision = Int::max(precision, p)
      }
      _ => return None
    }
  }
  Some(precision)
}

///|
fn client_local_scalar_nodes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  match client_local_schema_proof_inventory(sequences) {
    Some(inventory) => client_local_inventory_nodes(inventory, max_rows)
    None => None
  }
}
