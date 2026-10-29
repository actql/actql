///|
/// Internal Host task outcome is separate from publication and delivery.
pub(all) enum HostTaskRunOutcome {
  HostTasksCompleted
  HostTasksFailed
  HostTaskRunInvalid
} derive(Eq, Debug)

///|
pub fn prepare_host_task_run_outcome(
  failed : Bool,
  run_finished : Bool,
) -> HostTaskRunOutcome {
  if failed {
    return HostTasksFailed
  }
  if run_finished {
    return HostTasksCompleted
  }
  HostTaskRunInvalid
}

///|
pub fn host_task_run_outcome_code(outcome : HostTaskRunOutcome) -> Int {
  match outcome {
    HostTasksCompleted => 0
    HostTasksFailed => 1
    HostTaskRunInvalid => 2
  }
}
