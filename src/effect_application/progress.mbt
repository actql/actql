///|
pub(all) enum EffectRowState {
  Prepared
  Dispatching
  Applied
  Accepted
  Failed
  Unknown
} derive(Eq, Debug)

///|
pub(all) struct EffectRowRecord {
  logical_item_locator_cid : String
  intent_fingerprint_cid : String
  dispatch_key_cid : String
  canonical_request_cid : String
  state : EffectRowState
}

///|
pub(all) enum EffectRowAction {
  PersistPrepared
  ClaimPrepared
  JoinActive
  ReconcilePossibleDispatch
  ReconcileUnknown
  ReturnApplied
  ReturnAccepted
  ReturnFailed
  RequestConflict
  InvalidRecord
} derive(Eq, Debug)

///|
/// This is a recovery decision, not permission to send. The Store must
/// durably commit Prepared and then CAS it to Dispatching before physical I/O.
/// Current apply admission, authorization, and ownership are separate gates.
pub fn effect_row_recovery_action(
  expected_locator : LogicalItemLocator,
  intent_fingerprint_cid : String,
  expected_key : EffectDispatchKey,
  canonical_request_cid : String,
  stored : EffectRowRecord?,
  active_owner : Bool,
) -> EffectRowAction {
  if !effect_cid_valid(canonical_request_cid) ||
    !effect_cid_valid(intent_fingerprint_cid) ||
    expected_locator.logical_request_scope_cid !=
    expected_key.logical_request_scope_cid {
    return InvalidRecord
  }
  match stored {
    None => if active_owner { InvalidRecord } else { PersistPrepared }
    Some(record) => {
      if !effect_cid_valid(record.logical_item_locator_cid) ||
        !effect_cid_valid(record.intent_fingerprint_cid) ||
        !effect_cid_valid(record.dispatch_key_cid) ||
        !effect_cid_valid(record.canonical_request_cid) {
        return InvalidRecord
      }
      if record.logical_item_locator_cid != expected_locator.cid ||
        record.intent_fingerprint_cid != intent_fingerprint_cid ||
        record.dispatch_key_cid != expected_key.cid ||
        record.canonical_request_cid != canonical_request_cid {
        return RequestConflict
      }
      match record.state {
        Prepared => if active_owner { JoinActive } else { ClaimPrepared }
        Dispatching =>
          if active_owner {
            JoinActive
          } else {
            ReconcilePossibleDispatch
          }
        Applied => ReturnApplied
        Accepted => ReturnAccepted
        Failed => ReturnFailed
        Unknown => ReconcileUnknown
      }
    }
  }
}

///|
pub fn effect_row_action_code(action : EffectRowAction) -> Int {
  match action {
    PersistPrepared => 0
    ClaimPrepared => 1
    JoinActive => 2
    ReconcilePossibleDispatch => 3
    ReconcileUnknown => 4
    ReturnApplied => 5
    ReturnAccepted => 6
    ReturnFailed => 7
    RequestConflict => 8
    InvalidRecord => 9
  }
}

///|
/// The environment reports one durable Store snapshot. -1 is absence; a
/// present row must carry both exact identities and a known state code.
pub fn effect_row_recovery_action_from_store(
  expected_locator : LogicalItemLocator,
  intent_fingerprint_cid : String,
  expected_key : EffectDispatchKey,
  canonical_request_cid : String,
  stored_locator_cid : String,
  stored_fingerprint_cid : String,
  stored_key_cid : String,
  stored_request_cid : String,
  stored_state : Int,
  active_owner : Bool,
) -> Int {
  if stored_state == -1 {
    if !stored_locator_cid.is_empty() ||
      !stored_fingerprint_cid.is_empty() ||
      !stored_key_cid.is_empty() ||
      !stored_request_cid.is_empty() {
      return effect_row_action_code(InvalidRecord)
    }
    return effect_row_action_code(
      effect_row_recovery_action(
        expected_locator,
        intent_fingerprint_cid,
        expected_key,
        canonical_request_cid,
        None,
        active_owner,
      ),
    )
  }
  let state = match stored_state {
    0 => Prepared
    1 => Dispatching
    2 => Applied
    3 => Accepted
    4 => Failed
    5 => Unknown
    _ => return effect_row_action_code(InvalidRecord)
  }
  effect_row_action_code(
    effect_row_recovery_action(
      expected_locator,
      intent_fingerprint_cid,
      expected_key,
      canonical_request_cid,
      Some({
        logical_item_locator_cid: stored_locator_cid,
        intent_fingerprint_cid: stored_fingerprint_cid,
        dispatch_key_cid: stored_key_cid,
        canonical_request_cid: stored_request_cid,
        state,
      }),
      active_owner,
    ),
  )
}

///|
/// Preserve the typed ledger fact when the Host decides whether a physical
/// request may be claimed. A stored dispatching fact without an active owner
/// is possible-dispatch evidence, never automatic resend authority.
pub fn effect_row_recovery_action_from_entry(
  expected_locator : LogicalItemLocator,
  intent_fingerprint_cid : String,
  expected_key : EffectDispatchKey,
  canonical_request_cid : String,
  stored : EffectLedgerEntry?,
  active_owner : Bool,
) -> Int {
  let record = match stored {
    None => None
    Some(entry) =>
      Some({
        logical_item_locator_cid: entry.logical_item_locator_cid,
        intent_fingerprint_cid: entry.intent_fingerprint_cid,
        dispatch_key_cid: entry.dispatch_key_cid,
        canonical_request_cid: entry.canonical_request_cid,
        state: entry.state,
      })
  }
  effect_row_action_code(
    effect_row_recovery_action(
      expected_locator, intent_fingerprint_cid, expected_key, canonical_request_cid,
      record, active_owner,
    ),
  )
}
