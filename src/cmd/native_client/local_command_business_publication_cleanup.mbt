///|
// Store methods bracket their own original Read/SQL operations. Do not wrap
// this traversal in another Store flight or a whole-Store SQLite scope.
// Called after the borrowed command callback and before Compute retirement.
fn LocalCommandBusinessOriginal::close_publication_children(
  self : LocalCommandBusinessOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.publication_retired {
    return Ok(())
  }
  if self.publication_attempted && self.publication_result is None {
    // No reply proves that a durable commit did not happen. Keep the exact
    // occurrence, pending payloads, Store, Work and parent for reconciliation.
    return Err(CommandBusinessPublication)
  }
  if self.publication_pending is Some(pending) &&
    self.publication_result is None {
    match pending.cancel() {
      Ok(true) => ()
      Ok(false) => return Err(CommandBusinessPublication)
      Err(issue) => {
        self._retained_publication_cleanup_failure = Some(issue)
        return Err(CommandBusinessPublication)
      }
    }
  }
  // A partial preparation reports original failed generation positions. Only
  // their same retained Store may reclaim them; success here is not a commit.
  if self.publication_failure is Some(Publication(PrepareCleanup(_, failures))) {
    guard self.store is Some(store) && self.publication_results is Some(results) else {
      return Err(CommandBusinessPublication)
    }
    for failure in failures {
      if failure.result < 0 || failure.result >= results.length() {
        return Err(CommandBusinessPublication)
      }
      match
        store.reclaim_payload(results[failure.result].material_generation_cid) {
        Ok(_) => ()
        Err(issue) => return Err(CommandBusinessStore(issue))
      }
    }
  }
  if self.file_publication_failure is Some(CapturedPublication(PrepareCleanup(_, failures))) {
    guard self.store is Some(store) && self.publication_results is Some(results) else {
      return Err(CommandBusinessPublication)
    }
    for failure in failures {
      if failure.result < 0 || failure.result >= results.length() {
        return Err(CommandBusinessPublication)
      }
      match store.reclaim_payload(results[failure.result].material_generation_cid) {
        Ok(_) => ()
        Err(issue) => return Err(CommandBusinessStore(issue))
      }
    }
  }
  // Only managed aliases retire here. Their actual Store/DB, Compute and
  // domain acknowledgements follow separately in the existing parent order.
  self.publication_pending = None
  self._retained_publication_service = None
  self.publication_publisher = None
  self.publication_results = None
  // The borrowed call has returned and its primary presentation is retained
  // by the outer command. Do not keep these Read/business-managed receipts
  // past their domains after the original cancellation/reclamation or known
  // commit reply above. An unconfirmed commit never reaches this retirement.
  self.publication_failure = None
  self.file_publication_failure = None
  self._retained_publication_commit_failure = None
  self._retained_publication_cleanup_failure = None
  self.publication_result = None
  self.run_receipt_original = None
  self.publication_retired = true
  Ok(())
}
