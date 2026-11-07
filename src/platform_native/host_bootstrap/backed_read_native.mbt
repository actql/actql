///|
extern "C" fn read_context_supported_ffi() -> Int = "actql_bootstrap_read_supported"

///|
#borrow(domain)
extern "C" fn prepare_read_context_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_prepare_read_context"

///|
#borrow(domain)
extern "C" fn prepare_bounded_read_context_ffi(
  domain : PhysicalExtentDomain,
  bytes : Int64,
) -> Int = "actql_bootstrap_prepare_bounded_read_context"

///|
#borrow(domain)
extern "C" fn read_context_status_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_read_context_status"

///|
#borrow(domain)
extern "C" fn read_context_entered_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_read_context_entered"

///|
#borrow(domain)
extern "C" fn read_context_unentered_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_read_context_unentered"

///|
#borrow(domain)
extern "C" fn enter_read_context_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_enter_read_context"

///|
#borrow(domain)
extern "C" fn leave_read_context_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_leave_read_context"

///|
#borrow(domain)
extern "C" fn finish_failed_read_entry_cleanup_ffi(
  domain : PhysicalExtentDomain,
) -> Int = "actql_bootstrap_finish_failed_read_entry_cleanup"

///|
#borrow(domain)
extern "C" fn close_read_context_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_close_read_context"

