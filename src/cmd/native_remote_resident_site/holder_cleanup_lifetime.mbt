///|
/// Local channel facts only, never a cleanup ACK or dispatch admission.
priv enum HolderCleanupInput {
  CleanupProgress
  CleanupOther
  CleanupInputEnded
}

///|
/// An unopened ordinary resources set has no close steps. This advances no
/// existing Owner and proves nothing about the environment or inherited slot.
fn[T] holder_cleanup_initial_position(resources : T?) -> Int {
  match resources {
    Some(_) => 0
    None => 7
  }
}

///|
fn holder_cleanup_progress_frame(line : String) -> Bool {
  line == "effect-review"
}

///|
/// This result comes from the same Runtime Store's release operation. Both
/// success values confirm that the original holding is absent after its
/// verification Reader is closed and the current catalog is validated.
/// An unavailable Store or uncertain release remains pending.
fn holder_runtime_process_hold_released(
  result : Result[Bool, @bundle.NativeRuntimeBundleStoreIssue],
) -> Bool {
  result is Ok(_)
}

///|
/// Keep the exact opaque caller value alive across the existing channel and
/// signal waits. EOF/read failure disables further reads; it is not retirement.
/// Only the original Owner close pass can return this value as closed.
fn[T] retain_holder_cleanup_lifetime(
  original : T,
  retry : (T) -> Bool,
  input : () -> HolderCleanupInput,
  signal_wait : () -> Unit,
  pending : (T, Bool) -> Unit,
) -> T {
  let mut control_ended = false
  let mut closed = false
  while !closed {
    closed = retry(original)
    if closed {
      continue
    }
    pending(original, control_ended)
    if control_ended {
      signal_wait()
    } else {
      let mut progress = false
      while !progress {
        match input() {
          CleanupProgress => progress = true
          CleanupOther => ()
          CleanupInputEnded => {
            control_ended = true
            progress = true
          }
        }
      }
    }
  }
  original
}

///|
/// Advance only ACKed original close steps. A failed step is retried on the
/// same payload; all earlier ACKs stay recorded and later Owners stay untouched.
fn[T] advance_holder_cleanup_pass(
  original : T,
  position : Ref[Int],
  end : Int,
  close : (T, Int) -> Bool,
) -> Bool {
  while position.val < end {
    if !close(original, position.val) {
      return false
    }
    position.val += 1
  }
  true
}
