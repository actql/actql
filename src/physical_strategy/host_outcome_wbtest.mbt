///|
test "Host outcome keeps task failure separate from publication success" {
  assert_eq(prepare_host_task_run_outcome(false, true), HostTasksCompleted)
  assert_eq(prepare_host_task_run_outcome(true, true), HostTasksFailed)
  assert_eq(prepare_host_task_run_outcome(true, false), HostTasksFailed)
  assert_eq(prepare_host_task_run_outcome(false, false), HostTaskRunInvalid)
}
