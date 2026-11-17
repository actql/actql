///|
/// Constructor geometry, never an allocation grant or publication authority.
pub(all) enum ClientProgramValidationReadPhase {
  Scaffold
  Inventory
  Plan
  Fence
}

///|
/// The same owned plan supplies both logical cost and physical Read geometry.
/// Inventory counts precede its checked snapshot; Plan metadata excludes the
/// retained captured rows. Native ABI costs belong to the actual Read owner.
pub(all) struct ClientProgramValidationReadDemand {
  retained_bytes : Int64
  execution_bytes : Int64
  copied_slots : Int
  copied_arrays : Int
  metadata_nodes : Int
  phase : ClientProgramValidationReadPhase
}
