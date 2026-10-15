///|
/// Join the original live Resource ticket with its actual same-provider FD
/// window. The caller retains this exact domain/loan before journal I/O. The
/// immutable result is DATA only, never original custody or a startup permit.
pub fn[T, C] NativeHostBootstrap::project_prepared_domain_original(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[
  (NativePreparedDomainTransport, @resources.BackedExecutionOriginalData),
  NativeBackedExecutionIssue,
] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  let region = domain.view.loan.region.accounting
  let ticket = domain.view.loan.accounting
  let before = match
    @resources.issue_backed_execution_original_data(region, self, child, ticket) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  let physical = match self.project_prepared_domain(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let after = match
    @resources.issue_backed_execution_original_data(region, self, child, ticket) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  if before != after || physical.limits != after.limits {
    return Err(Bootstrap(ForeignOriginal))
  }
  match self.require_domain_current(original, domain, child) {
    Err(issue) => Err(issue)
    Ok(_) => Ok((physical, after))
  }
}
