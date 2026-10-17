///|
priv type NativeScopedDuplexResource

///|
extern "C" fn duplex_open_ffi() -> NativeScopedDuplexResource = "actql_executor_slot_duplex_open"

///|
#borrow(resource)
extern "C" fn duplex_current_ffi(resource : NativeScopedDuplexResource) -> Int = "actql_executor_slot_duplex_current"

///|
#borrow(resource)
extern "C" fn duplex_descriptor_ffi(
  resource : NativeScopedDuplexResource,
  role : Int,
) -> Int = "actql_executor_slot_duplex_descriptor"

///|
#borrow(resource)
extern "C" fn duplex_close_child_ffi(
  resource : NativeScopedDuplexResource,
) -> Int = "actql_executor_slot_duplex_close_child"

///|
#borrow(resource)
extern "C" fn duplex_close_ffi(resource : NativeScopedDuplexResource) -> Int = "actql_executor_slot_duplex_close"

///|
#borrow(resource)
extern "C" fn duplex_closed_ffi(resource : NativeScopedDuplexResource) -> Int = "actql_executor_slot_duplex_closed"

///|
priv enum NativeScopedStopTransport {
  HolderChannel(NativeHolderChannel)
  DuplexTransport(NativeScopedDuplexTransport)
}

///|
// All aliases stay in the parent's original holding, outside the exclusive
// child mapping. A transport holds no Host permission or capacity declaration.
struct NativeScopedDuplexTransport {
  original : NativeExecutorSlot
  anchor : NativeExecutorSlotAnchor
  resource : NativeScopedDuplexResource
  mut borrowed : NativeScopedDuplexBorrow?
  mut closed : Bool
}

///|
// No back-reference to transport: its retained borrow forms no ARC cycle.
struct NativeScopedDuplexBorrow {
  original : NativeExecutorSlot
  anchor : NativeExecutorSlotAnchor
  resource : NativeScopedDuplexResource
  mut returned : Bool
}

///|
fn duplex_issue(status : Int) -> NativeExecutorSlotIssue {
  match status {
    -2 => Closed
    -3 => OpenFailed
    _ => LockFailed
  }
}

///|
fn NativeScopedDuplexTransport::require_identity(
  self : NativeScopedDuplexTransport,
  expected : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  if !physical_equal(expected.original, self.original) ||
    !physical_equal(expected.anchor, self.anchor) ||
    !(expected.duplex is Some(original) && physical_equal(original, self)) {
    return Err(NotHeld)
  }
  if expected.closed {
    return Err(Closed)
  }
  Ok(())
}

