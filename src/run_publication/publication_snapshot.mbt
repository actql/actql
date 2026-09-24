///|
/// One current publication observation, separate from immutable Run outcome
/// and current per-Result availability.
pub(all) enum PublicationSnapshotState {
  NotStarted
  Preparing
  Committing
  PublicationUnknown
  Succeeded
  Failed
  Cancelled
} derive(Eq, Debug)

///|
/// An index query failure is not evidence that the index is absent.
pub(all) enum PublicationIndexObservation {
  IndexConfirmedAbsent
  IndexQueryUnknown
  IndexCommitted(PublicationContract)
}

///|
pub struct PublicationSnapshot {
  state : PublicationSnapshotState
  evidence_cid : String?
}

///|
pub fn publication_snapshot_state(
  value : PublicationSnapshot,
) -> PublicationSnapshotState {
  value.state
}

///|
pub fn publication_snapshot_evidence_cid(
  value : PublicationSnapshot,
) -> String? {
  value.evidence_cid
}

///|
pub fn publication_snapshot_state_text(value : PublicationSnapshot) -> String {
  match value.state {
    NotStarted => "not_started"
    Preparing => "preparing"
    Committing => "committing"
    PublicationUnknown => "publication_unknown"
    Succeeded => "succeeded"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
pub(all) enum PublicationSnapshotIssue {
  IndexObservationUnknown
  WrongRecord
  WrongIndex
  MissingRecord
  AttemptMismatch
  IndexMismatch
  ContradictoryRecord
} derive(Eq, Debug)

///|
/// Project the latest admitted attempt record after an authoritative index
/// observation. The caller must first validate that the record is the latest
/// member of its append-only chain; this function never retries publication.
pub fn project_publication_snapshot(
  record : PublicationContract?,
  index : PublicationIndexObservation,
) -> Result[PublicationSnapshot, PublicationSnapshotIssue] {
  if index is IndexQueryUnknown {
    return Err(IndexObservationUnknown)
  }
  if record is Some(value) && value.name != "publication_record" {
    return Err(WrongRecord)
  }
  match index {
    IndexConfirmedAbsent =>
      match record {
        None => Ok({ state: NotStarted, evidence_cid: None, })
        Some(value) => {
          let state = match publication_record_state(value) {
            Some("preparing") => PublicationSnapshotState::Preparing
            Some("committing") => PublicationSnapshotState::Committing
            Some("publication_unknown") =>
              PublicationSnapshotState::PublicationUnknown
            Some("failed") => PublicationSnapshotState::Failed
            Some("cancelled") => PublicationSnapshotState::Cancelled
            _ => return Err(ContradictoryRecord)
          }
          Ok({ state, evidence_cid: Some(value.identity), })
        }
      }
    IndexCommitted(entry) => {
      if entry.name != "public_index_entry" {
        return Err(WrongIndex)
      }
      guard record is Some(value) else { return Err(MissingRecord) }
      if contract_string(value, "publication_attempt_cid") !=
        contract_string(entry, "publication_attempt_cid") {
        return Err(AttemptMismatch)
      }
      if contract_string(value, "public_index_entry_cid") is Some(cid) &&
        cid != entry.identity {
        return Err(IndexMismatch)
      }
      match publication_record_state(value) {
        Some("committing") | Some("publication_unknown") | Some("succeeded") =>
          Ok({ state: Succeeded, evidence_cid: Some(entry.identity), })
        _ => Err(ContradictoryRecord)
      }
    }
    IndexQueryUnknown => Err(IndexObservationUnknown)
  }
}
