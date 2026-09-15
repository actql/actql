///|
/// Add ordinary Program proof records without reissuing admitted Host sources.
/// Existing claim indices and exact Host policy owners remain in place. The
/// caller still checks each new proof against its operation and actual inputs.
pub fn extend_program_sources(
  original : HostSources,
  additional : Array[@wire.ProgramProofClaim],
  limits : @wire.ClosureLimits,
) -> Result[HostSources, @wire.ProgramExtensionIssue] {
  let claims = match
    @wire.extend_program_claims(original.claims, additional, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let sources = original.sources.copy()
  for _ in additional {
    sources.push(None)
  }
  Ok({
    claims,
    sources,
    count: original.count,
    bytes: original.bytes,
    nodes: original.nodes,
    origin: original.origin,
    dependencies: original.dependencies,
    local_claims: original.local_claims,
    local_limits: original.local_limits,
  })
}
