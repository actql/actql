///|
// Closed source-owned construction facts. These are not SDK input or a byte
// allowance. Each real issuer must certify its selected emitted object sizes
// and complete allocation-request count before using this control family.
// Count every sequential constructor in the selected cohort too. Only its
// original physical finish can reconcile unused/retired pages; a failed
// retirement or escaped alias keeps those bytes charged.
// Intentionally private: only scoped diagnostics construct this prerequisite
// until a complete product constructor certificate exists.
#warnings("-struct_never_constructed")
priv struct NativeControlConstruction {
  maximum_managed_request : Int64
  allocation_requests : Int64
}

///|
priv struct NativeRootControl[T] {
  mut owner : NativeHostBootstrap[T]?
  claim : @resources.SharedAllocation
  mut bytes : Int64
  mut reconciling : Bool
  mut closing : Bool
  mut physical_retired : Bool
  mut closed : Bool
}

///|
#borrow(backing)
extern "C" fn root_control_quote_ffi(
  backing : Backing,
  maximum_request : Int64,
  objects : Int64,
  include_context : Int,
) -> Int64 = "actql_bootstrap_root_control_quote"

///|
#borrow(backing)
extern "C" fn root_control_available_ffi(
  backing : Backing,
  bytes : Int64,
) -> Int = "actql_bootstrap_root_control_available"

///|
#borrow(backing)
extern "C" fn prepare_root_control_ffi(
  backing : Backing,
  maximum_request : Int64,
  requests : Int64,
) -> Int = "actql_bootstrap_prepare_root_control"

///|
#borrow(backing)
extern "C" fn extend_root_control_ffi(
  backing : Backing,
  maximum_request : Int64,
  requests : Int64,
) -> Int = "actql_bootstrap_extend_root_control"

///|
#borrow(backing)
extern "C" fn enter_root_control_ffi(backing : Backing) -> Int = "actql_bootstrap_enter_root_control"

///|
#borrow(backing)
extern "C" fn leave_root_control_ffi(backing : Backing) -> Int = "actql_bootstrap_leave_root_control"

///|
#borrow(backing)
extern "C" fn close_root_control_ffi(backing : Backing) -> Int = "actql_bootstrap_close_root_control"

///|
// Called in the original outer bootstrap lifetime, before this root Read is
// entered. The same reservation pays context and constructor storage first.
// Partial C creation stays registered on the existing backing, including an
// unknown outcome. Initial Request inventory certification remains separate.
#warnings("-unused_value")
fn[T] NativeHostBootstrap::prepare_root_control(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
  construction : NativeControlConstruction,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if scope.scopes <= 0L || self.root_control is Some(_) {
    return Err(AlreadyConsumed)
  }
  let bytes = root_control_quote_ffi(
    self.backing,
    construction.maximum_managed_request,
    construction.allocation_requests,
    1,
  )
  if bytes <= 0L {
    return Err(Unavailable)
  }
  let status = root_control_available_ffi(self.backing, bytes)
  if status != 0 {
    return Err(Physical(status))
  }
  let claim = match @resources.allocate_shared_capacity(self.capacity, bytes) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  let control : NativeRootControl[T] = {
    owner: Some(self),
    claim,
    bytes,
    reconciling: false,
    closing: false,
    physical_retired: false,
    closed: false,
  }
  self.root_control = Some(control)
  let status = prepare_root_control_ffi(
    self.backing,
    construction.maximum_managed_request,
    construction.allocation_requests,
  )
  if status == 0 {
    Ok(())
  } else {
    control.closing = true
    Err(Physical(status))
  }
}

///|
// A new independently certified cohort may coexist with every earlier alias.
// Only an acknowledged original finish can reconcile the previous claim;
// observed free pages or a lowered live count never authorize credit reuse.
// The caller can first acquire more actual root backing through grow_backing;
// the initial control prefix is therefore not a permanent growth ceiling.
#warnings("-unused_value")
fn[T] NativeHostBootstrap::extend_root_control(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
  construction : NativeControlConstruction,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard scope.scopes > 0L &&
    self.root_control is Some(control) &&
    control.owner is Some(selected) &&
    physical_equal(selected, self) &&
    !control.closing &&
    !control.reconciling else {
    return Err(Unavailable)
  }
  let additional = root_control_quote_ffi(
    self.backing,
    construction.maximum_managed_request,
    construction.allocation_requests,
    0,
  )
  if additional <= 0L || additional > 9223372036854775807L - control.bytes {
    return Err(Unavailable)
  }
  let status = root_control_available_ffi(self.backing, additional)
  if status != 0 {
    return Err(Physical(status))
  }
  let bytes = control.bytes + additional
  match
    @resources.grow_unborrowed_shared_allocation(
      self.capacity,
      control.claim,
      control.bytes,
      bytes,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => control.bytes = bytes
  }
  let status = extend_root_control_ffi(
    self.backing,
    construction.maximum_managed_request,
    construction.allocation_requests,
  )
  if status == 0 {
    Ok(())
  } else {
    // The same claim keeps every partially activated slab until actual close.
    control.closing = true
    Err(Physical(status))
  }
}

