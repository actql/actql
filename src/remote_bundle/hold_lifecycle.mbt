///|
pub(all) enum RemoteBundleHoldObservation {
  BundleHoldRetained
  BundleHoldFenced
  BundleHoldUnresolved
  BundleHoldUnavailable
} derive(Eq, Debug)

///|
/// The Store supplies its physical catalog incarnation and whether the exact
/// binding's live hold row exists, read atomically with the bundle record.
/// An absent row is conclusive only after that existing record has advanced.
pub fn observe_bundle_hold(
  catalog_incarnation : String,
  record : RemoteBundleRecord?,
  binding : RemoteBundleHoldBinding,
  exact_live_hold : Bool,
) -> RemoteBundleHoldObservation {
  guard record is Some(record) else { return BundleHoldUnavailable }
  if bundle_hold_binding_json(binding) is Err(_) ||
    catalog_incarnation != binding.catalog_incarnation ||
    record.manifest.runtime_bundle_cid != binding.runtime_bundle_cid ||
    record.record_revision < binding.initial_revision ||
    record.owners < 0 ||
    (record.phase == BundleReclaimed && record.owners != 0) {
    return BundleHoldUnavailable
  }
  if exact_live_hold {
    if record.record_revision > binding.initial_revision &&
      record.owners > 0 &&
      (record.phase == BundleActive || record.phase == BundleDraining) {
      BundleHoldRetained
    } else {
      BundleHoldUnavailable
    }
  } else if record.record_revision > binding.initial_revision {
    BundleHoldFenced
  } else {
    BundleHoldUnresolved
  }
}

///|
pub fn bundle_hold_observation_projection(
  value : RemoteBundleHoldObservation,
) -> String {
  match value {
    BundleHoldRetained => "retained"
    BundleHoldFenced => "fenced"
    BundleHoldUnresolved => "unresolved"
    BundleHoldUnavailable => "unavailable"
  }
}

///|
/// New holds require the recorded initial revision and ordinary active-bundle
/// admission. A retry of an already retained binding is handled by observation,
/// without another owner increment or a general retain on a draining bundle.
pub fn prepare_bundle_hold_retain(
  catalog_incarnation : String,
  active_bundle_cid : String?,
  record : RemoteBundleRecord,
  binding : RemoteBundleHoldBinding,
  max_owners : Int,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if observe_bundle_hold(catalog_incarnation, Some(record), binding, false) !=
    BundleHoldUnresolved {
    return Err(InvalidBundleState)
  }
  prepare_active_bundle_retain(active_bundle_cid, record, max_owners)
}

///|
/// Resolve release-before-retain using only the existing record revision.
/// The Store commits this transition and its exact-hold absence check in one
/// transaction. No tombstone, new journal or phase/owner change is introduced.
pub fn prepare_bundle_hold_fence(
  catalog_incarnation : String,
  record : RemoteBundleRecord,
  binding : RemoteBundleHoldBinding,
  exact_live_hold : Bool,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if observe_bundle_hold(
      catalog_incarnation,
      Some(record),
      binding,
      exact_live_hold,
    ) !=
    BundleHoldUnresolved {
    return Err(InvalidBundleState)
  }
  transition(record, record.phase, record.owners)
}
