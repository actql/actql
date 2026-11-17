///|
/// Canonical nonsecret installation/configuration materials for the existing
/// Model binding reader. JSON text is only the Host DATA transport; canonical
/// order, data-key preservation and identities stay with the existing owner.
/// These originals are not a Provider, defaults admission, currentness,
/// installation provenance, physical funding or Account/egress permission.
pub fn prepare_client_model_provider_originals(
  installation_wire : String,
  contract_wire : String,
  configuration_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String, String),
  @environment.ModelTaskIssue,
] {
  // Keep the existing binding issuer's full admission envelope. This narrower
  // constructor cannot emit a body that requires widening that later reader.
  if max_bytes <= 0 ||
    max_bytes > 65536 ||
    max_nodes <= 0 ||
    max_nodes > 4096 ||
    max_depth <= 0 ||
    max_depth > 32 ||
    max_work < 0 {
    return Err({ kind: @environment.InvalidLimits, source: None, })
  }
  // Three finite originals, each with source/decode, canonical output and
  // hash work. Pre-admit a conservative four complete traversals per input;
  // physical buffers, canonical trees and output overlap remain Host funded.
  if 12L * (max_bytes.to_int64() + max_nodes.to_int64()) > max_work.to_int64() {
    return Err({ kind: @environment.WorkLimit, source: None, })
  }
  let originals : Array[(String, String)] = []
  for wire in [installation_wire, contract_wire, configuration_wire] {
    if @scalar.admit_utf8_length(wire, max_bytes) is Err(_) {
      return Err({ kind: @environment.BodyLimit, source: None, })
    }
    guard parse_plan_identity_value(wire, max_bytes, max_nodes, max_depth)
      is Some(value) else {
      return Err({ kind: @environment.InvalidBody, source: None, })
    }
    try {
      let canonical = @canonical.stringify_value(
        value, max_bytes, max_nodes, max_depth,
      )
      let cid = @canonical.cid_value(value, max_bytes, max_nodes, max_depth)
      originals.push((canonical, cid))
    } catch {
      _ => return Err({ kind: @environment.BodyLimit, source: None, })
    }
  }
  Ok(
    (
      originals[0].0,
      originals[0].1,
      originals[1].0,
      originals[1].1,
      originals[2].0,
      originals[2].1,
    ),
  )
}
