///|
priv enum LocalManagedScratchPhase {
  Bridges
  Imports
  Reads
  Cids
  Issuers
  Retired
} derive(Eq)

///|
/// Cursor over the existing driver's roots, not a new custody owner or ledger.
priv struct LocalManagedScratchRetirement {
  mut phase : LocalManagedScratchPhase
  mut index : Int
  mut steps : Int64
}

///|
fn local_managed_scratch_retirement() -> LocalManagedScratchRetirement {
  { phase: Bridges, index: 0, steps: 0L, }
}

///|
/// Collection entries and phase boundaries share one fixed cleanup slice.
/// Call only after provider scratch detaches and all active callbacks return.
/// A separately retained completion keeps its original physical cleanup handle.
fn[B, I, R, S] advance_local_managed_scratch_retirement(
  cursor : LocalManagedScratchRetirement,
  bridges : Array[Ref[B?]],
  imports : Array[Ref[I?]],
  reads : Array[R?],
  cids : Array[String?],
  issuers : Array[S],
) -> Bool {
  let mut steps = 0
  while steps < 64 {
    match cursor.phase {
      Bridges =>
        if cursor.index < bridges.length() {
          bridges[cursor.index].val = None
          cursor.index += 1
        } else {
          cursor.phase = Imports
          cursor.index = 0
        }
      Imports =>
        if cursor.index < imports.length() {
          imports[cursor.index].val = None
          cursor.index += 1
        } else {
          cursor.phase = Reads
          cursor.index = 0
        }
      Reads =>
        if cursor.index < reads.length() {
          reads[cursor.index] = None
          cursor.index += 1
        } else {
          cursor.phase = Cids
          cursor.index = 0
        }
      Cids =>
        if cursor.index < cids.length() {
          cids[cursor.index] = None
          cursor.index += 1
        } else {
          cursor.phase = Issuers
          cursor.index = 0
        }
      Issuers =>
        if !issuers.is_empty() {
          issuers.pop() |> ignore
        } else {
          // No live issuer remains when its empty backing storage is retired.
          issuers.shrink_to_fit()
          cursor.phase = Retired
        }
      Retired => return true
    }
    steps += 1
    cursor.steps += 1L
  }
  cursor.phase == Retired
}

///|
/// Once settled, a detached import handle must not repopulate retired roots.
/// This is lifecycle gating; the existing input/admission checks still apply.
fn local_managed_input_writes_open(
  live : Bool,
  settled : Bool,
  disposed : Bool,
) -> Bool {
  live && !settled && !disposed
}

///|
// Keep the SAME provider for eventual full cleanup even when its independent
// accepted output/backing allows this Local execution's scratch to retire.
fn release_local_managed_provider_scratch(
  provider : Ref[@local.ManagedProviderExecution?],
  retained_completion : Ref[Bool],
  completed : Bool,
  final_work : Ref[Result[Int64, @local.ManagedProviderWorkIssue]],
) -> Bool {
  guard provider.val is Some(active) else { return true }
  if !@local.managed_provider_stopped(active) {
    return false
  }
  match @local.cleanup_managed_provider(active) {
    Ok(true) => {
      final_work.val = @local.managed_provider_cumulative_work(active)
      provider.val = None
      true
    }
    Ok(false) =>
      if completed &&
        (
          retained_completion.val ||
          @local.managed_provider_retained_completion(active)
        ) {
        final_work.val = @local.managed_provider_cumulative_work(active)
        retained_completion.val = true
        true
      } else {
        false
      }
    Err(_) => false
  }
}
