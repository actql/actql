///|
#borrow(path)
extern "C" fn slot_open_ffi(path : Bytes, length : Int) -> Int = "actql_executor_slot_open"

///|
extern "C" fn slot_try_lock_ffi(descriptor : Int) -> Int = "actql_executor_slot_try_lock"

///|
#borrow(path)
extern "C" fn slot_verify_ffi(
  descriptor : Int,
  path : Bytes,
  length : Int,
) -> Int = "actql_executor_slot_verify"

///|
extern "C" fn slot_close_ffi(descriptor : Int) -> Int = "actql_executor_slot_close"

///|
#borrow(executable, arguments)
extern "C" fn slot_spawn_ffi(
  executable : Bytes,
  executable_length : Int,
  arguments : Bytes,
  arguments_length : Int,
  descriptor : Int,
  target_descriptor : Int,
) -> Int = "actql_executor_slot_spawn"

///|
extern "C" fn slot_wait_ffi(pid : Int, block : Int) -> Int = "actql_executor_slot_wait"

///|
extern "C" fn slot_signal_ffi(pid : Int, signal_number : Int) -> Int = "actql_executor_slot_signal"

///|
extern "C" fn current_executable_ffi() -> Bytes = "actql_executor_slot_current_executable"

///|
/// One Site executor slot: a private lock file that is never unlinked or
/// recreated while a Site runs. Every parent of the Site opens the same path.
struct NativeExecutorSlot {
  path : String
  mut descriptor : Int
}

///|
/// A process started as the slot holder. It holds the slot lock, and so do
/// its descendants, until the last of them exits.
struct NativeExecutorSlotChild {
  pid : Int
  mut exit : NativeExecutorSlotExit?
}

///|
fn valid_path(path : String) -> Bool {
  !path.is_empty() && path.length() <= 4096 && !path.contains("\u{0}")
}

///|
pub fn open_native_executor_slot(
  path : String,
) -> Result[NativeExecutorSlot, NativeExecutorSlotIssue] {
  if !valid_path(path) {
    return Err(InvalidConfiguration)
  }
  let encoded = @utf8.encode(path)
  let descriptor = slot_open_ffi(encoded, encoded.length())
  if descriptor < 0 {
    return Err(OpenFailed)
  }
  Ok({ path, descriptor, })
}

///|
/// Try to take the slot without waiting. `false` means another process (or a
/// descendant of an earlier holder) still holds it.
pub fn NativeExecutorSlot::try_acquire(
  self : NativeExecutorSlot,
) -> Result[Bool, NativeExecutorSlotIssue] {
  if self.descriptor < 0 {
    return Err(Closed)
  }
  match slot_try_lock_ffi(self.descriptor) {
    0 => Ok(true)
    1 => Ok(false)
    _ => Err(LockFailed)
  }
}