///|
// Scalar return is intentional: no managed Result constructor may run after
// C entry and consume an unquoted allocation before the cohort starts.
#warnings("-unused_value")
fn[T] NativeHostBootstrap::enter_root_control(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
) -> Bool {
  match self.require_borrow_current(original, scope) {
    Err(_) => return false
    Ok(_) => ()
  }
  guard scope.scopes > 0L &&
    self.root_control is Some(control) &&
    control.owner is Some(selected) &&
    physical_equal(selected, self) &&
    !control.closing &&
    !control.reconciling else {
    return false
  }
  enter_root_control_ffi(self.backing) == 0
}

///|
#warnings("-unused_value")
fn[T] NativeHostBootstrap::leave_root_control(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) {
    return Err(ForeignOriginal)
  }
  let status = leave_root_control_ffi(self.backing)
  if status == 0 {
    Ok(())
  } else {
    Err(Physical(status))
  }
}

///|
// Logical stop of this context's sole original user is not a physical ACK.
// Actual escaped controls keep the same context, claim and root mapping live.
fn[T] NativeHostBootstrap::close_root_control(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) {
    return Err(ForeignOriginal)
  }
  guard self.root_control is Some(control) else { return Ok(()) }
  if control.closed {
    return Ok(())
  }
  if control.reconciling {
    return Err(ReadersPending)
  }
  control.closing = true
  if !control.physical_retired {
    let status = close_root_control_ffi(self.backing)
    if status != 0 {
      return Err(Physical(status))
    }
    control.physical_retired = true
  }
  match @resources.retire_shared_capacity(control.claim) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match @resources.release_shared_capacity(control.claim) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => {
      control.closed = true
      control.owner = None
    }
  }
  Ok(())
}

///|
#borrow(backing, domain)
extern "C" fn request_control_scope_ffi(
  backing : Backing,
  domain : PhysicalExtentDomain,
) -> Int = "actql_bootstrap_request_control_scope"

///|
#borrow(backing)
extern "C" fn root_control_generation_ffi(backing : Backing) -> Int64 = "actql_bootstrap_root_control_generation"

///|
#borrow(backing)
extern "C" fn finish_root_control_cohort_ffi(
  backing : Backing,
  generation : Int64,
) -> Int64 = "actql_bootstrap_finish_root_control_cohort"

///|
// Private until an actual caller's complete fixed constructor certificate is
// selected. This is the existing control context's cleanup, not a new Owner.
#warnings("-unused_value")
fn[T] NativeHostBootstrap::finish_root_control_cohort(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard scope.scopes > 0L &&
    self.root_control is Some(control) &&
    control.owner is Some(selected) &&
    physical_equal(selected, self) &&
    !control.closing &&
    !control.reconciling else {
    return Err(Unavailable)
  }
  control.reconciling = true
  defer {
    control.reconciling = false
  }
  let generation = root_control_generation_ffi(self.backing)
  if generation <= 0L {
    return Err(Unavailable)
  }
  let remaining = finish_root_control_cohort_ffi(self.backing, generation)
  if remaining <= 0L {
    // Any partial/unknown physical finish remains on this exact claim. The
    // original close path, never a fresh cohort, owns subsequent cleanup.
    control.closing = true
    return Err(Physical(remaining.to_int()))
  }
  if remaining > control.bytes {
    control.closing = true
    return Err(Unavailable)
  }
  match
    @resources.reconcile_unborrowed_shared_allocation_after_cleanup(
      self.capacity,
      control.claim,
      control.bytes,
      remaining,
    ) {
    Err(issue) => {
      control.closing = true
      Err(Resource(issue))
    }
    Ok(_) => {
      control.bytes = remaining
      Ok(())
    }
  }
}
