///|
// Pure committed publication DATA, selected only after the actual Store call
// and original return succeeded. It owns no reader, FD, grant or cleanup ACK.
// The existing command capture drops these references on failure and at end.
priv struct NativeLocalCommittedResultObservation {
  store : @publication_store.Store
  namespace_id : String
  authority_scope_cid : String
  run_definition_cid : String
  result_name : String
  result : @publication_store.NativeCommittedResult
}

///|
// The three closed policy/delivery callers already checked this capture's
// actual Read and independent permissions. Trusted Store correspondence does
// not create a second admission frame. Retain only positive immutable facts;
// absence must remain observable after a real publication in this command.
fn local_committed_result_observation(
  store : @publication_store.Store,
  namespace_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  result_name : String,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[
  @publication_store.NativeCommittedResult?,
  NativeClientRunJournalIssue,
] {
  if capture is Some(owner) {
    if owner.closing ||
      owner.read_operation_issue is Some(_) ||
      (owner.read_callback_active && !owner.read_facts_valid) {
      return Err(CustodyLost)
    }
    if owner.read_callback_active {
      guard owner.opening is JournalAcquired(host) &&
        owner.read_facts_valid &&
        host.journal.operation_active else {
        owner.read_operation_issue = Some(OriginalResourceScopePending)
        owner.clear_read_operation_facts()
        return Err(CustodyLost)
      }
      for observed in owner.read_committed_results {
        if physical_equal(observed.store, store) &&
          observed.namespace_id == namespace_id &&
          observed.authority_scope_cid == authority_scope_cid &&
          observed.run_definition_cid == run_definition_cid &&
          observed.result_name == result_name {
          // Association metadata is insufficient. A closed/retiring Store or
          // an unacknowledged original return cannot expose a retained value.
          match store.retained_data_current() {
            Err(issue) => {
              let primary : NativeClientRunJournalIssue = PublicationObservation(
                issue,
              )
              if owner.read_operation_issue is None {
                owner.read_operation_issue = Some(Journal(primary))
              }
              owner.clear_read_operation_facts()
              return Err(primary)
            }
            Ok(_) => return Ok(Some(observed.result))
          }
        }
      }
    }
  }
  // Count an actual Store resolution, never a retained observation hit.
  native_timing_count(43)
  let result = store.resolve_committed_result(
    namespace_id, authority_scope_cid, run_definition_cid, result_name, 65536, 8192,
    64,
  )
  match result {
    Err(issue) => {
      let primary : NativeClientRunJournalIssue = PublicationObservation(issue)
      if capture is Some(owner) && owner.read_callback_active {
        if owner.read_operation_issue is None {
          owner.read_operation_issue = Some(Journal(primary))
        }
        owner.clear_read_operation_facts()
      }
      Err(primary)
    }
    Ok(None) => Ok(None)
    Ok(Some(value)) => {
      if capture is Some(owner) && owner.read_callback_active {
        if !owner.read_facts_valid || owner.read_operation_issue is Some(_) {
          return Err(CustodyLost)
        }
        owner.read_committed_results.push({
          store,
          namespace_id,
          authority_scope_cid,
          run_definition_cid,
          result_name,
          result: value,
        })
      }
      Ok(Some(value))
    }
  }
}
