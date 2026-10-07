///|
priv enum LocalManagedInputStopPhase {
  Bridges
  Imports
  Stopped
} derive(Eq)

///|
/// Progress over existing input owners; revocation does not release their roots.
priv struct LocalManagedInputStop {
  mut phase : LocalManagedInputStopPhase
  mut index : Int
  mut advancing : Bool
}

///|
fn local_managed_input_stop() -> LocalManagedInputStop {
  { phase: Bridges, index: 0, advancing: false, }
}

///|
/// Request flags and provider cancellation are set before entering this slice.
/// A callback may reenter cancellation, but cannot repeat or skip an input.
fn[B, I] advance_local_managed_input_stop(
  cursor : LocalManagedInputStop,
  bridges : Array[Ref[B?]],
  imports : Array[Ref[I?]],
  close_bridge : (B) -> Bool,
  cancel_import : (I) -> Bool,
) -> Bool {
  if cursor.advancing {
    return false
  }
  cursor.advancing = true
  let mut steps = 0
  while steps < 64 {
    match cursor.phase {
      Bridges =>
        if cursor.index < bridges.length() {
          let input = bridges[cursor.index].val
          if input is Some(bridge) && !close_bridge(bridge) {
            // The same owner resumes its private buffer; no new input starts.
            ()
          } else {
            cursor.index += 1
          }
        } else {
          cursor.phase = Imports
          cursor.index = 0
        }
      Imports =>
        if cursor.index < imports.length() {
          let input = imports[cursor.index].val
          if input is Some(importer) && !cancel_import(importer) {
            ()
          } else {
            cursor.index += 1
          }
        } else {
          cursor.phase = Stopped
        }
      Stopped => break
    }
    steps += 1
  }
  cursor.advancing = false
  cursor.phase == Stopped
}
