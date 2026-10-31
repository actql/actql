///|
pub(all) enum NativeHostInitializationIssue {
  Initial(@bootstrap.NativeBackedInitializationIssue)
  Host(@local.ClientHostInitializationIssue)
}

///|
/// Fixed Native input/constructor connection. The physical issuer first
/// retains a fresh Initialization live child and every partial acquisition.
/// Native installs its actual funded census; the shared Host body consumes
/// that SAME admission once and creates its one original working token.
/// No raw Ledger, scalar limits, Node admission or physical-ACK callback is
/// accepted. The returned Host owner must be retained before construction.
pub fn[I] begin_native_host_initialization_preparation(
  arena : @arena.InstalledArenaHost,
  live : @bootstrap.NativeBackedLiveChild[
    @arena.InstalledArenaHost,
    @arena.InstalledArenaDomain,
    I,
  ],
  input : I,
  budget : @bootstrap.NativeBackedInitializationBudget,
  policy : @local.ClientLocalResourcePolicy,
) -> Result[
  @local.ClientHostInitializationPreparation[I],
  NativeHostInitializationIssue,
] {
  let initial = match arena.initialize_preparation(live, input, budget) {
    Err(issue) => return Err(Initial(issue))
    Ok(value) => value
  }
  @local.begin_backed_host_initialization_preparation(initial, input, policy).map_err(issue => {
      Host(issue)
    },
  )
}
