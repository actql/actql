///|
// Actual same-domain supplier ports. Scalar quotations describe one original
// physical serial, not a caller-provided byte budget or authority.
#borrow(backing, domain)
extern "C" fn prepare_domain_growth_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
) -> Int = "actql_bootstrap_prepare_domain_growth"

///|
#borrow(backing, domain)
extern "C" fn quote_domain_growth_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  bytes : Int64,
) -> Int64 = "actql_bootstrap_quote_domain_growth"

///|
#borrow(backing, domain)
extern "C" fn domain_growth_scalar_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  serial : Int64,
  field : Int,
) -> Int64 = "actql_bootstrap_domain_growth_scalar"

///|
#borrow(backing, domain)
extern "C" fn acquire_domain_growth_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  serial : Int64,
) -> Int = "actql_bootstrap_acquire_domain_growth"

///|
#borrow(backing, domain)
extern "C" fn finish_domain_growth_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  serial : Int64,
) -> Int = "actql_bootstrap_finish_domain_growth"

///|
#borrow(backing, domain)
extern "C" fn cancel_domain_growth_quote_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  serial : Int64,
) -> Int = "actql_bootstrap_cancel_domain_growth_quote"

///|
#borrow(backing, domain)
extern "C" fn reconcile_domain_growth_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  serial : Int64,
) -> Int64 = "actql_bootstrap_reconcile_domain_growth"

///|
// Select the exact unborrowed local view BEFORE entering any allocator scope.
// No FD/exported domain can acquire this path. Child policy/Read limits remain
// unchanged; the original parent owns the later self-hosted receipts.
#warnings("-unused_value")
fn[T, C] NativeHostBootstrap::prepare_backed_domain_growth(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.transferred {
    return Err(Bootstrap(Unavailable))
  }
  let status = prepare_domain_growth_ffi(self.backing, domain.physical)
  if status == 0 {
    Ok(())
  } else {
    Err(Bootstrap(Physical(status)))
  }
}

///|
// The selected constructor supplies its actual contiguous raw allocation,
// independently of its Common R/E quote. Never substitute the logical deficit,
// a policy ceiling or observed free bytes for this physical geometry.
// The caller must separately fund all Common/result/callback constructors in
// its enclosing original lifetime; this physical bridge cannot fund itself.
#warnings("-unused_value")
fn[T, C] NativeHostBootstrap::grow_backed_domain_working(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  contiguous_bytes : Int64,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.control is Some(control) else {
    return Err(Bootstrap(Unavailable))
  }
  let serial = quote_domain_growth_ffi(
    self.backing,
    domain.physical,
    contiguous_bytes,
  )
  if serial <= 0L {
    return Err(Bootstrap(Unavailable))
  }
  let before = domain_growth_scalar_ffi(
    self.backing,
    domain.physical,
    serial,
    1,
  )
  let addition = domain_growth_scalar_ffi(
    self.backing,
    domain.physical,
    serial,
    3,
  )
  if before != @resources.shared_capacity_usage(self.capacity).capacity ||
    before < 0L ||
    addition <= 0L ||
    addition > 9223372036854775807L - before {
    cancel_domain_growth_quote_ffi(self.backing, domain.physical, serial)
    |> ignore
    return Err(Bootstrap(Unavailable))
  }
  // Charge the ENTIRE actual addition on the original parent before mmap.
  // The child receives no new logical permission. Receipt/control/payload and
  // even an unattached partial mapping stay in this claim until root cleanup.
  let growth = match
    @resources.begin_shared_capacity_growth(
      self.capacity,
      control,
      before + addition,
      addition,
    ) {
    Err(issue) => {
      cancel_domain_growth_quote_ffi(self.backing, domain.physical, serial)
      |> ignore
      return Err(Bootstrap(Resource(issue)))
    }
    Ok(value) => value
  }
  self.growth = Some(growth)
  domain.working_growth_serial = Some(serial)
  let status = acquire_domain_growth_ffi(self.backing, domain.physical, serial)
  if status != 0 {
    let outcome = domain_growth_scalar_ffi(
      self.backing,
      domain.physical,
      serial,
      7,
    )
    // Only the original supplier's atomic no-acquisition outcome can return
    // this suffix. Partial/unknown results retain the SAME pending originals.
    if outcome == 1L &&
      cancel_domain_growth_quote_ffi(self.backing, domain.physical, serial) == 0 {
      match @resources.abort_shared_capacity_growth_after_cleanup(growth) {
        Err(issue) => return Err(Bootstrap(Resource(issue)))
        Ok(_) => {
          self.growth = None
          domain.working_growth_serial = None
        }
      }
    }
    return Err(Bootstrap(Physical(status)))
  }
  let finished = finish_domain_growth_ffi(self.backing, domain.physical, serial)
  if finished != 0 {
    return Err(Bootstrap(Physical(finished)))
  }
  match @resources.complete_shared_capacity_growth_after_acquisition(growth) {
    Err(issue) => return Err(Bootstrap(Resource(issue)))
    Ok(_) => {
      self.growth = None
      domain.working_growth_serial = None
    }
  }
  Ok(())
}

///|
// Original cleanup only, outside allocation scopes. A retained partial mapping
// may be completed or detached, but the root keeps its bytes in BOTH cases.
// This observes the supplier's exact receipt rather than a missing query/GC.
#warnings("-unused_value")
fn[T, C] NativeHostBootstrap::reconcile_backed_domain_working(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_domain_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard domain.working_growth_serial is Some(serial) &&
    self.growth is Some(growth) else {
    return Err(Bootstrap(Unavailable))
  }
  let outcome = reconcile_domain_growth_ffi(
    self.backing,
    domain.physical,
    serial,
  )
  if outcome != 2L && outcome != 3L {
    return Err(Bootstrap(ReadersPending))
  }
  match @resources.complete_shared_capacity_growth_after_acquisition(growth) {
    Err(issue) => Err(Bootstrap(Resource(issue)))
    Ok(_) => {
      self.growth = None
      domain.working_growth_serial = None
      Ok(())
    }
  }
}
