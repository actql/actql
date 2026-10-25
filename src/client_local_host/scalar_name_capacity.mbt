///|
/// Scalar cells still charge original UTF-8 field names per row occurrence.
fn client_local_scalar_name_bytes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  match client_local_schema_proof_inventory(sequences) {
    Some(inventory) => client_local_inventory_names(inventory, max_rows)
    None => None
  }
}
