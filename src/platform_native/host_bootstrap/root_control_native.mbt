///|
// Source-owned control blocks, not SDK policy, caller byte grants or a new
// constructor-proof gate. Initial fixed bookkeeping uses the Host/domain's
// finite basis; larger actual work extends this same owned cohort before entry.
priv struct NativeControlConstruction {
  maximum_managed_request : Int64
  allocation_requests : Int64
}

///|
priv struct NativeRootControl[T] {
  mut owner : NativeHostBootstrap[T]?
  mut scope : NativeBootstrapBorrow[T]?
  claim : @resources.SharedAllocation
  mut bytes : Int64
  mut reconciling : Bool
  mut cohort_finished : Bool
  mut active : Bool
  mut entered_parent : Bool
  mut bookkeeping_pending : Bool
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
#borrow(backing)
extern "C" fn root_control_basis_maximum_ffi(backing : Backing) -> Int64 = "actql_bootstrap_root_control_basis_maximum"

///|
/// Prepare fixed bookkeeping before selecting a payload from the same Host.
/// Scope identity/current is checked by the existing Owner. No caller numeric
/// quotation can substitute for the original ABI/provider or fund a new Root.
pub fn[T] NativeHostBootstrap::prepare_backed_read_control(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if scope.scopes <= 0L {
    return Err(Unavailable)
  }
  if self.root_control is Some(control) {
    guard control.scope is Some(selected) &&
      physical_equal(selected, scope) &&
      !control.closing &&
      !control.closed else {
      return Err(Unavailable)
    }
    if control.cohort_finished {
      // Only the actual preceding finish can select another fixed block.
      // Its escaped aliases remain charged on this SAME claim; capacity and
      // physical acquisition still precede the next caller's entry.
      let maximum = root_control_basis_maximum_ffi(self.backing)
      return self.extend_root_control(original, scope, {
        maximum_managed_request: maximum,
        allocation_requests: 64L,
      })
    }
    return Ok(())
  }
  if !self.children.is_empty() || !self.delegations.is_empty() {
    return Err(AlreadyConsumed)
  }
  let maximum = root_control_basis_maximum_ffi(self.backing)
  if maximum <= 0L {
    return Err(Unavailable)
  }
  // A finite block of ordinary bookkeeping, priced/aligned by the actual C
  // supplier. Exhaustion is a refusal; it never admits a larger child budget.
  let construction : NativeControlConstruction = {
    maximum_managed_request: maximum,
    allocation_requests: 64L,
  }
  let bytes = root_control_quote_ffi(self.backing, maximum, 64L, 1)
  if bytes <= 0L || bytes > self.supplier.control_envelope_bytes {
    return Err(Unavailable)
  }
  self.prepare_root_control(original, scope, construction)
}

///|
/// Enter the already prepared fixed control on the original borrower. Scalar
/// return avoids constructing a result between physical entry and its caller.
/// No caller quantity, new context, permission or reservation is issued here.
pub fn[T] NativeHostBootstrap::enter_backed_read_control(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
) -> Bool {
  self.enter_root_control(original, scope)
}

///|
/// Finish the original preparation cohort before leaving its parent scope.
/// Failure retains the same active/control/claim; it is not a child stop ACK.
pub fn[T] NativeHostBootstrap::leave_backed_read_control(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) ||
    !physical_equal(scope.owner, self) {
    return Err(ForeignOriginal)
  }
  guard self.root_control is Some(control) &&
    control.scope is Some(selected) &&
    physical_equal(selected, scope) else {
    return Err(ForeignOriginal)
  }
  if control.active {
    match self.leave_root_control(original) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !control.cohort_finished {
    self.finish_root_control_cohort(original, scope)
  } else {
    Ok(())
  }
}

///|
// Called in the original outer bootstrap lifetime, before this root Read is
// entered. The same reservation pays context and constructor storage first.
// Partial C creation stays registered on the existing backing, including an
// unknown outcome. Dynamic payload geometry remains with its original caller.
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
    scope: Some(scope),
    claim,
    bytes,
    reconciling: false,
    cohort_finished: false,
    active: false,
    entered_parent: false,
    bookkeeping_pending: false,
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
// The next fixed cohort may coexist with every earlier alias.
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
  cleanup? : Bool = false,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard scope.scopes > 0L &&
    self.root_control is Some(control) &&
    control.owner is Some(selected) &&
    physical_equal(selected, self) &&
    (!control.closing || cleanup) &&
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
    control.cohort_finished = false
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
  cleanup? : Bool = false,
) -> Bool {
  match self.require_borrow_current(original, scope) {
    Err(_) => return false
    Ok(_) => ()
  }
  guard scope.scopes > 0L &&
    self.root_control is Some(control) &&
    control.owner is Some(selected) &&
    physical_equal(selected, self) &&
    (!control.closing || cleanup) &&
    !control.reconciling else {
    return false
  }
  let status = enter_root_control_ffi(self.backing)
  if status == 0 {
    control.active = true
    true
  } else {
    false
  }
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
    if self.root_control is Some(control) {
      control.active = false
    }
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
  match self.finish_failed_backed_read_bookkeeping(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
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
      control.scope = None
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
// Finish this actual cohort after its callers leave. Existing escaped aliases
// keep their original pages charged; this creates no new read or cleanup ACK.
#warnings("-unused_value")
fn[T] NativeHostBootstrap::finish_root_control_cohort(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
  cleanup? : Bool = false,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard scope.scopes > 0L &&
    self.root_control is Some(control) &&
    control.owner is Some(selected) &&
    physical_equal(selected, self) &&
    (!control.closing || cleanup) &&
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
      control.cohort_finished = true
      Ok(())
    }
  }
}