///|
/// The existing domain is the original partial carrier; no new pointer, Root,
/// Ledger or byte reserve is created here. Stock builds refuse before claiming.
pub fn[T, C] NativeHostBootstrap::prepare_backed_read_context(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
  execution_ceiling? : Int64,
) -> Result[Unit, NativeBackedExecutionIssue] {
  let prepared = self.with_backed_read_bookkeeping(original, () => {
    match self.require_domain_current(original, domain, child) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if !domain.transferred || read_context_supported_ffi() != 1 {
      return Err(Bootstrap(Unavailable))
    }
    if domain.read_attempted {
      return Err(Bootstrap(AlreadyConsumed))
    }
    match self.borrow_backed_domain_read_use(original, domain, child) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    domain.read_attempted = true
    Ok(())
  })
  match prepared {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = match execution_ceiling {
    None => prepare_read_context_ffi(domain.physical)
    Some(bytes) => prepare_bounded_read_context_ffi(domain.physical, bytes)
  }
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  self.require_backed_read_context_current(original, domain, child)
}

///|
/// Accounting use only. Do not create a parent physical read context in a
/// payload that must be lent to another process. The original C provider
/// correctly excludes that borrow while a parent read context exists.
fn[T, C] NativeHostBootstrap::borrow_backed_domain_read_use(
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
  if domain.read_use is Some(_) || domain.read_retired {
    return Err(Bootstrap(AlreadyConsumed))
  }
  let loan = domain.view.loan
  let read_use = match
    @resources.borrow_backed_execution_read_use(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(value) => value
  }
  // Publish original custody BEFORE any physical context allocation. Failure
  // keeps this same domain and use; caller must close, never acquire again.
  domain.read_use = Some(read_use)
  Ok(())
}

///|
pub fn[T, C] NativeHostBootstrap::require_backed_read_context_current(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_domain_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard domain.read_use is Some(read_use) &&
    domain.read_attempted &&
    !domain.read_retired else {
    return Err(Bootstrap(Unavailable))
  }
  let loan = domain.view.loan
  match
    @resources.require_backed_execution_read_use_current(
      loan.region.accounting,
      self,
      child,
      loan.accounting,
      read_use,
    ) {
    Err(issue) => return Err(Accounting(issue))
    Ok(_) => ()
  }
  let status = read_context_status_ffi(domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
/// Check the already entered original physical scope. This does not enter,
/// lend or disclose its context, and cannot replace Common use/current checks.
pub fn[T, C] NativeHostBootstrap::require_backed_read_context_entered(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = read_context_entered_ffi(domain.physical)
  if status == 0 {
    Ok(())
  } else {
    Err(Bootstrap(Physical(status)))
  }
}

///|
/// Existing cleanup callers only. Revalidate the same retained use and actual
/// entered physical context after logical stop. This neither revives normal
/// current nor returns its borrow, descriptor or parent acknowledgement.
pub fn[T, C] NativeHostBootstrap::require_backed_read_cleanup_entered(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  let read_use = match self.original_read_carrier(original, domain, child) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !domain.read_attempted || domain.read_retired {
    return Err(Bootstrap(Unavailable))
  }
  let status = read_context_status_ffi(domain.physical)
  if status != 0 {
    return Err(Bootstrap(Physical(status)))
  }
  let entered = read_context_entered_ffi(domain.physical)
  if entered != 0 {
    return Err(Bootstrap(Physical(entered)))
  }
  let loan = domain.view.loan
  // The existing stop is idempotent and validates the original region,
  // provider, child, ticket and unreturned use even while closing. It issues
  // no successful cleanup fact and cannot allocate or enter another context.
  @resources.stop_backed_execution_read_use(
    loan.region.accounting,
    self,
    child,
    loan.accounting,
    read_use,
  ).map_err(issue => Accounting(issue))
}

///|
/// Observe the original context before a managed caller enters it. This does
/// not supply an outer control allocation or switch out of another context.
pub fn[T, C] NativeHostBootstrap::require_backed_read_context_unentered(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = read_context_unentered_ffi(domain.physical)
  if status == 0 {
    Ok(())
  } else {
    Err(Bootstrap(Physical(status)))
  }
}

///|
/// Bracket the WHOLE managed caller, including input encoding and returned
/// values/failures. Escaped aliases retain original extents after leave. The
/// same provider's active-TLS getter is a borrowed C-only filesystem seam.
pub fn[T, C] NativeHostBootstrap::enter_backed_read_context(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match
    self.with_backed_read_bookkeeping(original, () => {
      self.require_backed_read_context_current(original, domain, child)
    }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = enter_read_context_ffi(domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
fn[T, C] NativeHostBootstrap::original_read_carrier(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[
  @resources.BackedExecutionReadUse[NativeHostBootstrap[T], C],
  NativeBackedExecutionIssue,
] {
  match self.original_domain_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match domain.read_use {
    Some(value) => Ok(value)
    None => Err(Bootstrap(Unavailable))
  }
}

///|
/// Existing cleanup caller only. Logical closing forbids new work while the
/// original Root/Reader Owner finishes its retained diagnostics/cleanup scope.
/// This is not a fresh read permission or a replacement physical user.
pub fn[T, C] NativeHostBootstrap::enter_backed_read_cleanup(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match
    self.with_backed_read_bookkeeping(
      original,
      () => {
        let read_use = match
          self.original_read_carrier(original, domain, child) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        // A live child can own only the Common use. It has no parent C cleanup
        // frame; its physical context/aliases remain that child's obligation.
        if !domain.read_attempted || domain.read_retired {
          return Err(Bootstrap(Unavailable))
        }
        let loan = domain.view.loan
        @resources.stop_backed_execution_read_use(
          loan.region.accounting,
          self,
          child,
          loan.accounting,
          read_use,
        ).map_err(issue => Accounting(issue))
      },
      cleanup=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = enter_read_context_ffi(domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
/// Original leaves remain available after logical Host/region closing. A
/// failed leave keeps the same physical active/scope record for original retry.
pub fn[T, C] NativeHostBootstrap::leave_backed_read_context(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_read_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.read_attempted || domain.read_retired {
    return Err(Bootstrap(Unavailable))
  }
  let status = leave_read_context_ffi(domain.physical)
  if status != 0 {
    Err(Bootstrap(Physical(status)))
  } else {
    Ok(())
  }
}

///|
/// A failed caller entry retains its nominal flight until this SAME physical
/// context confirms no Read frame remains. This is neither a normal entry nor
/// context/user/parent retirement; those original ACKs remain separate.
pub fn[T, C] NativeHostBootstrap::finish_backed_failed_read_entry_cleanup(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_read_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.read_attempted || domain.read_retired {
    return Err(Bootstrap(Unavailable))
  }
  let status = finish_failed_read_entry_cleanup_ffi(domain.physical)
  if status == 0 {
    Ok(())
  } else {
    Err(Bootstrap(Physical(status)))
  }
}

///|
/// Child-first original cleanup. The C context waits for active calls, users
/// and last aliases; only its actual retirement permits Common borrow return.
/// If Common return then fails, do not repeat physical retirement or replace
/// the domain. Parent domain/view/FD/process cleanup remains separate.
pub fn[T, C] NativeHostBootstrap::close_backed_read_context(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.finish_failed_backed_read_bookkeeping(original) {
    Err(issue) => return Err(Bootstrap(issue))
    Ok(_) => ()
  }
  match
    self.with_backed_read_bookkeeping(
      original,
      () => {
        let read_use = match
          self.original_read_carrier(original, domain, child) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        let loan = domain.view.loan
        @resources.stop_backed_execution_read_use(
          loan.region.accounting,
          self,
          child,
          loan.accounting,
          read_use,
        ).map_err(issue => Accounting(issue))
      },
      cleanup=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.read_retired {
    if domain.read_attempted {
      let status = close_read_context_ffi(domain.physical)
      if status != 0 {
        return Err(Bootstrap(Physical(status)))
      }
    }
    // No local attempt proves only no parent acquisition, never child/FD ACK.
    domain.read_retired = true
  }
  self.with_backed_read_bookkeeping(
    original,
    () => {
      let read_use = match self.original_read_carrier(original, domain, child) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      let loan = domain.view.loan
      match
        @resources.return_backed_execution_read_use_after_owner_ack(
          loan.region.accounting,
          self,
          child,
          loan.accounting,
          read_use,
        ) {
        Err(issue) => Err(Accounting(issue))
        Ok(_) => {
          domain.read_use = None
          Ok(())
        }
      }
    },
    cleanup=true,
  )
}

///|
/// Identity-only cleanup observation on this original parent context. A
/// logical stop, missing context, or child-process exit supplies no such ACK.
/// Physical close may already be confirmed while Common use return is pending.
pub fn[T, C] NativeHostBootstrap::require_backed_read_context_retired(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[Unit, NativeBackedExecutionIssue] {
  match self.original_domain_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if domain.read_attempted && domain.read_retired {
    Ok(())
  } else {
    Err(Bootstrap(ReadersPending))
  }
}

///|
#borrow(domain)
extern "C" fn read_context_scope_ffi(domain : PhysicalExtentDomain) -> Int = "actql_bootstrap_read_context_scope"

///|
pub(all) enum NativeBackedReadScope {
  BackedReadUnentered
  BackedReadEntered
} derive(Eq, Debug)

///|
/// Observe this exact current original, not a missing/foreign/failed result as
/// inactivity. Unentered does not imply another Read/owned scope is clear.
pub fn[T, C] NativeHostBootstrap::observe_backed_read_context_scope(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[NativeBackedReadScope, NativeBackedExecutionIssue] {
  match self.require_backed_read_context_current(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match read_context_scope_ffi(domain.physical) {
    0 => Ok(BackedReadUnentered)
    1 => Ok(BackedReadEntered)
    code => Err(Bootstrap(Physical(code)))
  }
}

///|
/// Cleanup-only observation of the same retained context after logical stop.
/// No current/entry/borrow/report or physical-retirement ACK is issued here.
#borrow(domain)
extern "C" fn read_context_cleanup_scope_ffi(
  domain : PhysicalExtentDomain,
) -> Int = "actql_bootstrap_read_context_cleanup_scope"

///|
pub fn[T, C] NativeHostBootstrap::observe_backed_read_cleanup_scope(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[NativeBackedReadScope, NativeBackedExecutionIssue] {
  match self.original_read_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.read_attempted || domain.read_retired {
    return Err(Bootstrap(Unavailable))
  }
  match read_context_cleanup_scope_ffi(domain.physical) {
    0 => Ok(BackedReadUnentered)
    1 => Ok(BackedReadEntered)
    code => Err(Bootstrap(Physical(code)))
  }
}
