///|
/// Admit the standard Client environment once under the shared Host limits.
/// Installed ABI profiles must reject unavailable capabilities before calling
/// this helper. Admission does not assert execution support or grant authority.
pub fn admit_client_check_environment(
  body : String,
  evidence_bundle_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
) -> @checked.CheckEnvironment? {
  let wire = match
    @environment.read(@utf8.encode(body), evidence_bundle_cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(@checked.checking_environment(wire, expressions, operations))
}
