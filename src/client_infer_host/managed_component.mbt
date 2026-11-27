///|
/// Adapt the existing Model execution to the common Local task lifecycle.
/// Selection, capacity, inputs and Run admission remain with their existing
/// owners. The Host retains typed Model failures when projecting to the Local
/// provider issue. Work reports are deltas, never the component's total.
pub fn local_component(
  active : Execution,
  project_issue : (Issue) -> @connector.FixedComputeIssue,
  retain_completed? : (Execution) -> Bool = _ => true,
  allow_cleanup? : (Execution) -> Bool = _ => true,
  host_await_io? : Bool = false,
  original_step? : (
    (Execution) -> Result[Unit, @connector.FixedComputeIssue],
    (Execution, Bool) -> Result[Unit, @connector.FixedComputeIssue],
  )? = None,
  output_workspace? : @relation.GeneratedSequence? = None,
  fund_original_phases? : Bool = false,
) -> Result[@local.ManagedProviderExecution, Issue] {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Input) ||
    !execution_input_unadvanced(active) ||
    !(active.local_component_binding is Unbound) {
    return Err(InvalidAdvance)
  }
  if output_workspace is Some(sequence) &&
    (
      !host_await_io ||
      !@relation.generated_output_workspace_matches(
        sequence,
        @publication_host.client_infer_occurrence_preparation(active.occurrence),
        @pipeline.Step(active.step),
      )
    ) {
    return Err(InvalidAdvance)
  }
  if fund_original_phases &&
    !(output_workspace is Some(_) &&
    active.identity_body is Some(_) &&
    active.original_preparation
    is Some({ read: Claimed(_), shared_mock: true, .. }) &&
    active.run_binding is Some(_) &&
    active.plan is Some(_)) {
    return Err(InvalidAdvance)
  }
  active.local_component_binding = if output_workspace is Some(sequence) {
    WithLocalOutputWorkspace(sequence, fund_original_phases)
  } else if host_await_io {
    WithHostIo
  } else {
    Synchronous
  }
  // The original producer's completed work stays in the cumulative report.
  // Local owns only new deltas from this fresh component entrance onward.
  let charged = Ref(active.entry_work)
  Ok(
    @local.managed_provider_execution_with_retained_completion(
      quantum => {
        // A stopped original does not need an Account snapshot to advance
        // cancellation. For regular polls Core still performs the one advance.
        let original = if active.cancelled { None } else { original_step }
        if original is Some((enter, _)) {
          match enter(active) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
        }
        let polled = advance(active, quantum)
        let returned = match original {
          Some((_, leave)) => leave(active, polled is Ok(_))
          None => Ok(())
        }
        let poll = match polled {
          Ok(value) => value
          Err(issue) => return Err(project_issue(issue))
        }
        if returned is Err(issue) {
          return Err(issue)
        }
        let total = match poll {
          Continue(work~)
          | AwaitIo(work~)
          | Waiting(work~)
          | Settling(_, work~)
          | Complete(_, work~)
          | Failed(_, work~)
          | Stopped(work~) => work
        }
        if total < charged.val || total - charged.val > quantum.to_int64() {
          return Err(project_issue(InvalidAdvance))
        }
        let delta = total - charged.val
        charged.val = total
        match poll {
          Continue(_) => Ok(@local.managed_provider_continue(delta, delta))
          // Only the installed Host that owns the physical wake can wait.
          AwaitIo(_) =>
            if active.local_component_binding
              is (WithHostIo | WithLocalOutputWorkspace(_, _)) {
              Ok(@local.managed_provider_await_io(delta, delta))
            } else {
              Err(project_issue(InvalidAdvance))
            }
          Waiting(_) => Ok(@local.managed_provider_waiting(delta, delta))
          Settling(slot, ..) =>
            Ok(@local.managed_provider_settling(slot, delta, delta))
          Complete(output, ..) => {
            // The Host can borrow the original accepted capture/output
            // before Local attempts scratch cleanup. Store custody may not
            // be replaced by replaying the Model after task completion.
            if !retain_completed(active) {
              return Ok(
                @local.managed_provider_failed(
                  project_issue(InvalidAdvance),
                  delta,
                  delta,
                ),
              )
            }
            Ok(@local.managed_provider_complete(output, delta, delta))
          }
          Failed(issue, ..) =>
            Ok(
              @local.managed_provider_failed(project_issue(issue), delta, delta),
            )
          Stopped(_) => Ok(@local.managed_provider_stopped_poll(delta, delta))
        }
      },
      () => cancel(active),
      () => execution_stopped(active),
      () => {
        // The installed Host may still need stopped attempt evidence even
        // when no accepted output exists to pin the component. Physical stop
        // does not grant the enclosing Local task permission to reclaim it.
        if !allow_cleanup(active) {
          Ok(false)
        } else {
          cleanup(active).map_err(project_issue)
        }
      },
      () => completed_original_component_scratch_retained(active),
    ),
  )
}

///|
// A nominal OutputUse pins the stopped Model and its original Read while
// Local drops only its driver scratch. Publication separately checks the
// handed-off Read, which can still include this very scratch reservation.
fn completed_original_component_scratch_retained(active : Execution) -> Bool {
  guard !(active.local_component_binding is Unbound) && active.output_uses > 0 else {
    return false
  }
  if !(active.local_component_binding is WithLocalOutputWorkspace(_, _)) {
    return original_infer_publication_owner_current(active)
  }
  execution_stopped(active) &&
  !active.cancelled &&
  !active.reclaimed &&
  active.completed is Some(_) &&
  active.rows is Some(_) &&
  active.model is Some(_) &&
  active.call_scope is Some(_) &&
  active.original_preparation
  is Some({ startup: Some(_), read: Claimed(_), .. }) &&
  active.run_binding is Some(_) &&
  active.plan is Some(_)
}
