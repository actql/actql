///|
/// One outbound control occurrence. A terminal observation means only that
/// the Site posted its exact durable record; Coordinator completion remains a
/// separate common-Host decision.
pub(all) enum NativeRemoteAgentOutcome {
  Idle
  DispatchObserved(String, Int)
  QueryObserved(String, Int)
  QueryNotSeen(String)
  ReleaseObserved(String, Int)
  ReleasePending(String, Int)
}

///|
/// Physical transport failure and Site execution failure remain distinct. A
/// completion whose terminal observation is unknown is returned intact so a
/// caller can reconcile it without authorizing another execution.
pub(all) enum NativeRemoteAgentIssue {
  Client(@client.NativeRemoteClientIssue)
  Runtime(@runtime.NativeRemoteRuntimeIssue)
  RuntimeObserved(@runtime.NativeRemoteRuntimeIssue, Int)
  RuntimeObservationUnknown(
    @runtime.NativeRemoteRuntimeIssue,
    @client.NativeRemoteClientIssue
  )
  CompletionObservationUnknown(
    @runtime.NativeRemoteRuntimeCompletion,
    @client.NativeRemoteClientIssue
  )
  ObservationMissing
  ObservationMismatch
}

///|
/// Advance one already-decoded outbound operation. The injected observation
/// functions keep transport effects outside the common progression decision.
pub fn advance_native_outbound_operation(
  runtime : @runtime.NativeRemoteRuntime,
  operation : @remote.RemotePollOperation?,
  acknowledge_acceptance : (@remote.DispatchRequest) -> Result[
    @remote.DispatchRecord,
    @client.NativeRemoteClientIssue,
  ],
  acknowledge_status : (@remote.DispatchRequest) -> Result[
    @remote.DispatchRecord?,
    @client.NativeRemoteClientIssue,
  ],
) -> Result[NativeRemoteAgentOutcome, NativeRemoteAgentIssue] {
  match operation {
    None => Ok(Idle)
    Some(@remote.Query(request)) =>
      match acknowledge_status(request) {
        Ok(Some(record)) => {
          if !@remote.dispatch_record_matches_request(record, request) {
            return Err(ObservationMismatch)
          }
          Ok(
            QueryObserved(
              @remote.dispatch_request_identity(request),
              @remote.dispatch_record_revision(record),
            ),
          )
        }
        Ok(None) => Ok(QueryNotSeen(@remote.dispatch_request_identity(request)))
        Err(issue) => Err(Client(issue))
      }
    Some(@remote.Release(request)) => {
      let released = runtime.release(request)
      match acknowledge_status(request) {
        Ok(Some(record)) => {
          if !@remote.dispatch_record_matches_request(record, request) {
            return Err(ObservationMismatch)
          }
          let revision = @remote.dispatch_record_revision(record)
          match released {
            Err(issue) => Err(RuntimeObserved(issue, revision))
            Ok(_) =>
              if @remote.remote_runtime_record_released(record) {
                Ok(
                  ReleaseObserved(
                    @remote.dispatch_request_identity(request),
                    revision,
                  ),
                )
              } else {
                Ok(
                  ReleasePending(
                    @remote.dispatch_request_identity(request),
                    revision,
                  ),
                )
              }
          }
        }
        Ok(None) => Err(ObservationMissing)
        Err(observation_issue) =>
          match released {
            Err(runtime_issue) =>
              Err(RuntimeObservationUnknown(runtime_issue, observation_issue))
            Ok(_) => Err(Client(observation_issue))
          }
      }
    }
    Some(@remote.Dispatch(dispatch)) => {
      let request = @remote.remote_poll_dispatch_request(dispatch)
      let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
      let accepted = [false]
      let acceptance_mismatch = [false]
      let acceptance_failure : Array[@client.NativeRemoteClientIssue?] = [None]
      let executed = runtime.start_after_acceptance(request, binding, _record => {
        match acknowledge_acceptance(request) {
          Ok(record) => {
            if !@remote.dispatch_record_matches_request(record, request) {
              acceptance_mismatch[0] = true
              return false
            }
            accepted[0] = true
            true
          }
          Err(issue) => {
            acceptance_failure[0] = Some(issue)
            false
          }
        }
      })
      match executed {
        Ok(completion) =>
          match acknowledge_status(request) {
            Ok(Some(record)) => {
              if !@remote.dispatch_record_matches_request(record, request) {
                return Err(ObservationMismatch)
              }
              let revision = @remote.dispatch_record_revision(record)
              if revision != completion.revision {
                Err(ObservationMismatch)
              } else {
                Ok(DispatchObserved(completion.dispatch_request_cid, revision))
              }
            }
            Ok(None) => Err(ObservationMissing)
            Err(issue) => Err(CompletionObservationUnknown(completion, issue))
          }
        Err(runtime_issue) =>
          if acceptance_mismatch[0] {
            Err(ObservationMismatch)
          } else {
            match acceptance_failure[0] {
              Some(issue) => Err(Client(issue))
              None =>
                if !accepted[0] {
                  Err(Runtime(runtime_issue))
                } else {
                  match acknowledge_status(request) {
                    Ok(Some(record)) => {
                      if !@remote.dispatch_record_matches_request(
                          record, request,
                        ) {
                        return Err(ObservationMismatch)
                      }
                      Err(
                        RuntimeObserved(
                          runtime_issue,
                          @remote.dispatch_record_revision(record),
                        ),
                      )
                    }
                    Ok(None) => Err(ObservationMissing)
                    Err(issue) =>
                      Err(RuntimeObservationUnknown(runtime_issue, issue))
                  }
                }
            }
          }
      }
    }
  }
}

///|
/// Poll once through the authenticated outbound transport. A dispatch is made
/// durable before its acceptance is posted, and physical execution begins
/// only after that post succeeds. The terminal Site record is then posted as
/// a separate observation. Query operations never enter runtime admission;
/// release operations can only advance an existing exact output owner.
pub fn run_native_outbound_site_occurrence(
  runtime : @runtime.NativeRemoteRuntime,
  journal : @journal.Journal,
  client : @http.Client,
  poll_url : String,
  observation_url : String,
) -> Result[NativeRemoteAgentOutcome, NativeRemoteAgentIssue] {
  let operation = match @client.poll_operation(client, poll_url) {
    Ok(value) => value
    Err(issue) => return Err(Client(issue))
  }
  advance_native_outbound_operation(
    runtime,
    operation,
    request => {
      @client.acknowledge_acceptance(journal, client, observation_url, request)
    },
    request => {
      @client.acknowledge_status(journal, client, observation_url, request)
    },
  )
}
