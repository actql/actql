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
  graph? : Bool = false,
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
  guard admit_client_check_environment_wire(body, evidence_bundle_cid)
    is Some(wire) else {
    return None
  }
  admit_client_check_environment_from_wire(
    wire,
    expressions,
    operations,
    numeric_profile=numeric,
    graph~,
  )
}

///|
/// The original bounded wire reader, shared by compatibility admission and
/// funded installation construction. Returned wire ownership is exact; this
/// neither checks a Catalog nor selects executable profiles.
pub fn admit_client_check_environment_wire(
  body : String,
  evidence_bundle_cid : String,
) -> @environment.WireEnvironment? {
  match
    @environment.read(@utf8.encode(body), evidence_bundle_cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
/// Continue the SAME admitted wire without encoding, parsing or hashing it
/// again. ModelTask admission and checker flags retain their original meaning.
pub fn admit_client_check_environment_from_wire(
  wire : @environment.WireEnvironment,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  numeric_profile? : @numeric.Profile? = None,
  graph? : Bool = false,
) -> @checked.CheckEnvironment? {
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
      numeric_profile~,
      graph~,
      model_tasks=Some(model_tasks),
    ),
  )
}
