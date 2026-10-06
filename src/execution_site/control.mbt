///|
/// Portable mutable authority for one execution and retention Site. Concrete
/// resources never enter this value; adapters retain those opaque handles and
/// report only observed stop and reclamation facts.
struct ExecutionSite {
  key : String
  generation : Int
  runtime_revision : String
  max_concurrent_operations : Int
  max_concurrent_transfers : Int
  max_retained_bytes : Int64
  max_execution_bytes : Int64
  mut reserved_retention_bytes : Int64
  mut held_bytes : Int64
  mut reserved_execution_bytes : Int64
  mut peak_retained_bytes : Int64
  mut accepting : Bool
  mut revoked : Bool
  mut active_operations : Int
  mut active_transfers : Int
  mut holdings : Int
  mut cleanup_responsibilities : Int
}

///|
struct SiteOperation {
  site : ExecutionSite
  mut stopped : Bool
  mut retention : Int64
  mut execution : Int64
  mut holding_created : Bool
}

///|
struct SiteTransfer {
  source : ExecutionSite
  destination : ExecutionSite
  mut source_stopped : Bool
  mut destination_stopped : Bool
  mut retention : Int64
  mut execution : Int64
  mut holding_created : Bool
}

///|
struct SiteHolding {
  site : ExecutionSite
  bytes : Int64
  mut live : Bool
}

///|
struct SiteCleanup {
  site : ExecutionSite
  mut live : Bool
}

///|
/// One historical holding awaiting accounting reconstruction. Its pending
/// cleanup responsibility prevents teardown from reporting the Site clean.
struct SiteHoldingRestoration {
  cleanup : SiteCleanup
  bytes : Int64
}

///|
pub fn create_site(
  key : String,
  generation : Int,
  runtime_revision : String,
  max_concurrent_operations : Int,
  max_concurrent_transfers : Int,
  max_retained_bytes : Int64,
  max_execution_bytes : Int64,
) -> ExecutionSite? {
  if key.is_empty() ||
    generation < 0 ||
    runtime_revision.is_empty() ||
    max_concurrent_operations <= 0 ||
    max_concurrent_transfers <= 0 ||
    max_retained_bytes < 0L ||
    max_execution_bytes < 0L {
    return None
  }
  Some({
    key,
    generation,
    runtime_revision,
    max_concurrent_operations,
    max_concurrent_transfers,
    max_retained_bytes,
    max_execution_bytes,
    reserved_retention_bytes: 0L,
    held_bytes: 0L,
    reserved_execution_bytes: 0L,
    peak_retained_bytes: 0L,
    accepting: true,
    revoked: false,
    active_operations: 0,
    active_transfers: 0,
    holdings: 0,
    cleanup_responsibilities: 0,
  })
}

///|
pub fn site_available(site : ExecutionSite) -> Bool {
  site.accepting && !site.revoked
}

///|
pub fn site_revoked(site : ExecutionSite) -> Bool {
  site.revoked
}

///|
pub fn site_generation(site : ExecutionSite) -> Int {
  site.generation
}

///|
pub fn site_runtime_revision(site : ExecutionSite) -> String {
  site.runtime_revision
}

///|
pub fn site_key(site : ExecutionSite) -> String {
  site.key
}

///|
pub fn site_capacity_supports(
  site : ExecutionSite,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  retained_bytes >= 0L &&
  execution_bytes >= 0L &&
  retained_bytes <= site.max_retained_bytes &&
  execution_bytes <= site.max_execution_bytes
}

///|
pub fn site_binding_current(
  site : ExecutionSite,
  generation : Int,
  runtime_revision : String,
) -> Bool {
  site_available(site) &&
  site.generation == generation &&
  site.runtime_revision == runtime_revision
}

