///|
/// Initial release progression for prepared Result payloads after publication
/// fails. Payloads are visited in reverse construction order; the adapter
/// observes physical status and performs the selected release operation.
pub(all) enum PublicationPreparedReleaseAction {
  PublicationInspectPreparedRelease
  PublicationReleasePrepared
  PublicationAdvancePreparedRelease
  PublicationPreparedReleaseFinished
  PublicationPreparedReleaseInvalid
} derive(Eq, Debug)

///|
pub fn prepare_publication_prepared_release_step(
  current_index : Int,
  owner_count : Int,
  status_checked : Bool,
  pending : Bool,
  release_attempted : Bool,
) -> PublicationPreparedReleaseAction {
  if owner_count < 0 ||
    current_index < -1 ||
    current_index >= owner_count ||
    (release_attempted && !status_checked) {
    return PublicationPreparedReleaseInvalid
  }
  if current_index == -1 {
    return PublicationPreparedReleaseFinished
  }
  if !status_checked {
    return PublicationInspectPreparedRelease
  }
  if !pending || release_attempted {
    return PublicationAdvancePreparedRelease
  }
  PublicationReleasePrepared
}

///|
pub fn publication_prepared_release_action_code(
  action : PublicationPreparedReleaseAction,
) -> Int {
  match action {
    PublicationInspectPreparedRelease => 0
    PublicationReleasePrepared => 1
    PublicationAdvancePreparedRelease => 2
    PublicationPreparedReleaseFinished => 3
    PublicationPreparedReleaseInvalid => 4
  }
}

///|
/// Retry every independent cleanup owner once per call. One failure cannot
/// suppress a later owner, and diagnostic errors do not become ownership.
pub(all) enum PublicationCleanupOwnerAction {
  PublicationInspectCleanupOwner
  PublicationRetryCleanupOwner
  PublicationAdvanceCleanupOwner
  PublicationCleanupOwnersFinished
  PublicationCleanupOwnerInvalid
} derive(Eq, Debug)

///|
pub fn prepare_publication_cleanup_owner_step(
  current_index : Int,
  owner_count : Int,
  status_checked : Bool,
  pending : Bool,
  retry_available : Bool,
  retry_attempted : Bool,
) -> PublicationCleanupOwnerAction {
  if owner_count < 0 ||
    current_index < 0 ||
    current_index > owner_count ||
    (retry_attempted && !status_checked) {
    return PublicationCleanupOwnerInvalid
  }
  if current_index == owner_count {
    return PublicationCleanupOwnersFinished
  }
  if !status_checked {
    return PublicationInspectCleanupOwner
  }
  if pending && retry_available && !retry_attempted {
    return PublicationRetryCleanupOwner
  }
  PublicationAdvanceCleanupOwner
}

///|
pub fn publication_cleanup_owner_action_code(
  action : PublicationCleanupOwnerAction,
) -> Int {
  match action {
    PublicationInspectCleanupOwner => 0
    PublicationRetryCleanupOwner => 1
    PublicationAdvanceCleanupOwner => 2
    PublicationCleanupOwnersFinished => 3
    PublicationCleanupOwnerInvalid => 4
  }
}

///|
/// Cleanup progression for one failed durable Result payload export. Writer
/// reclamation, prepared custody release, and logical export cancellation are
/// separate responsibilities and are attempted in that order.
pub(all) enum DurablePayloadFailureAction {
  DurablePayloadCancelWriter
  DurablePayloadReleasePrepared
  DurablePayloadCancelExport
  DurablePayloadFailureFinished
  DurablePayloadFailureInvalid
} derive(Eq, Debug)

///|
pub fn prepare_durable_payload_failure_step(
  writer_exists : Bool,
  writer_sealed : Bool,
  writer_cancel_attempted : Bool,
  prepared_pending : Bool,
  prepared_release_attempted : Bool,
  export_exists : Bool,
  export_released : Bool,
  export_cancel_attempted : Bool,
) -> DurablePayloadFailureAction {
  if (writer_sealed && !writer_exists) ||
    (writer_cancel_attempted && writer_sealed) ||
    (export_released && !export_exists) {
    return DurablePayloadFailureInvalid
  }
  if writer_exists && !writer_sealed && !writer_cancel_attempted {
    return DurablePayloadCancelWriter
  }
  if prepared_pending && !prepared_release_attempted {
    return DurablePayloadReleasePrepared
  }
  if export_exists && !export_released && !export_cancel_attempted {
    return DurablePayloadCancelExport
  }
  DurablePayloadFailureFinished
}

///|
pub fn durable_payload_failure_action_code(
  action : DurablePayloadFailureAction,
) -> Int {
  match action {
    DurablePayloadCancelWriter => 0
    DurablePayloadReleasePrepared => 1
    DurablePayloadCancelExport => 2
    DurablePayloadFailureFinished => 3
    DurablePayloadFailureInvalid => 4
  }
}
