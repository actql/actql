///|
// Both parent retirement and sequential File delivery use the same return
// ordering. Reconciling only the lower bridge would lose the Store's mirror;
// closing children first would refuse an outstanding original return.
fn LocalCommandBusinessOriginal::close_result_children_after_return(
  business : LocalCommandBusinessOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  // The Store retains its own return mirror and any unexposed Result child.
  // Recover through that same owner before lower-level scope recovery can
  // consume the physical return without acknowledging the Store's duty.
  if business.store is Some(store) {
    match store.reconcile_original_return() {
      Err(issue) => return Err(CommandBusinessStore(issue))
      Ok(_) => ()
    }
  }
  // A Store open can fail before Work exists. Reconcile the same outstanding
  // route before either its publication children or failed DB are retired.
  if business.operation is Some(operation) {
    match operation.pending_scope() {
      Err(issue) => return Err(CommandStoreOperation(issue))
      Ok(true) =>
        match operation.retry_scope_cleanup() {
          Err(issue) => return Err(CommandStoreOperation(issue))
          Ok(_) => ()
        }
      Ok(false) => ()
    }
  }
  business.close_result_children()
}

///|
// The original Result/Store methods enter and return their own Read/SQL
// scopes. Do not wrap the whole close in another Store/SQL flight. The parent
// has already reconciled the same pending return before reaching this method.
fn LocalCommandBusinessOriginal::close_result_children(
  self : LocalCommandBusinessOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.store is Some(store) {
    // A failed acquisition can retain a Delivery without creating a Session.
    // This closes only that same unexposed child after its original return;
    // false denotes no pending child and never substitutes for a close ACK.
    match store.retry_pending_result_delivery_cleanup() {
      Err(issue) => return Err(CommandBusinessStore(issue))
      Ok(_) => ()
    }
  }
  if self.result_material is Some(receiver) {
    match receiver.close() {
      Err(issue) => {
        if self.result_cleanup_issue is None {
          self.result_cleanup_issue = Some(issue)
        }
        return Err(CommandBusinessResult(issue))
      }
      Ok(_) => ()
    }
  }
  if self.result_sink is Some(sink) {
    match sink.close() {
      Err(issue) => {
        if self.result_cleanup_issue is None {
          self.result_cleanup_issue = Some(issue)
        }
        return Err(CommandBusinessResult(issue))
      }
      Ok(_) => ()
    }
  }
  // A sink may never have been installed. The exact acquired session remains
  // separately retained; a sink error never substitutes for its close ACK.
  if self.result_session is Some(session) {
    match session.close() {
      Err(issue) => {
        if self.result_cleanup_issue is None {
          self.result_cleanup_issue = Some(issue)
        }
        return Err(CommandBusinessResult(issue))
      }
      Ok(_) => ()
    }
  }
  // Keep the independent output Writer/Root until the same session and Store
  // return have acknowledged. A constructor-only failure still owns this duty.
  if self.result_binding is Some(binding) {
    match binding.close_file_output() {
      Err(issue) => return Err(CommandBusinessFileOutput(issue))
      Ok(_) => ()
    }
  }
  // Both Result close entrances return only after the original Store return.
  // Keep even closed aliases until that acknowledgement; no poll/receipt or
  // payload reopen is performed by this cleanup path.
  self.result_material = None
  self.result_sink = None
  self.result_session = None
  self.result_service = None
  self.result_binding = None
  self.result_refusal = None
  // The outer command retains its primary presentation. Retire this last
  // Read-managed diagnostic only after the same session/Store return ACKs,
  // before the parent can retire the actual Read domain.
  self.result_cleanup_issue = None
  Ok(())
}
