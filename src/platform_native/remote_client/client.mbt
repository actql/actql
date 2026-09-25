///|
pub(all) enum NativeRemoteClientIssue {
  UnsupportedTarget
  Closed
  Http(@http.NativeHttpIssue)
  Journal(@journal.NativeRemoteJournalIssue)
  Protocol(@remote.DispatchIssue)
  HttpStatus(Int)
  InvalidUtf8
  NotAuthorized
  OutcomeUnknownPersistence(
    @journal.NativeRemoteJournalIssue,
    NativeRemoteClientIssue
  )
}

///|
/// Account-configuration tuple for dispatching one checked task to a remote
/// Site: the Run owner's trusted Host principal sends the selected
/// registration to the named Site. The Site keeps its own mTLS and authority
/// checks; this is the Run owner's decision, not a Site-side state machine.
pub fn remote_dispatch_access_tuple(
  principal : String,
  request : @remote.DispatchRequest,
) -> @authorization.AccessTuple {
  {
    principal,
    connection: @remote.dispatch_request_execution_scope(request)[0],
    resource: @remote.dispatch_request_connector_registration(request),
    operation: "write",
  }
}

///|
/// Only an evaluated `AuthorizedForDispatch` admits a remote dispatch. A Host
/// permit must also be bound to this exact dispatch scope: the Activation
/// boundary, the Site/registration tuple and the checked Run definition.
pub fn remote_dispatch_authorized(
  action : @authorization.RuntimeAction,
  request : @remote.DispatchRequest,
) -> Bool {
  match action {
    AuthorizedForDispatch(AccountAllow(_)) => true
    AuthorizedForDispatch(HostPermit(subject, _, _)) =>
      subject.boundary == Activation &&
      subject.tuple ==
      remote_dispatch_access_tuple(subject.tuple.principal, request) &&
      subject.subject_cid == @remote.dispatch_request_task_scope(request).0
    _ => false
  }
}
