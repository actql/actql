///|
pub(all) enum StopReason {
  Cancelled
  Deadline
} derive(Eq, Debug)

///|
/// Engine-owned request state. It conveys a request but does not itself prove
/// that a kernel has stopped or that resources have been reclaimed.
struct Control {
  mut reason : StopReason?
}

///|
/// Read-only capability supplied to one bounded kernel session.
struct Reader {
  control : Control
}

///|
pub fn control() -> Control {
  { reason: None, }
}

///|
pub fn request_cancel(value : Control) -> Bool {
  if value.reason is Some(_) {
    return false
  }
  value.reason = Some(Cancelled)
  true
}

///|
pub fn request_deadline(value : Control) -> Bool {
  if value.reason is Some(_) {
    return false
  }
  value.reason = Some(Deadline)
  true
}

///|
pub fn stop_requested(value : Reader) -> StopReason? {
  value.control.reason
}
