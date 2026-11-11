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
    !execution_input_unadvanced(active) ||
    active.local_component_bound {
    return Err(InvalidAdvance)
  }
  active.local_component_bound = true
  // The original producer's completed work stays in the cumulative report.
  // Local owns only new deltas from this fresh component entrance onward.
  let charged = Ref(active.entry_work)
  Ok(
    @local.managed_provider_execution_with_retained_completion(
      quantum => {
        let poll = match advance(active, quantum) {
          Ok(value) => value
          Err(issue) => return Err(project_issue(issue))
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
          // This installed managed profile does not admit persistence polls.
          // Never disguise I/O suspension as a checkpoint or zero-work loop.
          AwaitIo(_) => Err(project_issue(InvalidAdvance))
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
// The actual nominal output borrow keeps the SAME original Model, Read and
// their backing alive. Local can detach only its temporary driver roots; this
// does not reclaim the Model or settle evidence, publication or physical IO.
fn completed_original_component_scratch_retained(active : Execution) -> Bool {
  active.local_component_bound &&
  active.output_uses > 0 &&
  original_infer_publication_owner_current(active)
}
