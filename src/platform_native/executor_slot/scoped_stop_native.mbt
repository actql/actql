///|
// The anchor is a distinct open description of the original slot inode. It
// pins identity without retaining the holder's inherited lock description.
priv type NativeExecutorSlotAnchor

///|
#borrow(path)
extern "C" fn scoped_anchor_open_ffi(
  descriptor : Int,
  path : Bytes,
  length : Int,
) -> NativeExecutorSlotAnchor = "actql_executor_slot_anchor_open"

///|
#borrow(anchor)
extern "C" fn scoped_anchor_status_ffi(
  anchor : NativeExecutorSlotAnchor,
) -> Int = "actql_executor_slot_anchor_status"

///|
#borrow(anchor)
extern "C" fn scoped_anchor_thread_ffi(
  anchor : NativeExecutorSlotAnchor,
) -> Int = "actql_executor_slot_anchor_thread_current"

///|
#borrow(anchor, path)
extern "C" fn scoped_anchor_current_ffi(
  anchor : NativeExecutorSlotAnchor,
  path : Bytes,
  length : Int,
  require_pin : Int,
) -> Int = "actql_executor_slot_anchor_current"

///|
#borrow(anchor, path)
extern "C" fn scoped_anchor_pin_ffi(
  anchor : NativeExecutorSlotAnchor,
  path : Bytes,
  length : Int,
) -> Int = "actql_executor_slot_anchor_pin"

///|
#borrow(anchor)
extern "C" fn scoped_anchor_close_ffi(anchor : NativeExecutorSlotAnchor) -> Int = "actql_executor_slot_anchor_close"

///|
// This is process/slot custody, not permission, capacity, a Store ACK or a
// region cleanup ACK. The trusted caller retains the holder before spawn.
struct NativeScopedExecutorHolder {
  original : NativeExecutorSlot
  anchor : NativeExecutorSlotAnchor
  preparation_issue : NativeExecutorSlotIssue?
  mut attempted : Bool
  mut child : NativeExecutorSlotChild?
  mut channel : NativeHolderChannel?
  mut duplex : NativeScopedDuplexTransport?
  mut input : Int
  mut output : Int
  mut partial_close_unknown : Bool
  mut parent_close_unknown : Bool
  mut stop : NativeScopedExecutorStop?
  mut closed : Bool
}

///|
pub(all) enum NativeScopedExecutorPreparation {
  Ready(NativeScopedExecutorHolder)
  Refused(NativeScopedExecutorHolder, NativeExecutorSlotIssue)
}

///|
// No back-reference to holder: its retained stop and these original aliases
// form no ARC cycle. The expected holder is required at each current check.
struct NativeScopedExecutorStop {
  original : NativeExecutorSlot
  anchor : NativeExecutorSlotAnchor
  child : NativeExecutorSlotChild
  transport : NativeScopedStopTransport
  mut closed : Bool
  mut close_unknown : Bool
}

///|
fn scoped_slot_issue(status : Int) -> NativeExecutorSlotIssue {
  match status {
    1 => Busy
    2 => Replaced
    -2 => Closed
    -3 => OpenFailed
    _ => LockFailed
  }
}

///|
/// Thread-confined, synchronous preparation of an already held original.
/// A refused preparation returns the same carrier for its own cleanup.
pub fn NativeExecutorSlot::prepare_scoped_holder(
  self : NativeExecutorSlot,
) -> NativeScopedExecutorPreparation {
  let current = self.verify_current_hold()
  let path = @utf8.encode(self.path)
  let anchor = scoped_anchor_open_ffi(
    if current is Ok(_) {
      self.descriptor
    } else {
      -1
    },
    path,
    path.length(),
  )
  let issue = match current {
    Err(issue) => Some(issue)
    Ok(_) => {
      let status = scoped_anchor_status_ffi(anchor)
      if status == 0 {
        None
      } else {
        Some(scoped_slot_issue(status))
      }
    }
  }
  let holder = {
    original: self,
    anchor,
    preparation_issue: issue,
    attempted: false,
    child: None,
    channel: None,
    duplex: None,
    input: -1,
    output: -1,
    partial_close_unknown: false,
    parent_close_unknown: false,
    stop: None,
    closed: false,
  }
  match issue {
    None => Ready(holder)
    Some(issue) => Refused(holder, issue)
  }
}

