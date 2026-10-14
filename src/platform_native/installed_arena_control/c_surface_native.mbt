///|
/// Private installed C boundary: construct the existing typed limits in MoonBit.
/// The C shim must not manufacture a LedgerLimits object or read its layout.
/// These inputs select only the original arena intent; they are not authority,
/// actual acquisition, VM funding or an adopted numerical product profile.
pub fn prepare_installed_arena_from_primitives(
  source : String,
  recipe : Bytes,
  generation : Int64,
  bytes : Int64,
  planning_work : Int,
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  control_envelope_bytes : Int64,
) -> Result[InstalledArenaHost, @bootstrap.NativeBootstrapIssue] {
  let limits : @resources.LedgerLimits = {
    planning_work,
    attempts,
    holdings,
    transfer_bytes,
    retained_bytes,
    execution_bytes,
  }
  prepare_installed_arena_host(
    source, recipe, generation, bytes, limits, control_envelope_bytes,
  )
}
