///|
/// Allocation-free identity/scope observation for a pre-owned entry receiver.
/// This is not current/admission, a Ledger borrow or a physical retirement ACK.
/// The caller separately retains the original current cut and byte inventory.
pub fn[T, C] NativeHostBootstrap::original_backed_read_scope_matches(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  entered : Bool,
) -> Bool {
  let view = domain.view
  let loan = view.loan
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(loan.region.owner, self) ||
    !physical_equal(loan.child, child) ||
    domain.closed ||
    view.closed ||
    loan.physical_returned ||
    loan.settled ||
    loan.region.closed ||
    !(view.domain is Some(selected) && physical_equal(selected, domain)) ||
    !(loan.view is Some(selected) && physical_equal(selected, view)) ||
    !domain.read_attempted ||
    domain.read_retired ||
    domain.read_use is None {
    return false
  }
  read_context_cleanup_scope_ffi(domain.physical) ==
  (if entered { 1 } else { 0 })
}
