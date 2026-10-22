///|
/// Same-domain physical observations, including controls and pending extents.
/// Peak is retained within the original holding; none of these fields grants
/// capacity, proves input adequacy, or acknowledges retirement.
pub(all) struct NativeDomainInventory {
  capacity_bytes : Int64
  page_bytes : Int64
  control_bytes : Int64
  occupied_bytes : Int64
  peak_occupied_bytes : Int64
} derive(Eq, Debug)

///|
#borrow(domain, output)
extern "C" fn domain_inventory_ffi(
  domain : PhysicalExtentDomain,
  output : FixedArray[Int64],
  count : Int,
) -> Int = "actql_bootstrap_domain_inventory"

///|
/// Observe this original without entering or replacing its physical scope.
/// The caller covers the fixed output and returned scalar DATA in its existing
/// allowance. This observes occupancy, not cumulative extent allocation work.
pub fn[T, C] NativeHostBootstrap::observe_backed_domain_inventory(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[NativeDomainInventory, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  let values = FixedArray::make(5, 0L)
  let code = domain_inventory_ffi(domain.physical, values, 5)
  if code != 0 {
    return Err(Bootstrap(Physical(code)))
  }
  Ok({
    capacity_bytes: values[0],
    page_bytes: values[1],
    control_bytes: values[2],
    occupied_bytes: values[3],
    peak_occupied_bytes: values[4],
  })
}
