///|
/// The complete immutable unsigned verified wrapper already admitted by this
/// Owner. This emits neither a Host signature nor a completed Resolution. A
/// signing Host must retain these exact bytes and their original verified_at
/// before claiming a use; restoring them must not select another timestamp.
pub fn AdmittedResolution::prepared_wire(
  self : AdmittedResolution,
  limits : WireLimits,
) -> Result[String, ResolutionIssue] {
  if !valid_limits(limits) {
    return Err(ResolutionInvalidLimits)
  }
  match wire_of(self.body, limits) {
    Some(wire) => Ok(wire)
    None => Err(ResolutionEncoding)
  }
}
