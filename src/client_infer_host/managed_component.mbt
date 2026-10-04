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
) -> Result[@local.ManagedProviderExecution, Issue] {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Input) ||
    active.work != 0L ||
    active.local_component_bound {
    return Err(InvalidAdvance)
  }
  active.local_component_bound = true
  let charged = Ref(0L)
  Ok(
    @local.managed_provider_execution(
      quantum => {
        let poll = match advance(active, quantum) {
          Ok(value) => value
          Err(issue) => return Err(project_issue(issue))
        }
        let total = match poll {
          Continue(work~)
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
    ),
  )
}
