///|
/// Local acceptance injection retained by the exact stopped cleanup owner.
/// With the default zero failures this never defers physical cleanup.
priv struct StoppedReleaseFailureHook {
  mut remaining : Int
  mut attempts : Int
}

///|
fn stopped_release_failure_attempt(
  hook : StoppedReleaseFailureHook,
  already_settled : Bool,
) -> Int? {
  if already_settled || hook.remaining <= 0 {
    return None
  }
  hook.remaining -= 1
  hook.attempts += 1
  Some(hook.attempts)
}
