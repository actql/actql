///|
#borrow(backing, domain)
extern "C" fn checked_read_working_status_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  bytes : Int64,
) -> Int = "actql_bootstrap_checked_read_working_status"

///|
#borrow(backing, domain)
extern "C" fn quote_checked_read_growth_covering_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
  contiguous_bytes : Int64,
  minimum_usable_bytes : Int64,
) -> Int64 = "actql_bootstrap_quote_checked_read_growth_covering"

///|
#borrow(backing, domain)
extern "C" fn domain_growth_eligible_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
) -> Int = "actql_bootstrap_domain_growth_eligible"

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
pub fn[T, C] NativeHostBootstrap::prepare_backed_domain_growth(
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
  if domain.working_growth_prepared {
    return Ok(())
  }
  let status = prepare_domain_growth_ffi(self.backing, domain.physical)
  if status == 0 {
    domain.working_growth_prepared = true
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
  checked_read? : Bool = false,
  minimum_usable_bytes? : Int64 = 0L,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.control is Some(control) else {
    return Err(Bootstrap(Unavailable))
  }
  let serial = if checked_read {
    quote_checked_read_growth_covering_ffi(
      self.backing,
      domain.physical,
      contiguous_bytes,
      minimum_usable_bytes,
    )
  } else {
    quote_domain_growth_ffi(self.backing, domain.physical, contiguous_bytes)
  }
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
  // The parent's one current callback may have stopped this original child.
  // Recheck only retained child/current facts after it, with no new callback
  // or allocation between the final fence and the physical acquisition.
  let current = if self.closing ||
    domain.closed ||
    domain.view.closed ||
    domain.view.loan.region.closing {
    Err(Accounting(@resources.RegionClosing))
  } else {
    let loan = domain.view.loan
    match domain.read_use {
      Some(read_use) =>
        @resources.require_backed_execution_read_use_current(
          loan.region.accounting,
          self,
          child,
          loan.accounting,
          read_use,
        ).map_err(issue => Accounting(issue))
      None =>
        @resources.check_backed_execution_delegation_current(
          loan.region.accounting,
          self,
          child,
          loan.accounting,
        ).map_err(issue => Accounting(issue))
    }
  }
  if current is Err(issue) {
    if cancel_domain_growth_quote_ffi(self.backing, domain.physical, serial) ==
      0 {
      match @resources.abort_shared_capacity_growth_after_cleanup(growth) {
        Err(_) => () // Keep the exact logical pending original for cleanup.
        Ok(_) => {
          self.growth = None
          domain.working_growth_serial = None
        }
      }
    }
    return Err(issue)
  }
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
  // The physical receipt's usable suffix updates only this SAME original
  // acquired window. The full mapping remains on the Root control claim;
  // neither the old contiguous extent nor its address is expanded.
  let completed = if domain.view.loan.initial_window is Some(_) {
    let payload = domain_growth_scalar_ffi(
      self.backing,
      domain.physical,
      serial,
      5,
    )
    let controls = domain_growth_scalar_ffi(
      self.backing,
      domain.physical,
      serial,
      6,
    )
    if payload <= controls || controls < 0L {
      return Err(Bootstrap(Unavailable))
    }
    let loan = domain.view.loan
    @resources.complete_backed_execution_window_after_acquisition(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
      growth,
      payload - controls,
    ).map_err(issue => Accounting(issue))
  } else {
    @resources.complete_shared_capacity_growth_after_acquisition(growth).map_err(issue => {
        Bootstrap(Resource(issue))
      },
    )
  }
  match completed {
    Err(issue) => return Err(issue)
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
  if outcome == 1L {
    match @resources.abort_shared_capacity_growth_after_cleanup(growth) {
      Err(issue) => return Err(Bootstrap(Resource(issue)))
      Ok(_) => {
        self.growth = None
        domain.working_growth_serial = None
        return Ok(())
      }
    }
  }
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

///|
/// Actual constructor preflight in this SAME current Read. The raw size comes
/// from the selected Native ABI/constructor, never a logical R/E deficit.
/// Success describes backing now; only the following constructor can execute.
pub fn[T, C] NativeHostBootstrap::prepare_backed_read_working(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  contiguous_bytes : Int64,
  minimum_usable_bytes? : Int64 = 0L,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_backed_read_context_entered(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if minimum_usable_bytes < 0L {
    return Err(Bootstrap(Unavailable))
  }
  let placement = checked_read_working_status_ffi(
    self.backing,
    domain.physical,
    contiguous_bytes,
  )
  match placement {
    0 if minimum_usable_bytes == 0L => Ok(())
    0 | 1 if domain.working_growth_prepared => {
      match
        self.grow_backed_domain_working(
          original,
          domain,
          child,
          contiguous_bytes,
          checked_read=true,
          minimum_usable_bytes~,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      // Acquisition/accounting may invoke the same parent's current callback.
      // A stopped original Read cannot turn that physical result into a new
      // constructor entrance; the acquired bytes remain on the same owner.
      self.require_backed_read_context_current(original, domain, child)
    }
    _ => Err(Bootstrap(Unavailable))
  }
}