///|
fn NativeScopedDuplexTransport::require_original(
  self : NativeScopedDuplexTransport,
  expected : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  match self.require_identity(expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.closed {
    return Err(Closed)
  }
  let path = @utf8.encode(self.original.path)
  let status = scoped_anchor_current_ffi(self.anchor, path, path.length(), 0)
  if status == 0 {
    Ok(())
  } else {
    Err(scoped_slot_issue(status))
  }
}

///|
/// Capture four endpoints before borrowing or launch. Refusal leaves every
/// known endpoint/unknown close in this same already-retained Holder.
pub fn NativeScopedExecutorHolder::prepare_duplex(
  self : NativeScopedExecutorHolder,
) -> Result[NativeScopedDuplexTransport, NativeExecutorSlotIssue] {
  self.prepare_duplex_using(duplex_open_ffi)
}

///|
// The physical factory is private; only the finite Owner allocation-failure
// fixture selects a different actual-pipe factory.
fn NativeScopedExecutorHolder::prepare_duplex_using(
  self : NativeScopedExecutorHolder,
  open : () -> NativeScopedDuplexResource,
) -> Result[NativeScopedDuplexTransport, NativeExecutorSlotIssue] {
  match self.require_prepared() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.duplex is Some(_) {
    return Err(InvalidConfiguration)
  }
  let transport = {
    original: self.original,
    anchor: self.anchor,
    resource: open(),
    borrowed: None,
    closed: false,
  }
  self.duplex = Some(transport)
  let status = duplex_current_ffi(transport.resource)
  if status == 0 {
    Ok(transport)
  } else {
    Err(duplex_issue(status))
  }
}

///|
/// One original parent borrow only. Returning it never permits another borrow
/// or settles the child, channel metadata, exclusive region or WorkspaceLoan.
pub fn NativeScopedDuplexTransport::borrow_transport(
  self : NativeScopedDuplexTransport,
  expected : NativeScopedExecutorHolder,
) -> Result[NativeScopedDuplexBorrow, NativeExecutorSlotIssue] {
  match self.require_original(expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if expected.attempted || self.borrowed is Some(_) {
    return Err(Busy)
  }
  let status = duplex_current_ffi(self.resource)
  if status != 0 {
    return Err(duplex_issue(status))
  }
  let borrowed = {
    original: self.original,
    anchor: self.anchor,
    resource: self.resource,
    returned: false,
  }
  self.borrowed = Some(borrowed)
  Ok(borrowed)
}

///|
fn NativeScopedDuplexBorrow::original_transport(
  self : NativeScopedDuplexBorrow,
  expected : NativeScopedExecutorHolder,
) -> Result[NativeScopedDuplexTransport, NativeExecutorSlotIssue] {
  let transport = match expected.duplex {
    Some(value) => value
    None => return Err(NotHeld)
  }
  match transport.require_identity(expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(self.original, transport.original) ||
    !physical_equal(self.anchor, transport.anchor) ||
    !physical_equal(self.resource, transport.resource) ||
    !(transport.borrowed is Some(original) && physical_equal(original, self)) {
    return Err(NotHeld)
  }
  Ok(transport)
}

///|
/// Same-holder physical transport currentness only. Resource/permission and
/// the channel's in-flight-use fence remain with their original Owners.
pub fn NativeScopedDuplexBorrow::require_current(
  self : NativeScopedDuplexBorrow,
  expected : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  let transport = match self.original_transport(expected) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if self.returned {
    return Err(Closed)
  }
  match transport.require_original(expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = duplex_current_ffi(self.resource)
  if status != 0 {
    return Err(duplex_issue(status))
  }
  if duplex_descriptor_ffi(self.resource, 1) < 0 ||
    duplex_descriptor_ffi(self.resource, 3) < 0 {
    Err(Closed)
  } else {
    Ok(())
  }
}

///|
/// Physical facts for the trusted channel caller: parent stdin writer first,
/// parent stdout reader second. No caller-supplied numbers can mint this view.
pub fn NativeScopedDuplexBorrow::parent_descriptors(
  self : NativeScopedDuplexBorrow,
  expected : NativeScopedExecutorHolder,
) -> Result[(Int, Int), NativeExecutorSlotIssue] {
  match self.require_current(expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let writer = duplex_descriptor_ffi(self.resource, 1)
  let reader = duplex_descriptor_ffi(self.resource, 3)
  if writer < 0 || reader < 0 {
    Err(Closed)
  } else {
    Ok((writer, reader))
  }
}

///|
/// The trusted channel Owner first fences new I/O and observes zero in-flight
/// uses. This returns only its endpoint borrow, never a physical cleanup ACK.
pub fn NativeScopedDuplexBorrow::return_transport(
  self : NativeScopedDuplexBorrow,
  expected : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  match self.original_transport(expected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.returned {
    return Ok(())
  }
  self.returned = true
  Ok(())
}

///|
pub fn NativeScopedExecutorHolder::spawn_duplex(
  self : NativeScopedExecutorHolder,
  executable : String,
  arguments : Array[String],
) -> Result[Unit, NativeExecutorSlotIssue] {
  match self.require_prepared() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.child_launch is Some(_) {
    return Err(InvalidConfiguration)
  }
  let transport = match self.duplex {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  guard transport.borrowed is Some(borrowed) && !borrowed.returned else {
    return Err(Busy)
  }
  let status = duplex_current_ffi(transport.resource)
  if status != 0 {
    return Err(duplex_issue(status))
  }
  let input = duplex_descriptor_ffi(transport.resource, 0)
  let output = duplex_descriptor_ffi(transport.resource, 2)
  if input < 0 || output < 0 {
    return Err(Closed)
  }
  self.attempted = true
  let spawned = self.original.spawn_holder_reading(
    executable,
    arguments,
    input,
    scoped=Some(self),
    output~,
  )
  // A returned synchronous call is distinct from an unresolved attempt. The
  // actual child is retained by spawn_holder_reading before this observation.
  self.duplex_spawn_returned = true
  match spawned {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if duplex_close_child_ffi(transport.resource) != 0 ||
    self.parent_close_unknown {
    Err(LockFailed)
  } else {
    Ok(())
  }
}

///|
fn NativeScopedDuplexTransport::cleanup_unstarted(
  self : NativeScopedDuplexTransport,
  expected : NativeScopedExecutorHolder,
) -> Bool {
  if self.require_identity(expected) is Err(_) {
    return false
  }
  if self.borrowed is Some(borrowed) && !borrowed.returned {
    return false
  }
  if self.closed {
    return true
  }
  if duplex_close_ffi(self.resource) != 0 {
    return false
  }
  self.closed = true
  true
}

///|
fn NativeScopedExecutorHolder::poll_duplex_stop(
  self : NativeScopedExecutorHolder,
  transport : NativeScopedDuplexTransport,
) -> Result[NativeScopedExecutorStop?, NativeExecutorSlotIssue] {
  match transport.require_identity(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if transport.borrowed is Some(borrowed) && !borrowed.returned {
    return Err(Busy)
  }
  let child = match self.child() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The returned view can no longer issue I/O. Closing its original writer
  // also permits an EOF-waiting child to stop; exit is still observed below.
  if duplex_close_ffi(transport.resource) != 0 {
    return Err(LockFailed)
  }
  if self.child_launch is Some(launch) &&
    selected_child_close_ffi(launch.resource) != 0 {
    return Err(LockFailed)
  }
  match child.wait(false) {
    Err(issue) => return Err(issue)
    Ok(None) => return Ok(None)
    Ok(Some(_)) => ()
  }
  let path = @utf8.encode(self.original.path)
  let status = scoped_anchor_pin_ffi(self.anchor, path, path.length())
  if status == 1 {
    return Ok(None)
  }
  if status != 0 {
    return Err(scoped_slot_issue(status))
  }
  let stop = {
    original: self.original,
    anchor: self.anchor,
    child,
    transport: DuplexTransport(transport),
    closed: false,
    close_unknown: false,
  }
  self.stop = Some(stop)
  Ok(Some(stop))
}

///|
fn scoped_stop_transport_matches(
  expected : NativeScopedExecutorHolder,
  transport : NativeScopedStopTransport,
) -> Bool {
  match transport {
    HolderChannel(channel) =>
      expected.channel is Some(original) && physical_equal(original, channel)
    DuplexTransport(duplex) =>
      expected.duplex is Some(original) && physical_equal(original, duplex)
  }
}

///|
fn scoped_stop_transport_closed(transport : NativeScopedStopTransport) -> Bool {
  match transport {
    HolderChannel(channel) =>
      channel.descriptor < 0 &&
      channel.inspection_descriptor < 0 &&
      !channel.close_unknown &&
      channel.pending_frame is None
    DuplexTransport(duplex) =>
      duplex_closed_ffi(duplex.resource) == 0 &&
      !(duplex.borrowed is Some(borrowed) && !borrowed.returned)
  }
}