///|
/// Start `executable` as the slot holder. The caller must hold the slot. The
/// lock passes to the child through the inherited descriptor, and this
/// process then closes its own copy, so the slot is held without a gap by the
/// child and its descendants only. On a spawn failure the caller keeps the
/// slot and nothing was started.
pub fn NativeExecutorSlot::spawn_holder(
  self : NativeExecutorSlot,
  executable : String,
  arguments : Array[String],
) -> Result[NativeExecutorSlotChild, NativeExecutorSlotIssue] {
  if self.descriptor < 0 {
    return Err(Closed)
  }
  if !valid_path(executable) || arguments.length() > 63 {
    return Err(InvalidConfiguration)
  }
  match
    slot_verify_ffi(
      self.descriptor,
      @utf8.encode(self.path),
      @utf8.encode(self.path).length(),
    ) {
    0 => ()
    1 => return Err(Busy)
    2 => return Err(Replaced)
    _ => return Err(LockFailed)
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
  let encoded_executable = @utf8.encode(executable)
  let encoded_arguments = Bytes::from_array(block)
  let pid = slot_spawn_ffi(
    encoded_executable,
    encoded_executable.length(),
    encoded_arguments,
    encoded_arguments.length(),
    self.descriptor,
    NATIVE_EXECUTOR_SLOT_INHERITED_FD,
  )
  if pid <= 0 {
    return Err(SpawnFailed)
  }
  ignore(slot_close_ffi(self.descriptor))
  self.descriptor = -1
  Ok({ pid, exit: None, })
}

///|
/// In a started holder: confirm that the inherited descriptor is the current
/// slot file named by `path` and that this process holds its lock. A holder
/// that cannot confirm this must not claim or start execution.
pub fn inherited_native_executor_slot(
  path : String,
) -> Result[NativeExecutorSlot, NativeExecutorSlotIssue] {
  if !valid_path(path) {
    return Err(InvalidConfiguration)
  }
  let encoded = @utf8.encode(path)
  match
    slot_verify_ffi(
      NATIVE_EXECUTOR_SLOT_INHERITED_FD,
      encoded,
      encoded.length(),
    ) {
    0 => Ok({ path, descriptor: NATIVE_EXECUTOR_SLOT_INHERITED_FD, })
    1 => Err(NotHeld)
    2 => Err(Replaced)
    _ => Err(NotHeld)
  }
}

///|
/// Release this process's hold on the slot. Descendants that inherited the
/// same description keep holding it until they exit.
pub fn NativeExecutorSlot::close(self : NativeExecutorSlot) -> Bool {
  if self.descriptor < 0 {
    return false
  }
  let closed = slot_close_ffi(self.descriptor) == 0
  self.descriptor = -1
  closed
}

///|
pub fn NativeExecutorSlotChild::pid(self : NativeExecutorSlotChild) -> Int {
  self.pid
}

///|
/// Wait for the holder to end. With `block` false, `None` means it is still
/// running.
pub fn NativeExecutorSlotChild::wait(
  self : NativeExecutorSlotChild,
  block : Bool,
) -> Result[NativeExecutorSlotExit?, NativeExecutorSlotIssue] {
  if self.exit is Some(exit) {
    return Ok(Some(exit))
  }
  let status = slot_wait_ffi(self.pid, if block { 1 } else { 0 })
  let exit = if status == -2 {
    return Ok(None)
  } else if status >= 0 && status < 256 {
    Exited(status)
  } else if status >= 256 {
    Signaled(status - 256)
  } else {
    return Err(WaitFailed)
  }
  self.exit = Some(exit)
  Ok(Some(exit))
}

///|
/// Ask the holder to stop (SIGTERM). This does not prove that it stopped;
/// only the slot lock does.
pub fn NativeExecutorSlotChild::terminate(
  self : NativeExecutorSlotChild,
) -> Bool {
  self.exit is None && slot_signal_ffi(self.pid, 15) == 0
}

///|
pub fn native_current_executable() -> Result[String, NativeExecutorSlotIssue] {
  let path = @utf8.decode_lossy(current_executable_ffi())
  if path.is_empty() {
    Err(InvalidConfiguration)
  } else {
    Ok(path)
  }
}

///|
extern "C" fn install_termination_ffi() -> Int = "actql_executor_slot_install_termination"

///|
extern "C" fn termination_requested_ffi() -> Int = "actql_executor_slot_termination_requested"

///|
extern "C" fn sleep_ms_ffi(milliseconds : Int) = "actql_executor_slot_sleep_ms"

///|
/// Record SIGTERM and SIGINT instead of exiting at once, so a resident loop
/// can stop taking work while its running work finishes or is settled.
pub fn install_native_termination_request() -> Bool {
  install_termination_ffi() == 0
}

///|
pub fn native_termination_requested() -> Bool {
  termination_requested_ffi() != 0
}

///|
/// Wait, returning early when termination is requested.
pub fn native_wait_milliseconds(milliseconds : Int) -> Unit {
  sleep_ms_ffi(milliseconds)
}

///|
#borrow(path, line)
extern "C" fn append_line_ffi(
  path : Bytes,
  path_length : Int,
  line : Bytes,
  line_length : Int,
) -> Int = "actql_executor_slot_append_line"

///|
/// Append `line` and a newline to `path` and sync it before returning.
pub fn native_append_evidence_line(path : String, line : String) -> Bool {
  if !valid_path(path) || line.contains("\n") {
    return false
  }
  let encoded_path = @utf8.encode(path)
  let encoded_line = @utf8.encode(line)
  append_line_ffi(
    encoded_path,
    encoded_path.length(),
    encoded_line,
    encoded_line.length(),
  ) ==
  0
}
