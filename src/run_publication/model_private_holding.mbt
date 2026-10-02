///|
/// Store-local custody identity, not execution authority or replay evidence.
/// Role and slot identify one immutable cell in this Run's private inventory.
/// A different body for that cell conflicts instead of replacing an outcome.
pub fn model_private_holding_cid(
  definition : PublicationContract,
  store_authority_cid : String,
  role : String,
  slot : Int,
) -> String? {
  if definition.name != "run_definition" ||
    !valid_contract_cid(store_authority_cid) {
    return None
  }
  match role {
    "model_capture_bundle" | "observation_set" | "run_invocation" =>
      if slot != -1 {
        return None
      }
    "model_slot_capture"
    | "model_call_attempt"
    | "model_attempt_accounting"
    | "model_attempt_outcome"
    | "model_dispatch_authority" => if slot < 0 || slot >= 128 { return None }
    _ => return None
  }
  let writer = @encode.hashing_writer(1024, 32, 2) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "role")
    @encode.string_value(writer, role)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, definition.identity)
    @encode.key(writer, "slot")
    @encode.number_value(writer, slot.to_double())
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-model-private-holding/0.1")
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}
