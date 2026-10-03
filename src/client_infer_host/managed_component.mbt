///|
/// Adapt the existing Model execution to the common Local task lifecycle.
/// Selection, capacity, inputs and Run admission remain with their existing
/// owners. The Host retains typed Model failures when projecting to the Local
/// provider issue. Work reports are deltas, never the component's total.
pub fn local_component(
  active : Execution,
  project_issue : (Issue) -> @connector.FixedComputeIssue,
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
          Complete(output, ..) =>
            Ok(@local.managed_provider_complete(output, delta, delta))
          Failed(issue, ..) =>
            Ok(
              @local.managed_provider_failed(project_issue(issue), delta, delta),
            )
          Stopped(_) => Ok(@local.managed_provider_stopped_poll(delta, delta))
        }
      },
      () => cancel(active),
      () => execution_stopped(active),
      () => cleanup(active).map_err(project_issue),
    ),
  )
}
