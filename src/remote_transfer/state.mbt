///|
pub(all) enum RemoteTransferAttemptState {
  TransferAdmitted
  TransferCopying
  TransferDestinationCommitted
  TransferFailed
  TransferCancelled
  TransferUnknown
} derive(Eq, Debug)

///|
/// Store object state is separate from each download or destination attempt.
pub(all) enum RemoteTransferObjectState {
  NoTransferObject
  TransferObjectReserved
  TransferObjectUploading
  TransferObjectSealed
  TransferObjectReclaimed
} derive(Eq, Debug)

///|
pub(all) enum RemoteTransferIntegrityState {
  TransferIntegrityPending
  TransferIntegrityVerified
  TransferIntegrityRejected
} derive(Eq, Debug)

///|
pub(all) enum RemoteTransferCleanupState {
  TransferCleanupActive
  TransferCleanupReleased
  TransferCleanupUnknown
  TransferCleanupForceLost
  TransferCleanupRecoveredAfterLoss
} derive(Eq, Debug)

///|
struct RemoteTransferRecord {
  request : RemoteTransferRequest
  mut revision : Int
  mut attempt : RemoteTransferAttemptState
  mut object : RemoteTransferObjectState
  mut integrity : RemoteTransferIntegrityState
  mut cleanup : RemoteTransferCleanupState
  mut source_access_stopped : Bool
  mut destination_temporary_reclaimed : Bool
  mut object_use_released : Bool
  mut destination_material_available : Bool
}

///|
struct RemoteTransferTransition {
  record : RemoteTransferRecord
  expected : Array[Int]
  next : Array[Int]
  mut consumed : Bool
}

///|
fn attempt_code(value : RemoteTransferAttemptState) -> Int {
  match value {
    TransferAdmitted => 0
    TransferCopying => 1
    TransferDestinationCommitted => 2
    TransferFailed => 3
    TransferCancelled => 4
    TransferUnknown => 5
  }
}

///|
fn object_code(value : RemoteTransferObjectState) -> Int {
  match value {
    NoTransferObject => 0
    TransferObjectReserved => 1
    TransferObjectUploading => 2
    TransferObjectSealed => 3
    TransferObjectReclaimed => 4
  }
}

///|
fn integrity_code(value : RemoteTransferIntegrityState) -> Int {
  match value {
    TransferIntegrityPending => 0
    TransferIntegrityVerified => 1
    TransferIntegrityRejected => 2
  }
}

///|
fn cleanup_code(value : RemoteTransferCleanupState) -> Int {
  match value {
    TransferCleanupActive => 0
    TransferCleanupReleased => 1
    TransferCleanupUnknown => 2
    TransferCleanupForceLost => 3
    TransferCleanupRecoveredAfterLoss => 4
  }
}