///|
/// This observes preparation only. It grants neither launch nor resources.
pub fn NativeScopedExecutorHolder::require_prepared(
  self : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  if self.closed || self.attempted {
    return Err(Closed)
  }
  if self.preparation_issue is Some(issue) {
    return Err(issue)
  }
  match self.original.verify_current_hold() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
/// Exactly one attempt. An error may retain an actual child (for example an
/// unconfirmed parent descriptor close); it is never proof of not-started.
pub fn NativeScopedExecutorHolder::spawn_with_channel(
  self : NativeScopedExecutorHolder,
  executable : String,
  arguments : Array[String],
) -> Result[Unit, NativeExecutorSlotIssue] {
  match self.require_prepared() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.duplex is Some(_) {
    return Err(InvalidConfiguration)
  }
  self.attempted = true
  let ends = open_channel_ffi()
  if ends < 0 {
    return Err(SpawnFailed)
  }
  self.input = ends >> 16
  self.output = ends & 0xFFFF
  let child = match
    self.original.spawn_holder_reading(
      executable,
      arguments,
      self.input,
      scoped=Some(self),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  self.channel = Some({
    descriptor: self.output,
    inspection_descriptor: self.input,
    child,
    pending_frame: None,
    offset: 0,
    close_unknown: false,
  })
  self.input = -1
  self.output = -1
  if self.parent_close_unknown {
    Err(LockFailed)
  } else {
    Ok(())
  }
}

///|
/// Original opaque aliases only; no PID or DATA can construct this holder.
pub fn NativeScopedExecutorHolder::child(
  self : NativeScopedExecutorHolder,
) -> Result[NativeExecutorSlotChild, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  match self.child {
    Some(value) => Ok(value)
    None => Err(InvalidConfiguration)
  }
}

///|
pub fn NativeScopedExecutorHolder::channel(
  self : NativeScopedExecutorHolder,
) -> Result[NativeHolderChannel, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  match self.channel {
    Some(value) => Ok(value)
    None => Err(InvalidConfiguration)
  }
}

///|
/// Nonblocking: actual wait of this child, its original Channel cleanup and
/// reacquisition of the pinned original inode are independent required facts.
/// The pin remains held through the caller's region/FD cleanup acknowledgement.
pub fn NativeScopedExecutorHolder::poll_stop(
  self : NativeScopedExecutorHolder,
) -> Result[NativeScopedExecutorStop?, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  if self.closed {
    return Err(Closed)
  }
  if self.parent_close_unknown || self.partial_close_unknown {
    return Err(LockFailed)
  }
  if self.stop is Some(stop) {
    match stop.require_current(self) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return Ok(Some(stop))
  }
  if self.duplex is Some(transport) {
    return self.poll_duplex_stop(transport)
  }
  let child = match self.child() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let channel = match self.channel() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match child.wait(false) {
    Err(issue) => return Err(issue)
    Ok(None) => return Ok(None)
    Ok(Some(_)) => ()
  }
  if !channel.close() {
    return Err(LockFailed)
  }
  let path = @utf8.encode(self.original.path)
  let status = scoped_anchor_pin_ffi(self.anchor, path, path.length())
  if status == 1 {
    return Ok(None)
  }
  if status != 0 {
    return Err(scoped_slot_issue(status))
  }
  // These private bytes were never exported and no physical Channel user
  // remains. Their retirement does not settle any relayed operation outcome.
  channel.pending_frame = None
  channel.offset = 0
  let stop = {
    original: self.original,
    anchor: self.anchor,
    child,
    transport: HolderChannel(channel),
    closed: false,
    close_unknown: false,
  }
  self.stop = Some(stop)
  Ok(Some(stop))
}

///|
/// Require the holder captured by the existing region Owner before spawn.
/// Same path/PID/file metadata on a different holder is insufficient.
pub fn NativeScopedExecutorStop::require_current(
  self : NativeScopedExecutorStop,
  expected : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  if !physical_equal(expected.anchor, self.anchor) ||
    !physical_equal(expected.original, self.original) {
    return Err(NotHeld)
  }
  if self.closed || self.close_unknown || expected.closed {
    return Err(Closed)
  }
  if !(expected.stop is Some(original) && physical_equal(original, self)) ||
    !(expected.child is Some(child) && physical_equal(child, self.child)) ||
    !scoped_stop_transport_matches(expected, self.transport) ||
    expected.parent_close_unknown ||
    expected.partial_close_unknown {
    return Err(NotHeld)
  }
  match self.child.wait(false) {
    Err(issue) => return Err(issue)
    Ok(None) => return Err(Busy)
    Ok(Some(_)) => ()
  }
  if !scoped_stop_transport_closed(self.transport) {
    return Err(Busy)
  }
  let path = @utf8.encode(self.original.path)
  let status = scoped_anchor_current_ffi(self.anchor, path, path.length(), 1)
  if status == 0 {
    Ok(())
  } else {
    Err(scoped_slot_issue(status))
  }
}

///|
/// Call only after the original exclusive region/view/FD cleanup ACK. A lost
/// close observation is sticky; never retry a consumed raw descriptor.
pub fn NativeScopedExecutorStop::close(self : NativeScopedExecutorStop) -> Bool {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return false
  }
  if self.closed {
    return true
  }
  if self.close_unknown {
    return false
  }
  if scoped_anchor_close_ffi(self.anchor) != 0 {
    self.close_unknown = true
    return false
  }
  self.closed = true
  true
}

///|
/// Partial/unstarted cleanup only. A live or stopped child still requires
/// explicit poll_stop and the caller's later physical cleanup acknowledgement.
/// The pre-spawn original Slot remains independently owned by its caller.
pub fn NativeScopedExecutorHolder::cleanup(
  self : NativeScopedExecutorHolder,
) -> Bool {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return false
  }
  if self.closed {
    return true
  }
  if self.child is Some(_) {
    if self.stop is Some(stop) && stop.closed && !stop.close_unknown {
      self.closed = true
      return true
    }
    return false
  }
  if self.duplex is Some(transport) && !transport.cleanup_unstarted(self) {
    return false
  }
  if self.output >= 0 {
    let original = self.output
    self.output = -1
    if slot_close_ffi(original) != 0 {
      self.partial_close_unknown = true
    }
  }
  if self.input >= 0 {
    let original = self.input
    self.input = -1
    if slot_close_ffi(original) != 0 {
      self.partial_close_unknown = true
    }
  }
  if self.partial_close_unknown || self.parent_close_unknown {
    return false
  }
  if scoped_anchor_close_ffi(self.anchor) != 0 {
    self.partial_close_unknown = true
    return false
  }
  self.closed = true
  true
}
