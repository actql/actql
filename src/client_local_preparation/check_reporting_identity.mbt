///|
/// Existing generated reporting schema identities, in reason/outcome order.
/// A Host includes these DATA identifiers in its original keyed check context;
/// neither the pair nor that context is a Run, namespace or execution grant.
/// Keep the generator's pins as the only production source for these values.
pub fn client_program_check_reporting_schema_cids() -> (String, String) {
  (check_reason_schema_cid, check_outcome_schema_cid)
}
