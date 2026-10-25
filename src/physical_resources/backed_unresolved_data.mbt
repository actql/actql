///|
/// Immutable accounting DATA only. No provider, child, Ledger, reservation,
/// borrow, launch/stop/settle permission or journal lookup key is exported.
pub(all) struct BackedExecutionCumulativeData {
  planning_work : Int
  attempts : Int
  transferred_bytes : Int64
  uncertain_transfer_bytes : Int64
} derive(Eq, Debug)

///|
/// Current occupation of the same child. These counters may decrease after
/// actual retirement; none is spent work or a transferable allowance.
pub(all) struct BackedExecutionOccupationData {
  holdings : Int
  reserved_attempts : Int
  live_reservations : Int
  live_delegations : Int
} derive(Eq, Debug)

///|
pub(all) enum BackedExecutionReadUseData {
  NotIssued
  Pending
  Closing
  Retired
} derive(Eq, Debug)

///|
/// This is the exact remaining original provisioning reservation, not another
/// byte charge and not the shared allocation's already reserved backing.
pub(all) struct BackedExecutionProvisionData {
  transfer_bytes : Int64
  retained_bytes : Int64
  execution_bytes : Int64
  open : Bool
  cleanup_pending : Bool
} derive(Eq, Debug)

///|
/// Fixed-size, scalar-only projection. None final usage stays unobserved.
/// Even a closed logical reservation does not acknowledge physical retirement.
pub(all) struct BackedExecutionOriginalData {
  allocation_bytes : Int64
  extent : BackedExecutionExtent
  access : BackedExecutionAccess
  limits : LedgerLimits
  cumulative : BackedExecutionCumulativeData
  occupation : BackedExecutionOccupationData
  peak_retention_bytes : Int64
  provision : BackedExecutionProvisionData
  region_closing : Bool
  read_use : BackedExecutionReadUseData
  final_usage : LedgerUsage?
} derive(Eq, Debug)

///|
/// A read-only validated DATA observation, not nominal original custody.
/// Copies can be read as DATA but cannot enter any existing ticket/ACK API.
pub struct UnresolvedBackedExecutionOriginal {
  priv data : BackedExecutionOriginalData
}

///|
pub(all) enum BackedExecutionDataIssue {
  InvalidData
} derive(Eq, Debug)

///|
fn backed_unresolved_limits_valid(limits : LedgerLimits) -> Bool {
  limits.planning_work >= 0 &&
  limits.attempts >= 0 &&
  limits.holdings >= 0 &&
  limits.transfer_bytes >= 0L &&
  limits.retained_bytes >= 0L &&
  limits.execution_bytes >= 0L
}

///|
fn backed_unresolved_final_valid(
  data : BackedExecutionOriginalData,
  usage : LedgerUsage,
) -> Bool {
  let limits = data.limits
  let cumulative = data.cumulative
  usage.planning_work == cumulative.planning_work &&
  usage.attempts == cumulative.attempts &&
  // Preserve the actual last observed census independently of the domain's
  // later confirmed retirement. Current occupation is a separate projection.
  usage.holdings >= 0 &&
  usage.holdings <= limits.holdings &&
  usage.reserved_attempts >= 0 &&
  usage.reserved_attempts <= limits.attempts - usage.attempts &&
  usage.live_reservations >= 0 &&
  usage.live_delegations >= 0 &&
  usage.transferred_bytes == cumulative.transferred_bytes &&
  usage.uncertain_transfer_bytes == cumulative.uncertain_transfer_bytes &&
  usage.reserved_transfer_bytes >= 0L &&
  usage.reserved_transfer_bytes <=
  limits.transfer_bytes -
  usage.transferred_bytes -
  usage.uncertain_transfer_bytes &&
  usage.held_bytes >= 0L &&
  usage.held_bytes <= limits.retained_bytes &&
  usage.reserved_retention_bytes >= 0L &&
  usage.reserved_retention_bytes <= limits.retained_bytes - usage.held_bytes &&
  usage.reserved_execution_bytes >= 0L &&
  usage.reserved_execution_bytes <= limits.execution_bytes &&
  usage.peak_retention_bytes >=
  usage.held_bytes + usage.reserved_retention_bytes &&
  usage.peak_retention_bytes >= data.peak_retention_bytes &&
  usage.peak_retention_bytes <= limits.retained_bytes
}

