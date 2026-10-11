///|
/// A trusted Host representation bound, not a wire-size estimate or a new
/// Ledger limit. Selecting numeric layout coefficients remains an installation
/// obligation. No production profile is inferred from a positive envelope.
pub(all) struct ResidentEffectComputationCapacity {
  contract_bytes : Int64
  control_bytes : Int64
  workspace_bytes : Int64
} derive(Eq)

///|
fn original_computation_capacity_valid(
  capacity : ResidentEffectComputationCapacity,
) -> Bool {
  capacity.contract_bytes > 0L &&
  capacity.control_bytes > 0L &&
  capacity.workspace_bytes > 0L &&
  capacity.contract_bytes <= 9223372036854775807L - capacity.control_bytes
}

///|
/// Fund the representation and measurement workspace on the original Ledger.
/// This byte-only reservation supplies no attempt, transfer or send authority.
fn reserve_original_computation_capacity(
  ledger : @resources.Ledger,
  capacity : ResidentEffectComputationCapacity,
) -> Result[@resources.CapacityReservation, @resources.LedgerIssue] {
  if !original_computation_capacity_valid(capacity) {
    return Err(InvalidCharge)
  }
  @resources.reserve_capacity(
    ledger,
    capacity.contract_bytes + capacity.control_bytes,
    capacity.workspace_bytes,
  )
}

///|
/// Only the existing capture cleanup path retires this record. The original
/// contracts are dropped before settlement; failed settlement keeps the same
/// nominal token, without making another reservation or retaining the graph.
priv struct FundedResidentEffectComputation {
  capacity : ResidentEffectComputationCapacity
  reservation : @resources.CapacityReservation
  mut evidence : OriginalResidentEffectComputationEvidence?
  mut physical_cleanup_confirmed : Bool
}
