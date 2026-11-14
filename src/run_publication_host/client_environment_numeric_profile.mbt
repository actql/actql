///|
/// Continue an original funded wire with the same pinned numeric selection as
/// the compatibility reader. Profile identity supplies no execution authority.
pub fn admit_client_check_environment_from_wire_with_numeric_profile(
  wire : @environment.WireEnvironment,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  numeric_profile_cid : String,
  graph : Bool,
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
