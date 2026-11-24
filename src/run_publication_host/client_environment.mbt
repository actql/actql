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
  // A JSON node or top-level evidence member needs at least one input byte.
  // These intrinsic finite decoder ceilings do not price bytes as nodes or
  // grant capacity. The installed Source entrance reserves its measured
  // same-wire construction geometry before calling this pure reader. Explicit
  // callers of environment.read keep their independently selected limits.
  let bytes = @utf8.encode(body)
  let input_extent = bytes.length()
  match
    @environment.read(bytes, evidence_bundle_cid, {
      max_bytes: input_extent,
      max_nodes: input_extent,
      max_depth: 64,
      max_members: input_extent,
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
/// Select the installed Local relation profile from the authenticated policy.
/// The callers link the Common evaluator and use the same built-in reducer.
pub fn admit_local_relation_check_environment(
  body : String,
  evidence_bundle_cid : String,
) -> @checked.CheckEnvironment? {
  guard admit_client_check_environment_wire(body, evidence_bundle_cid)
    is Some(wire) else {
    return None
  }
  let policy = @environment.host_policy(wire)
  guard @decode.object_length(policy) is Some(field_count) else { return None }
  let mut text_time = false
  for position in 0..<field_count {
    if @decode.field_at(policy, position) is Some(("text_time_evaluation", _)) {
      text_time = true
      break
    }
  }
  admit_client_check_environment_from_wire(
    wire,
    { text_time, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile=Some(@numeric.builtin_profile()),
  )
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
  guard @environment.original_model_tasks_admission_limits(wire) is Some(limits) else {
    return None
  }
  let model_tasks = match @environment.check_model_tasks(wire, limits) {
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

///|
/// The same already admitted wire with the existing selected numeric profile.
/// This neither parses/reissues its original nor selects an executable Owner.
pub fn admit_client_check_environment_from_wire_with_numeric_profile_cid(
  wire : @environment.WireEnvironment,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  numeric_profile_cid : String,
  graph? : Bool = false,
) -> @checked.CheckEnvironment? {
  let numeric = @numeric.builtin_profile()
  if numeric_profile_cid != @numeric.cid(numeric) {
    return None
  }
  admit_client_check_environment_from_wire(
    wire,
    expressions,
    operations,
    numeric_profile=Some(numeric),
    graph~,
  )
}
