///|
/// Admit the standard Client environment once under the shared Host limits.
/// Installed Host profiles must reject unavailable capabilities before calling
/// this helper. Admission does not assert execution support or grant authority.
pub fn admit_client_check_environment(
  body : String,
  evidence_bundle_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  numeric_profile_cid? : String? = None,
  property_graph? : Bool = false,
) -> @checked.CheckEnvironment? {
  let numeric = match numeric_profile_cid {
    None => None
    Some(cid) => {
      let selected = @numeric.builtin_profile()
      if cid != @numeric.cid(selected) {
        return None
      }
      Some(selected)
    }
  }
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
  let model_tasks = match
    @environment.check_model_tasks(wire, {
      bodies: {
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 64,
        max_members: 256,
      },
      contracts: { max_nodes: 4096, max_depth: 64, max_text_bytes: 65536, },
      max_work: 65536,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(
    @checked.checking_environment(
      wire,
      expressions,
      operations,
      numeric_profile=numeric,
      property_graph~,
      model_tasks=Some(model_tasks),
    ),
  )
}