///|
fn bool_code(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
fn record_state_projection(record : RemoteTransferRecord) -> Array[Int] {
  [
    record.revision,
    attempt_code(record.attempt),
    object_code(record.object),
    integrity_code(record.integrity),
    cleanup_code(record.cleanup),
    bool_code(record.source_access_stopped),
    bool_code(record.destination_temporary_reclaimed),
    bool_code(record.object_use_released),
    bool_code(record.destination_material_available),
  ]
}

///|
fn prepare_transition(
  record : RemoteTransferRecord,
  attempt : RemoteTransferAttemptState,
  object : RemoteTransferObjectState,
  integrity : RemoteTransferIntegrityState,
  cleanup : RemoteTransferCleanupState,
  source_access_stopped : Bool,
  destination_temporary_reclaimed : Bool,
  object_use_released : Bool,
  destination_material_available : Bool,
) -> RemoteTransferTransition {
  let expected = record_state_projection(record)
  {
    record,
    expected,
    next: [
      record.revision + 1,
      attempt_code(attempt),
      object_code(object),
      integrity_code(integrity),
      cleanup_code(cleanup),
      bool_code(source_access_stopped),
      bool_code(destination_temporary_reclaimed),
      bool_code(object_use_released),
      bool_code(destination_material_available),
    ],
    consumed: false,
  }
}

///|
fn transition_matches_record(transition : RemoteTransferTransition) -> Bool {
  transition.expected == record_state_projection(transition.record)
}

///|
pub fn open_record(request : RemoteTransferRequest) -> RemoteTransferRecord {
  let (object, object_use_released) = match request.route {
    DirectStream => (NoTransferObject, true)
    TransferStore => (TransferObjectReserved, false)
  }
  {
    request,
    revision: 0,
    attempt: TransferAdmitted,
    object,
    integrity: TransferIntegrityPending,
    cleanup: TransferCleanupActive,
    source_access_stopped: false,
    destination_temporary_reclaimed: false,
    object_use_released,
    destination_material_available: false,
  }
}

///|
pub fn prepare_start(
  record : RemoteTransferRecord,
) -> Result[RemoteTransferTransition, RemoteTransferIssue] {
  if record.attempt != TransferAdmitted ||
    record.cleanup != TransferCleanupActive {
    return Err(InvalidTransfer)
  }
  let object = match record.request.route {
    DirectStream => NoTransferObject
    TransferStore => TransferObjectUploading
  }
  Ok(
    prepare_transition(
      record,
      TransferCopying,
      object,
      TransferIntegrityPending,
      TransferCleanupActive,
      false,
      false,
      record.object_use_released,
      false,
    ),
  )
}

///|
/// Confirm actual source stop and physical integrity. Store uploads must seal
/// their object in the same durable observation; direct streams have none.
pub fn prepare_source_settled(
  record : RemoteTransferRecord,
  integrity_verified : Bool,
  store_object_sealed : Bool,
) -> Result[RemoteTransferTransition, RemoteTransferIssue] {
  if record.attempt != TransferCopying ||
    record.cleanup != TransferCleanupActive {
    return Err(InvalidTransfer)
  }
  let object = match record.request.route {
    DirectStream => {
      if store_object_sealed {
        return Err(InvalidTransfer)
      }
      NoTransferObject
    }
    TransferStore => {
      if !store_object_sealed {
        return Err(InvalidTransfer)
      }
      TransferObjectSealed
    }
  }
  Ok(
    prepare_transition(
      record,
      TransferCopying,
      object,
      if integrity_verified {
        TransferIntegrityVerified
      } else {
        TransferIntegrityRejected
      },
      TransferCleanupActive,
      true,
      false,
      record.object_use_released,
      false,
    ),
  )
}

///|
pub fn prepare_destination_commit(
  record : RemoteTransferRecord,
) -> Result[RemoteTransferTransition, RemoteTransferIssue] {
  let object_ready = match record.request.route {
    DirectStream => record.object == NoTransferObject
    TransferStore => record.object == TransferObjectSealed
  }
  if record.attempt != TransferCopying ||
    !record.source_access_stopped ||
    record.integrity != TransferIntegrityVerified ||
    !object_ready ||
    record.cleanup != TransferCleanupActive {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_transition(
      record,
      TransferDestinationCommitted,
      record.object,
      record.integrity,
      TransferCleanupActive,
      true,
      true,
      record.object_use_released,
      true,
    ),
  )
}

///|
/// A failed or cancelled call records outcome without guessing that source
/// access stopped or that either destination responsibility was reclaimed.
pub fn prepare_failure(
  record : RemoteTransferRecord,
  cancelled : Bool,
  source_access_stopped : Bool,
) -> Result[RemoteTransferTransition, RemoteTransferIssue] {
  if record.attempt == TransferDestinationCommitted ||
    record.cleanup == TransferCleanupReleased ||
    record.cleanup == TransferCleanupForceLost ||
    record.cleanup == TransferCleanupRecoveredAfterLoss {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_transition(
      record,
      if cancelled {
        TransferCancelled
      } else {
        TransferFailed
      },
      record.object,
      record.integrity,
      TransferCleanupActive,
      record.source_access_stopped || source_access_stopped,
      record.destination_temporary_reclaimed,
      record.object_use_released,
      false,
    ),
  )
}

///|
pub fn prepare_unknown(
  record : RemoteTransferRecord,
) -> Result[RemoteTransferTransition, RemoteTransferIssue] {
  if record.attempt == TransferDestinationCommitted ||
    record.cleanup == TransferCleanupReleased {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_transition(
      record,
      TransferUnknown,
      record.object,
      record.integrity,
      TransferCleanupUnknown,
      record.source_access_stopped,
      record.destination_temporary_reclaimed,
      record.object_use_released,
      false,
    ),
  )
}

///|
/// Release follows observed ownership, not the failure outcome. A committed
/// destination has independent holding and does not require deletion here.
pub fn prepare_cleanup(
  record : RemoteTransferRecord,
  source_access_stopped : Bool,
  destination_temporary_reclaimed : Bool,
  object_use_released : Bool,
) -> Result[RemoteTransferTransition, RemoteTransferIssue] {
  if record.cleanup == TransferCleanupForceLost ||
    record.cleanup == TransferCleanupRecoveredAfterLoss {
    return Err(InvalidTransfer)
  }
  let source_stopped = record.source_access_stopped || source_access_stopped
  let destination_reclaimed = record.destination_temporary_reclaimed ||
    destination_temporary_reclaimed
  let object_released = record.object_use_released || object_use_released
  let committed = record.attempt == TransferDestinationCommitted
  let failed = record.attempt == TransferFailed ||
    record.attempt == TransferCancelled
  let releasable = source_stopped &&
    object_released &&
    (committed || (failed && destination_reclaimed))
  if !releasable {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_transition(
      record,
      record.attempt,
      record.object,
      record.integrity,
      TransferCleanupReleased,
      source_stopped,
      destination_reclaimed,
      object_released,
      record.destination_material_available,
    ),
  )
}

///|
pub fn transition_projection(
  transition : RemoteTransferTransition,
) -> (Array[Int], Array[Int]) {
  (transition.expected.copy(), transition.next.copy())
}

///|
pub fn transition_journal_key(
  transition : RemoteTransferTransition,
) -> Array[String] {
  [
    request_cid(transition.record.request),
    ..request_journal_key(transition.record.request),
  ]
}

///|
/// Commit only after an adapter durably installs the exact next projection.
pub fn commit_transition(
  transition : RemoteTransferTransition,
  durable : Bool,
) -> Result[RemoteTransferRecord, RemoteTransferIssue] {
  if transition.consumed || !durable || !transition_matches_record(transition) {
    return Err(InvalidTransfer)
  }
  let next = transition.next
  let record = transition.record
  record.revision = next[0]
  record.attempt = match next[1] {
    0 => TransferAdmitted
    1 => TransferCopying
    2 => TransferDestinationCommitted
    3 => TransferFailed
    4 => TransferCancelled
    5 => TransferUnknown
    _ => return Err(InvalidTransfer)
  }
  record.object = match next[2] {
    0 => NoTransferObject
    1 => TransferObjectReserved
    2 => TransferObjectUploading
    3 => TransferObjectSealed
    4 => TransferObjectReclaimed
    _ => return Err(InvalidTransfer)
  }
  record.integrity = match next[3] {
    0 => TransferIntegrityPending
    1 => TransferIntegrityVerified
    2 => TransferIntegrityRejected
    _ => return Err(InvalidTransfer)
  }
  record.cleanup = match next[4] {
    0 => TransferCleanupActive
    1 => TransferCleanupReleased
    2 => TransferCleanupUnknown
    3 => TransferCleanupForceLost
    4 => TransferCleanupRecoveredAfterLoss
    _ => return Err(InvalidTransfer)
  }
  record.source_access_stopped = next[5] == 1
  record.destination_temporary_reclaimed = next[6] == 1
  record.object_use_released = next[7] == 1
  record.destination_material_available = next[8] == 1
  transition.consumed = true
  Ok(record)
}

///|
pub fn record_projection(record : RemoteTransferRecord) -> Array[Int] {
  record_state_projection(record)
}

///|
pub fn record_revision(record : RemoteTransferRecord) -> Int {
  record.revision
}

///|
fn restored_state_valid(record : RemoteTransferRecord) -> Bool {
  if record.revision < 0 {
    return false
  }
  let direct_object = record.request.route == DirectStream &&
    record.object == NoTransferObject &&
    record.object_use_released
  let store_object = record.request.route == TransferStore &&
    (
      record.object == TransferObjectReserved ||
      record.object == TransferObjectUploading ||
      record.object == TransferObjectSealed
    )
  if !direct_object && !store_object {
    return false
  }
  match record.attempt {
    TransferAdmitted =>
      record.revision == 0 &&
      record.integrity == TransferIntegrityPending &&
      record.cleanup == TransferCleanupActive &&
      !record.source_access_stopped &&
      !record.destination_temporary_reclaimed &&
      !record.destination_material_available &&
      (
        record.request.route == DirectStream ||
        record.object == TransferObjectReserved
      )
    TransferCopying =>
      record.revision > 0 &&
      record.cleanup == TransferCleanupActive &&
      !record.destination_temporary_reclaimed &&
      !record.destination_material_available &&
      (if record.source_access_stopped {
        record.revision >= 2 &&
        record.integrity != TransferIntegrityPending &&
        (
          record.request.route == DirectStream ||
          record.object == TransferObjectSealed
        )
      } else {
        record.integrity == TransferIntegrityPending &&
        (
          record.request.route == DirectStream ||
          record.object == TransferObjectUploading
        )
      })
    TransferDestinationCommitted =>
      record.revision >= 3 &&
      record.integrity == TransferIntegrityVerified &&
      record.source_access_stopped &&
      record.destination_temporary_reclaimed &&
      record.destination_material_available &&
      (
        record.cleanup == TransferCleanupActive ||
        record.cleanup == TransferCleanupReleased
      ) &&
      (
        record.request.route == DirectStream ||
        record.object == TransferObjectSealed
      )
    TransferFailed | TransferCancelled =>
      record.revision > 0 &&
      !record.destination_material_available &&
      (
        record.cleanup == TransferCleanupActive ||
        record.cleanup == TransferCleanupReleased
      ) &&
      (
        record.cleanup != TransferCleanupReleased ||
        (
          record.source_access_stopped &&
          record.destination_temporary_reclaimed &&
          record.object_use_released
        )
      )
    TransferUnknown =>
      record.revision > 0 &&
      record.cleanup == TransferCleanupUnknown &&
      !record.destination_material_available
  }
}

///|
/// Restore only a closed durable state. The journal supplies physical
/// persistence; MoonBit remains the authority for valid state combinations.
pub fn restore_record(
  request : RemoteTransferRequest,
  state : Array[Int],
) -> Result[RemoteTransferRecord, RemoteTransferIssue] {
  if !valid_request_fields(request) || state.length() != 9 {
    return Err(InvalidTransfer)
  }
  let record : RemoteTransferRecord = {
    request,
    revision: state[0],
    attempt: match state[1] {
      0 => TransferAdmitted
      1 => TransferCopying
      2 => TransferDestinationCommitted
      3 => TransferFailed
      4 => TransferCancelled
      5 => TransferUnknown
      _ => return Err(InvalidTransfer)
    },
    object: match state[2] {
      0 => NoTransferObject
      1 => TransferObjectReserved
      2 => TransferObjectUploading
      3 => TransferObjectSealed
      4 => TransferObjectReclaimed
      _ => return Err(InvalidTransfer)
    },
    integrity: match state[3] {
      0 => TransferIntegrityPending
      1 => TransferIntegrityVerified
      2 => TransferIntegrityRejected
      _ => return Err(InvalidTransfer)
    },
    cleanup: match state[4] {
      0 => TransferCleanupActive
      1 => TransferCleanupReleased
      2 => TransferCleanupUnknown
      3 => TransferCleanupForceLost
      4 => TransferCleanupRecoveredAfterLoss
      _ => return Err(InvalidTransfer)
    },
    source_access_stopped: state[5] == 1,
    destination_temporary_reclaimed: state[6] == 1,
    object_use_released: state[7] == 1,
    destination_material_available: state[8] == 1,
  }
  for index = 5; index < 9; index = index + 1 {
    if state[index] != 0 && state[index] != 1 {
      return Err(InvalidTransfer)
    }
  }
  if restored_state_valid(record) {
    Ok(record)
  } else {
    Err(InvalidTransfer)
  }
}