///|
pub fn start_site_operation(
  site : ExecutionSite,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> SiteOperation? {
  if !site_available(site) ||
    retained_bytes < 0L ||
    execution_bytes < 0L ||
    site.active_operations >= site.max_concurrent_operations ||
    retained_bytes >
    site.max_retained_bytes - site.held_bytes - site.reserved_retention_bytes ||
    execution_bytes > site.max_execution_bytes - site.reserved_execution_bytes {
    return None
  }
  site.reserved_retention_bytes += retained_bytes
  site.reserved_execution_bytes += execution_bytes
  let peak = site.held_bytes + site.reserved_retention_bytes
  if peak > site.peak_retained_bytes {
    site.peak_retained_bytes = peak
  }
  site.active_operations += 1
  Some({
    site,
    stopped: false,
    retention: retained_bytes,
    execution: execution_bytes,
    holding_created: false,
  })
}

///|
pub fn site_operation_available(operation : SiteOperation) -> Bool {
  !operation.stopped && !operation.site.revoked
}

///|
pub fn settle_site_operation(operation : SiteOperation) -> Bool {
  if operation.stopped {
    return false
  }
  operation.stopped = true
  operation.site.reserved_execution_bytes -= operation.execution
  operation.execution = 0L
  operation.site.reserved_retention_bytes -= operation.retention
  operation.retention = 0L
  operation.site.active_operations -= 1
  true
}

///|
pub fn retain_site_operation_holding(
  operation : SiteOperation,
  bytes : Int64,
) -> SiteHolding? {
  if operation.stopped ||
    operation.holding_created ||
    bytes < 0L ||
    bytes > operation.retention {
    return None
  }
  operation.site.reserved_retention_bytes -= bytes
  operation.retention -= bytes
  operation.site.held_bytes += bytes
  operation.site.holdings += 1
  operation.holding_created = true
  Some({ site: operation.site, bytes, live: true, })
}

///|
pub fn start_site_transfer(
  source : ExecutionSite,
  destination : ExecutionSite,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> SiteTransfer? {
  let same_site = physical_equal(source, destination)
  if !site_available(source) ||
    !site_available(destination) ||
    retained_bytes < 0L ||
    execution_bytes < 0L ||
    source.active_transfers >= source.max_concurrent_transfers ||
    (
      !same_site &&
      destination.active_transfers >= destination.max_concurrent_transfers
    ) ||
    retained_bytes >
    destination.max_retained_bytes -
    destination.held_bytes -
    destination.reserved_retention_bytes ||
    execution_bytes >
    destination.max_execution_bytes - destination.reserved_execution_bytes {
    return None
  }
  destination.reserved_retention_bytes += retained_bytes
  destination.reserved_execution_bytes += execution_bytes
  let peak = destination.held_bytes + destination.reserved_retention_bytes
  if peak > destination.peak_retained_bytes {
    destination.peak_retained_bytes = peak
  }
  source.active_transfers += 1
  if !same_site {
    destination.active_transfers += 1
  }
  Some({
    source,
    destination,
    source_stopped: false,
    destination_stopped: false,
    retention: retained_bytes,
    execution: execution_bytes,
    holding_created: false,
  })
}

///|
pub fn site_transfer_available(transfer : SiteTransfer) -> Bool {
  !transfer.source_stopped &&
  !transfer.destination_stopped &&
  !transfer.source.revoked &&
  !transfer.destination.revoked
}

///|
pub fn settle_site_transfer_source(transfer : SiteTransfer) -> Bool {
  if transfer.source_stopped {
    return false
  }
  transfer.source_stopped = true
  if !physical_equal(transfer.source, transfer.destination) ||
    transfer.destination_stopped {
    transfer.source.active_transfers -= 1
  }
  true
}

///|
pub fn settle_site_transfer_destination(transfer : SiteTransfer) -> Bool {
  if transfer.destination_stopped {
    return false
  }
  transfer.destination_stopped = true
  transfer.destination.reserved_execution_bytes -= transfer.execution
  transfer.execution = 0L
  transfer.destination.reserved_retention_bytes -= transfer.retention
  transfer.retention = 0L
  if !physical_equal(transfer.source, transfer.destination) ||
    transfer.source_stopped {
    transfer.destination.active_transfers -= 1
  }
  true
}

///|
pub fn retain_site_transfer_holding(
  transfer : SiteTransfer,
  bytes : Int64,
) -> SiteHolding? {
  if transfer.source.revoked ||
    transfer.destination.revoked ||
    transfer.destination_stopped ||
    transfer.holding_created ||
    bytes < 0L ||
    bytes > transfer.retention {
    return None
  }
  transfer.destination.reserved_retention_bytes -= bytes
  transfer.retention -= bytes
  transfer.destination.held_bytes += bytes
  transfer.destination.holdings += 1
  transfer.holding_created = true
  Some({ site: transfer.destination, bytes, live: true, })
}

///|
pub fn retain_site_holding(site : ExecutionSite, bytes : Int64) -> SiteHolding? {
  if site.revoked ||
    bytes < 0L ||
    bytes >
    site.max_retained_bytes - site.held_bytes - site.reserved_retention_bytes {
    return None
  }
  site.held_bytes += bytes
  site.holdings += 1
  if site.held_bytes > site.peak_retained_bytes {
    site.peak_retained_bytes = site.held_bytes
  }
  Some({ site, bytes, live: true, })
}

///|
/// Capture accounting for an already-verified historical holding while the
/// Site is current. This reserves no bytes and grants no execution/read use.
/// The caller must keep the same token and exclusive physical cleanup custody.
pub fn prepare_site_holding_restoration(
  site : ExecutionSite,
  bytes : Int64,
) -> SiteHoldingRestoration? {
  if !site_available(site) || bytes < 0L || bytes > site.max_retained_bytes {
    return None
  }
  Some({ cleanup: retain_site_cleanup(site), bytes, })
}

///|
/// Transfer the original pending cleanup obligation into one real holding.
/// Revocation blocks new use, not accounting for already-owned physical debt.
/// Capacity refusal preserves the token; a successful acquisition consumes it.
pub fn SiteHoldingRestoration::acquire(
  self : SiteHoldingRestoration,
) -> SiteHolding? {
  let site = self.cleanup.site
  if !self.cleanup.live ||
    self.bytes >
    site.max_retained_bytes - site.held_bytes - site.reserved_retention_bytes {
    return None
  }
  site.held_bytes += self.bytes
  site.holdings += 1
  if site.held_bytes > site.peak_retained_bytes {
    site.peak_retained_bytes = site.held_bytes
  }
  ignore(release_site_cleanup(self.cleanup))
  Some({ site, bytes: self.bytes, live: true, })
}

///|
pub fn release_site_holding(holding : SiteHolding) -> Bool {
  if !holding.live {
    return false
  }
  holding.live = false
  holding.site.held_bytes -= holding.bytes
  holding.site.holdings -= 1
  true
}

///|
pub fn retain_site_cleanup(site : ExecutionSite) -> SiteCleanup {
  site.cleanup_responsibilities += 1
  { site, live: true, }
}

///|
pub fn release_site_cleanup(cleanup : SiteCleanup) -> Bool {
  if !cleanup.live {
    return false
  }
  cleanup.live = false
  cleanup.site.cleanup_responsibilities -= 1
  true
}

///|
pub fn begin_site_teardown(site : ExecutionSite) -> Unit {
  site.accepting = false
}

///|
pub fn revoke_site(site : ExecutionSite) -> Unit {
  site.accepting = false
  site.revoked = true
}

///|
pub fn site_status(site : ExecutionSite) -> Array[Int64] {
  [
    if site_available(site) {
      1L
    } else {
      0L
    },
    if site.revoked {
      1L
    } else {
      0L
    },
    site.active_operations.to_int64(),
    site.active_transfers.to_int64(),
    site.holdings.to_int64(),
    site.cleanup_responsibilities.to_int64(),
    site.held_bytes,
    site.reserved_retention_bytes,
    site.reserved_execution_bytes,
    site.peak_retained_bytes,
    if !site.accepting &&
      site.active_operations == 0 &&
      site.active_transfers == 0 &&
      site.holdings == 0 &&
      site.cleanup_responsibilities == 0 &&
      site.held_bytes == 0L &&
      site.reserved_retention_bytes == 0L &&
      site.reserved_execution_bytes == 0L {
      1L
    } else {
      0L
    },
  ]
}
