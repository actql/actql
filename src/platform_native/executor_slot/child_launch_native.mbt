///|
priv type NativeScopedChildDescriptor

///|
extern "C" fn capture_selected_child_ffi(
  source : Int,
) -> NativeScopedChildDescriptor = "actql_executor_slot_capture_selected_child"

///|
#borrow(record)
extern "C" fn selected_child_current_ffi(
  record : NativeScopedChildDescriptor,
) -> Int = "actql_executor_slot_selected_child_current"

///|
#borrow(record)
extern "C" fn selected_child_close_ffi(
  record : NativeScopedChildDescriptor,
) -> Int = "actql_executor_slot_selected_child_close"

///|
#borrow(record)
extern "C" fn selected_child_closed_ffi(
  record : NativeScopedChildDescriptor,
) -> Int = "actql_executor_slot_selected_child_closed"

///|
#borrow(executable, arguments, record, environment)
extern "C" fn spawn_selected_duplex_ffi(
  executable : Bytes,
  executable_length : Int,
  arguments : Bytes,
  arguments_length : Int,
  descriptor : Int,
  target_descriptor : Int,
  input : Int,
  output : Int,
  record : NativeScopedChildDescriptor,
  environment : Bytes,
  environment_length : Int,
) -> Int = "actql_executor_slot_spawn_selected_duplex"

///|
// Parent-owned immutable physical launch inputs, never a resource or permission
// issuer. There is no caller-visible constructor from a descriptor/serialized ID.
priv struct NativeScopedDuplexChildLaunch {
  original : NativeExecutorSlot
  anchor : NativeExecutorSlotAnchor
  resource : NativeScopedChildDescriptor
  executable : Bytes
  arguments : Bytes
  environment : Bytes
}

///|
fn selected_child_issue(status : Int) -> NativeExecutorSlotIssue {
  match status {
    -2 => Closed
    -3 => OpenFailed
    _ => LockFailed
  }
}

///|
fn selected_child_environment(
  environment : Array[(String, String)],
) -> Result[Bytes, NativeExecutorSlotIssue] {
  if environment.length() > 4 {
    return Err(InvalidConfiguration)
  }
  let seen : Array[Int] = []
  let block : Array[Byte] = []
  for (name, value) in environment {
    let key = match name {
      "LANG" => 0
      "LC_ALL" => 1
      "LC_CTYPE" => 2
      "TMPDIR" => 3
      _ => return Err(InvalidConfiguration)
    }
    let bytes = @utf8.encode(value)
    if seen.contains(key) || value.contains("\u{0}") || bytes.length() > 4096 {
      return Err(InvalidConfiguration)
    }
    seen.push(key)
    for byte in @utf8.encode(name + "=") {
      block.push(byte)
    }
    for byte in bytes {
      block.push(byte)
    }
    block.push((0 : Byte))
  }
  Ok(Bytes::from_array(block))
}

///|
/// Trusted physical preparation only. The existing installer/region Owner
/// supplies and retains the same original backing FD and current loan/recipe.
/// This Holder owns only a new CLOEXEC alias and frozen argv/selected env.
/// The caller must fund that parent holding independently; intake bounds do not.
pub fn NativeScopedExecutorHolder::prepare_duplex_child(
  self : NativeScopedExecutorHolder,
  executable : String,
  arguments : Array[String],
  backing_descriptor : Int,
  environment : Array[(String, String)],
) -> Result[Unit, NativeExecutorSlotIssue] {
  match self.require_prepared() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.child_launch is Some(_) ||
    !valid_path(executable) ||
    !executable.has_prefix("/") ||
    arguments.length() > 255 ||
    backing_descriptor < 0 ||
    backing_descriptor == self.original.descriptor {
    return Err(InvalidConfiguration)
  }
  let transport = match self.duplex {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  guard transport.borrowed is Some(borrowed) else { return Err(Busy) }
  match borrowed.require_current(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  for role in 0..<4 {
    if backing_descriptor == duplex_descriptor_ffi(transport.resource, role) {
      return Err(InvalidConfiguration)
    }
  }
  let encoded_environment = match selected_child_environment(environment) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let block : Array[Byte] = []
  for argument in [executable, ..arguments] {
    if argument.contains("\u{0}") {
      return Err(InvalidConfiguration)
    }
    for byte in @utf8.encode(argument) {
      block.push(byte)
    }
    block.push((0 : Byte))
  }
  let launch = {
    original: self.original,
    anchor: self.anchor,
    resource: capture_selected_child_ffi(backing_descriptor),
    executable: @utf8.encode(executable),
    arguments: Bytes::from_array(block),
    environment: encoded_environment,
  }
  // Even refused physical capture remains in the original pre-retained Holder.
  self.child_launch = Some(launch)
  let status = selected_child_current_ffi(launch.resource)
  if status == 0 {
    Ok(())
  } else {
    Err(selected_child_issue(status))
  }
}

///|
/// One attempt using only the prepared original snapshot. Child FD4 is fixed;
/// the selected environment, including an empty selection, never merges ambient
/// process values. Errors may retain an actual child or an unconfirmed close.
pub fn NativeScopedExecutorHolder::spawn_prepared_duplex(
  self : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  match self.require_prepared() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let launch = match self.child_launch {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  if !physical_equal(launch.original, self.original) ||
    !physical_equal(launch.anchor, self.anchor) {
    return Err(NotHeld)
  }
  let transport = match self.duplex {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  guard transport.borrowed is Some(borrowed) else { return Err(Busy) }
  match borrowed.require_current(self) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let status = selected_child_current_ffi(launch.resource)
  if status != 0 {
    return Err(selected_child_issue(status))
  }
  let input = duplex_descriptor_ffi(transport.resource, 0)
  let output = duplex_descriptor_ffi(transport.resource, 2)
  if input < 0 || output < 0 {
    return Err(Closed)
  }
  self.attempted = true
  let pid = spawn_selected_duplex_ffi(
    launch.executable,
    launch.executable.length(),
    launch.arguments,
    launch.arguments.length(),
    self.original.descriptor,
    NATIVE_EXECUTOR_SLOT_INHERITED_FD,
    input,
    output,
    launch.resource,
    launch.environment,
    launch.environment.length(),
  )
  let spawned = self.original.record_spawn_result(pid, Some(self))
  self.duplex_spawn_returned = true
  match spawned {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Both known parent copies retire even if one close becomes Unknown. The
  // same retained carrier and actual child then remain for composite cleanup.
  let child_closed = selected_child_close_ffi(launch.resource) == 0
  let transport_closed = duplex_close_child_ffi(transport.resource) == 0
  if !child_closed || !transport_closed || self.parent_close_unknown {
    Err(LockFailed)
  } else {
    Ok(())
  }
}
