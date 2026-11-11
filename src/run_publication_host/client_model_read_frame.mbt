///|
pub(all) enum ClientModelReadFrameIssue {
  ForeignRun
  Frame(@resources.ImportedChildLedgerIssue)
}

///|
// This is the original scope's existing census, not a newly issued Model
// allowance. A finished group member must not borrow its still-live siblings.
fn client_model_read_frame_scope_current(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  if scope.finished ||
    !client_model_read_scope_live(scope, compiled, definition, plan) {
    return false
  }
  if scope.group is Some(group) {
    if group.busy || group.closing || group.closed {
      return false
    }
    for original in group.scopes {
      if physical_equal(original, scope) {
        return true
      }
    }
    return false
  }
  true
}

///|
/// Observe the same physical Request frame before the Model supplier enters.
/// It neither takes the frame nor reserves, admits, starts or sends a Model.
/// Its Result/issue constructors require an already funded enclosing scope.
pub fn check_client_model_read_frame(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, ClientModelReadFrameIssue] {
  if !client_model_read_frame_scope_current(scope, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  match @resources.check_imported_original_child_ledger(frame, scope.ledger) {
    Err(issue) => return Err(Frame(issue))
    Ok(_) => ()
  }
  // Imported currentness can reenter and finish the same Model scope.
  check_client_model_read_frame_retained(
    scope, compiled, definition, plan, frame,
  )
}

///|
/// Callback-free final fence after the Native issuer's physical observation.
/// No Ledger projection, capacity grant or cleanup acknowledgement is issued.
pub fn check_client_model_read_frame_retained(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  frame : @resources.ImportedChildLedger,
) -> Result[Unit, ClientModelReadFrameIssue] {
  if !client_model_read_frame_scope_current(scope, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.check_imported_original_child_ledger_retained(frame, scope.ledger).map_err(issue => {
      Frame(issue)
    },
  )
}