///|
/// Bounded admission of read-only DATA. Host/Store epoch, original operation
/// key/CAS and physical provider/backing admission remain with the existing
/// installed journal/Host. Passing this reader supplies none of those facts.
pub fn admit_unresolved_backed_execution_data(
  data : BackedExecutionOriginalData,
) -> Result[UnresolvedBackedExecutionOriginal, BackedExecutionDataIssue] {
  let limits = data.limits
  let cumulative = data.cumulative
  let provision = data.provision
  if !backed_unresolved_limits_valid(limits) ||
    !backed_extent_valid(data.extent, data.allocation_bytes) ||
    limits.retained_bytes > data.extent.payload_length ||
    limits.execution_bytes > data.extent.payload_length - limits.retained_bytes ||
    cumulative.planning_work < 0 ||
    cumulative.planning_work > limits.planning_work ||
    cumulative.attempts < 0 ||
    cumulative.attempts > limits.attempts ||
    data.occupation.holdings < 0 ||
    data.occupation.holdings > limits.holdings ||
    data.occupation.reserved_attempts < 0 ||
    data.occupation.reserved_attempts > limits.attempts - cumulative.attempts ||
    data.occupation.live_reservations < 0 ||
    data.occupation.live_delegations < 0 ||
    cumulative.transferred_bytes < 0L ||
    cumulative.transferred_bytes > limits.transfer_bytes ||
    cumulative.uncertain_transfer_bytes < 0L ||
    cumulative.uncertain_transfer_bytes >
    limits.transfer_bytes - cumulative.transferred_bytes ||
    data.peak_retention_bytes < 0L ||
    data.peak_retention_bytes > limits.retained_bytes ||
    provision.transfer_bytes < 0L ||
    provision.retained_bytes < 0L ||
    provision.execution_bytes < 0L ||
    provision.transfer_bytes >
    limits.transfer_bytes -
    cumulative.transferred_bytes -
    cumulative.uncertain_transfer_bytes {
    return Err(InvalidData)
  }
  if provision.open {
    if data.final_usage is Some(_) ||
      provision.transfer_bytes !=
      limits.transfer_bytes -
      cumulative.transferred_bytes -
      cumulative.uncertain_transfer_bytes {
      return Err(InvalidData)
    }
  } else {
    if data.occupation !=
      {
        holdings: 0,
        reserved_attempts: 0,
        live_reservations: 0,
        live_delegations: 0,
      } ||
      provision.transfer_bytes != 0L ||
      provision.retained_bytes != 0L ||
      provision.execution_bytes != 0L ||
      provision.cleanup_pending {
      return Err(InvalidData)
    }
    match data.final_usage {
      Some(usage) =>
        if !backed_unresolved_final_valid(data, usage) {
          return Err(InvalidData)
        }
      None =>
        if cumulative.planning_work != limits.planning_work ||
          cumulative.attempts != limits.attempts ||
          cumulative.uncertain_transfer_bytes !=
          limits.transfer_bytes - cumulative.transferred_bytes {
          return Err(InvalidData)
        }
    }
  }
  Ok({ data, })
}

///|
/// Live original-only projection. Existing current/mutation fences and
/// foreign/retired refusal remain; this does not permit another allocation.
/// Fixed projection/transport/Store controls need their existing funding.
pub fn[P, C] issue_backed_execution_original_data(
  region : BackedExecutionRegion[P, C],
  provider : P,
  child : C,
  ticket : BackedExecutionDelegation[P, C],
) -> Result[BackedExecutionOriginalData, BackedExecutionIssue] {
  let (_, borrow, logical) = match
    backed_child_current(region, provider, child, ticket) {
    Ok(original) => original
    Err(issue) => return Err(issue)
  }
  let reservation = logical.reservation
  let read_use = match ticket.read_use {
    Some(value) => {
      match backed_read_use_current(region, provider, child, ticket, value) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      if value.closing {
        Closing
      } else {
        Pending
      }
    }
    None => if ticket.read_use_issued { Retired } else { NotIssued }
  }
  Ok({
    allocation_bytes: borrow.allocation.bytes,
    extent: ticket.extent,
    access: ticket.access,
    limits: ticket.limits,
    cumulative: {
      planning_work: logical.planning,
      attempts: logical.attempts,
      transferred_bytes: logical.transferred,
      uncertain_transfer_bytes: logical.uncertain,
    },
    occupation: if reservation.open {
      {
        holdings: logical.holdings,
        reserved_attempts: logical.reserved_attempts,
        live_reservations: logical.live_reservations,
        live_delegations: logical.live_delegations,
      }
    } else {
      {
        holdings: 0,
        reserved_attempts: 0,
        live_reservations: 0,
        live_delegations: 0,
      }
    },
    peak_retention_bytes: ticket.peak_retention,
    provision: {
      transfer_bytes: reservation.transfer,
      retained_bytes: reservation.retention,
      execution_bytes: reservation.execution,
      open: reservation.open,
      cleanup_pending: reservation.cleanup_pending,
    },
    region_closing: region.closing,
    read_use,
    final_usage: ticket.final_usage,
  })
}

///|
pub fn unresolved_backed_execution_data(
  observation : UnresolvedBackedExecutionOriginal,
) -> BackedExecutionOriginalData {
  observation.data
}
