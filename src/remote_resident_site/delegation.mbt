///|
/// What this Site delegates to the one Cloud it is configured for. It is Site
/// configuration, never taken from a dispatch: an instruction from that Cloud
/// can make the Site do only what this names, within its capacity.
pub(all) struct ResidentSiteDelegation {
  coordinator_authority : String
  site_key : String
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  grant_cid : String
  evidence_issuer_capability_cid : String
  budget_cids : Array[String]
}

///|
/// Why a dispatch is refused before acceptance. Refusal writes nothing and
/// starts nothing.
pub(all) enum ResidentDispatchRefusal {
  ForeignCoordinator
  ForeignSite
  StaleGeneration
  ForeignRuntime
  ForeignConnector
  ForeignGrant
  ForeignIssuer
  UnsupportedBudget
  /// This implementation runs only source-free Values Runs it can rebuild
  /// from typed run materials.
  MaterialsMissing
  MaterialsRejected(@host.ClientValuesRunMaterialsIssue)
  /// The Run is not live at the Site's own clock.
  NotCurrent
  /// The bounded queue of accepted, not yet started dispatches is full.
  QueueFull
}

///|
/// Check a dispatch against the Site's delegation and current generation.
/// A matching grant alone is not enough: every delegated scope must match.
pub fn check_resident_dispatch_delegation(
  delegation : ResidentSiteDelegation,
  request : @remote.DispatchRequest,
  site_generation : Int,
) -> Result[Unit, ResidentDispatchRefusal] {
  let route = @remote.dispatch_request_journal_key(request)
  let scope = @remote.dispatch_request_execution_scope(request)
  if route[0] != delegation.coordinator_authority {
    return Err(ForeignCoordinator)
  }
  if scope[0] != delegation.site_key {
    return Err(ForeignSite)
  }
  if scope[1] != site_generation.to_string() {
    return Err(StaleGeneration)
  }
  if scope[2] != delegation.runtime_bundle_cid {
    return Err(ForeignRuntime)
  }
  if scope[3] != delegation.connector_registration ||
    scope[4] != delegation.connector_revision ||
    scope[5] != delegation.strategy_revision {
    return Err(ForeignConnector)
  }
  if scope[6] != delegation.grant_cid {
    return Err(ForeignGrant)
  }
  if scope[7] != delegation.evidence_issuer_capability_cid {
    return Err(ForeignIssuer)
  }
  if !delegation.budget_cids.contains(
      @remote.dispatch_request_budget_cid(request),
    ) {
    return Err(UnsupportedBudget)
  }
  Ok(())
}

///|
/// The rebuilt Run must be live at the Site's own clock `at` (an ISO 8601
/// UTC timestamp): after its creation, before its validity and the
/// authorization's expiry. Checked at receipt and again before start.
pub fn check_resident_run_current(
  materials : @host.ClientValuesRunMaterials,
  at : String,
) -> Result[Unit, ResidentDispatchRefusal] {
  if @publication.run_publication_start_current(
      materials.admission,
      materials.run_definition,
      at,
    ) {
    Ok(())
  } else {
    Err(NotCurrent)
  }
}

///|
/// Accepted dispatches waiting for the executor slot, bounded so that
/// acceptance never promises more than the Site holds room for.
struct ResidentAcceptedQueue {
  capacity : Int
  waiting : Array[String]
}

///|
pub fn ResidentAcceptedQueue::new(capacity : Int) -> ResidentAcceptedQueue? {
  if capacity < 1 {
    return None
  }
  Some({ capacity, waiting: [], })
}

///|
/// Reserve room for one attempt before it is accepted. The same attempt is
/// reserved once.
pub fn ResidentAcceptedQueue::reserve(
  self : ResidentAcceptedQueue,
  attempt_identity : String,
) -> Result[Unit, ResidentDispatchRefusal] {
  if self.waiting.contains(attempt_identity) {
    return Ok(())
  }
  if self.waiting.length() >= self.capacity {
    return Err(QueueFull)
  }
  self.waiting.push(attempt_identity)
  Ok(())
}

///|
/// The oldest waiting attempt, which is the next to start.
pub fn ResidentAcceptedQueue::next(self : ResidentAcceptedQueue) -> String? {
  self.waiting.get(0)
}

///|
/// Remove an attempt that started, was refused or was cancelled.
pub fn ResidentAcceptedQueue::remove(
  self : ResidentAcceptedQueue,
  attempt_identity : String,
) -> Bool {
  match self.waiting.search(attempt_identity) {
    Some(index) => {
      ignore(self.waiting.remove(index))
      true
    }
    None => false
  }
}

///|
pub fn ResidentAcceptedQueue::length(self : ResidentAcceptedQueue) -> Int {
  self.waiting.length()
}
