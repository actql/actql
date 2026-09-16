///|
/// Exact supported profile body, not proof of a particular runtime's conformance
/// and not permission to omit an identity required by the admitted obligations.
struct ManagedExecutionProfile {
  cid : String
}

///|
pub(all) enum ManagedProfileIssue {
  InvalidLimits
  BodyLimit
  UnsupportedProfile
} derive(Eq, Debug)

///|
pub fn admit_managed_execution_profile(
  body : @identity.CanonicalValue,
  limits : RegistryLimits,
) -> Result[ManagedExecutionProfile, ManagedProfileIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 0 ||
    limits.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  let cid = @identity.cid_value(
    body,
    limits.max_body_bytes,
    limits.max_body_nodes,
    limits.max_body_depth,
  ) catch {
    _ => return Err(BodyLimit)
  }
  if cid != selected_managed_profile_cid {
    return Err(UnsupportedProfile)
  }
  Ok({ cid, })
}

///|
pub fn managed_execution_profile_cid(
  profile : ManagedExecutionProfile,
) -> String {
  profile.cid
}
