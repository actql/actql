///|
/// Read the existing domain's declared payload and execution quota under the
/// same nominal Host/child/current checks. This neither issues capacity nor
/// estimates available allocator space. In particular, payload includes its
/// original physical controls; callers still need their charged-layout bound.
/// Unlike transport projection, this does not retain a recipe/descriptor cache.
pub fn[T, C] NativeHostBootstrap::backed_domain_capacity(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[(Int64, Int64), NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  let loan = domain.view.loan
  match
    @resources.backed_execution_delegation_description(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
    ) {
    Err(issue) => Err(Accounting(issue))
    Ok((extent, _, limits)) =>
      Ok((extent.payload_length, limits.execution_bytes))
  }
}