///|
// Unwind only an enclosing control entrance owned by a failed bookkeeping
// operation. This never leaves a live child Read or re-executes its action.
// Failed physical exits retain these exact scope/control aliases for retry.
fn[T] NativeHostBootstrap::finish_failed_backed_read_bookkeeping(
  self : NativeHostBootstrap[T],
  original : T,
) -> Result[Unit, NativeBootstrapIssue] {
  if !physical_equal(self.supplier.original, original) {
    return Err(ForeignOriginal)
  }
  guard self.root_control is Some(control) else { return Ok(()) }
  if !control.closing || control.closed || !control.bookkeeping_pending {
    return Ok(())
  }
  guard control.owner is Some(owner) &&
    physical_equal(owner, self) &&
    control.scope is Some(scope) &&
    physical_equal(scope.owner, self) else {
    return Err(ForeignOriginal)
  }
  if control.active {
    match self.leave_root_control(original) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !control.cohort_finished {
    match self.finish_root_control_cohort(original, scope, cleanup=true) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if control.entered_parent {
    match self.leave_borrow_scope(original, scope) {
      Err(issue) => return Err(issue)
      Ok(_) => control.entered_parent = false
    }
  }
  control.bookkeeping_pending = false
  Ok(())
}

///|
// Fixed ordinary bookkeeping on the SAME retained Root/control/scope. Payload
// constructors and their actual domain working requests stay with the Read.
fn[T] NativeHostBootstrap::with_backed_read_bookkeeping(
  self : NativeHostBootstrap[T],
  original : T,
  action : () -> Result[Unit, NativeBackedExecutionIssue],
  cleanup? : Bool = false,
) -> Result[Unit, NativeBackedExecutionIssue] {
  // Existing imported profiles keep their original entrance. The ordinary
  // Resident installs enclosing control before selecting its payload.
  guard self.root_control is Some(control) else { return action() }
  guard control.scope is Some(scope) &&
    (!control.closing || cleanup) &&
    !control.closed &&
    !control.active &&
    !control.entered_parent &&
    !control.bookkeeping_pending else {
    return Err(Bootstrap(Unavailable))
  }
  if scope.scopes == 0L {
    match self.enter_borrow_scope(original, scope) {
      Err(issue) => return Err(Bootstrap(issue))
      Ok(_) => control.entered_parent = true
    }
  }
  control.bookkeeping_pending = true
  if control.cohort_finished {
    let maximum = root_control_basis_maximum_ffi(self.backing)
    match
      self.extend_root_control(
        original,
        scope,
        { maximum_managed_request: maximum, allocation_requests: 64L, },
        cleanup~,
      ) {
      Err(issue) => {
        control.closing = true
        return Err(Bootstrap(issue))
      }
      Ok(_) => ()
    }
  }
  if !self.enter_root_control(original, scope, cleanup~) {
    control.closing = true
    return Err(Bootstrap(Unavailable))
  }
  let result = action()
  match self.leave_root_control(original) {
    Err(issue) => {
      control.closing = true
      return match result {
        Err(original) => Err(original)
        Ok(_) => Err(Bootstrap(issue))
      }
    }
    Ok(_) => ()
  }
  match self.finish_root_control_cohort(original, scope, cleanup~) {
    Err(issue) => {
      control.closing = true
      return match result {
        Err(original) => Err(original)
        Ok(_) => Err(Bootstrap(issue))
      }
    }
    Ok(_) => ()
  }
  if control.entered_parent {
    match self.leave_borrow_scope(original, scope) {
      Err(issue) => {
        control.closing = true
        return match result {
          Err(original) => Err(original)
          Ok(_) => Err(Bootstrap(issue))
        }
      }
      Ok(_) => control.entered_parent = false
    }
  }
  control.bookkeeping_pending = false
  result
}
