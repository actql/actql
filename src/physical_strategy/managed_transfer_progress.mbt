///|
/// Common Transfer progression actions. Environment adapters execute the
/// physical operation named by an action and then request the next step; they
/// do not choose lifecycle ordering themselves.
pub(all) enum ManagedTransferRuntimeAction {
  TransferAwaitSourceStop
  TransferMarkCleanupPending
  TransferSettleSourceSite
  TransferSettleRun
  TransferRetainDestinationSite
  TransferSettleDestinationSite
  TransferReleaseDestinationCleanup
  TransferCompleteRun
  TransferReclaimDestination
  TransferAbortRun
  TransferReleaseRun
  TransferReleaseSiteHolding
  TransferFinished
} derive(Eq, Debug)

///|
/// Bounded facts observed after a representation provider has finished one
/// destination copy. Object ownership and callable adapter methods remain
/// environment concerns; common code decides whether the observed generation
/// and measurements are admissible for the selected Transfer estimate.
pub(all) struct ManagedTransferDestinationFacts {
  distinct_material : Bool
  distinct_generation : Bool
  rows : Int
  batches : Int
  max_batch_rows : Int
  max_batch_bytes : Int
  transferred_bytes : Int64
  retained_bytes : Int64
}

///|
/// Admit one independently owned Transfer destination against the exact
/// pre-execution ceilings. A provider cannot turn a shared handle, aliased
/// generation, malformed batching report, or post-copy overrun into a common
/// completion merely by returning a structurally valid adapter object.
pub fn managed_transfer_destination_admitted(
  facts : ManagedTransferDestinationFacts,
  transfer_limit : Int64,
  retention_limit : Int64,
) -> Bool {
  transfer_limit >= 0L &&
  retention_limit >= 0L &&
  facts.distinct_material &&
  facts.distinct_generation &&
  facts.rows >= 0 &&
  facts.batches >= 0 &&
  facts.max_batch_rows > 0 &&
  facts.max_batch_bytes > 0 &&
  facts.transferred_bytes >= 0L &&
  facts.transferred_bytes <= transfer_limit &&
  facts.retained_bytes >= 0L &&
  facts.retained_bytes <= retention_limit
}

///|
/// Plan successful destination adoption one physical fact at a time.
pub fn prepare_managed_transfer_commit_step(
  transfer : ManagedTransfer,
  source_access_stopped : Bool,
  source_site_settled : Bool,
  destination_verified : Bool,
  destination_holding_retained : Bool,
  destination_site_settled : Bool,
  destination_cleanup_released : Bool,
) -> Result[ManagedTransferRuntimeAction, RunIssue] {
  managed_transfer_commit_step(
    transfer.settled,
    transfer.completed,
    transfer.released,
    source_access_stopped,
    source_site_settled,
    destination_verified,
    destination_holding_retained,
    destination_site_settled,
    destination_cleanup_released,
  )
}

///|
fn managed_transfer_commit_step(
  settled : Bool,
  completed : Bool,
  released : Bool,
  source_access_stopped : Bool,
  source_site_settled : Bool,
  destination_verified : Bool,
  destination_holding_retained : Bool,
  destination_site_settled : Bool,
  destination_cleanup_released : Bool,
) -> Result[ManagedTransferRuntimeAction, RunIssue] {
  if released {
    return Err(NotReady)
  }
  if completed {
    return Ok(TransferFinished)
  }
  if !source_access_stopped {
    return Ok(TransferAwaitSourceStop)
  }
  if !source_site_settled {
    return Ok(TransferSettleSourceSite)
  }
  if !destination_verified {
    return Err(NotReady)
  }
  if !settled {
    return Ok(TransferSettleRun)
  }
  if !destination_holding_retained {
    return Ok(TransferRetainDestinationSite)
  }
  if !destination_site_settled {
    return Ok(TransferSettleDestinationSite)
  }
  if !destination_cleanup_released {
    return Ok(TransferReleaseDestinationCleanup)
  }
  Ok(TransferCompleteRun)
}

///|
/// Plan failure or ordinary release without coupling source access lifetime to
/// destination reclamation. Cleanup-pending is recorded once while source
/// stop remains unknown; physical reservations are released only after the
/// corresponding observations become confirmed.
pub fn prepare_managed_transfer_cleanup_step(
  transfer : ManagedTransfer,
  source_access_stopped : Bool,
  source_site_settled : Bool,
  destination_reclaimed : Bool,
  destination_site_settled : Bool,
  destination_cleanup_released : Bool,
  site_holding_released : Bool,
) -> Result[ManagedTransferRuntimeAction, RunIssue] {
  managed_transfer_cleanup_step(
    transfer.completed,
    transfer.released,
    @resources.reservation_open(transfer.reservation),
    captured_managed_transfer_pending(transfer),
    source_access_stopped,
    source_site_settled,
    destination_reclaimed,
    destination_site_settled,
    destination_cleanup_released,
    site_holding_released,
  )
}

///|
fn managed_transfer_cleanup_step(
  completed : Bool,
  released : Bool,
  reservation_open : Bool,
  cleanup_pending : Bool,
  source_access_stopped : Bool,
  source_site_settled : Bool,
  destination_reclaimed : Bool,
  destination_site_settled : Bool,
  destination_cleanup_released : Bool,
  site_holding_released : Bool,
) -> Result[ManagedTransferRuntimeAction, RunIssue] {
  if !source_access_stopped {
    if !completed && reservation_open && !cleanup_pending {
      return Ok(TransferMarkCleanupPending)
    }
    if destination_reclaimed && !destination_site_settled {
      return Ok(TransferSettleDestinationSite)
    }
    if destination_reclaimed && !destination_cleanup_released {
      return Ok(TransferReleaseDestinationCleanup)
    }
    return Ok(TransferAwaitSourceStop)
  }
  if !source_site_settled {
    return Ok(TransferSettleSourceSite)
  }
  if !destination_reclaimed {
    return Ok(TransferReclaimDestination)
  }
  if !destination_site_settled {
    return Ok(TransferSettleDestinationSite)
  }
  if !destination_cleanup_released {
    return Ok(TransferReleaseDestinationCleanup)
  }
  if completed {
    if !released {
      return Ok(TransferReleaseRun)
    }
    if !site_holding_released {
      return Ok(TransferReleaseSiteHolding)
    }
    return Ok(TransferFinished)
  }
  if reservation_open {
    return Ok(TransferAbortRun)
  }
  Ok(TransferFinished)
}

///|
/// Stable adapter projection. Codes name physical actions and are not a wire
/// protocol or persistent Transfer identity.
pub fn managed_transfer_runtime_action_code(
  action : ManagedTransferRuntimeAction,
) -> Int {
  match action {
    TransferAwaitSourceStop => 0
    TransferMarkCleanupPending => 1
    TransferSettleSourceSite => 2
    TransferSettleRun => 3
    TransferRetainDestinationSite => 4
    TransferSettleDestinationSite => 5
    TransferReleaseDestinationCleanup => 6
    TransferCompleteRun => 7
    TransferReclaimDestination => 8
    TransferAbortRun => 9
    TransferReleaseRun => 10
    TransferReleaseSiteHolding => 11
    TransferFinished => 12
  }
}
