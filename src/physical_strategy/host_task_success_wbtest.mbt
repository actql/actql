///|
test "Host task success requires readiness retention settlement and binding" {
  assert_eq(
    prepare_host_task_success_step(
      false, false, false, false, true, false, false, true, false, false,
    ),
    HostTaskCheckSiteCompletion,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, false, false, false, true, false, false, true, false, false,
    ),
    HostTaskRejectSiteCompletion,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, false, false, true, false, false, true, false, false,
    ),
    HostTaskCheckCommonCompletion,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, true, true, true, false, false, true, false, false,
    ),
    HostTaskRetainConnectorOutput,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, true, true, false, false, false, false, false, false,
    ),
    HostTaskRetainCoreOutput,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, true, true, true, true, false, true, false, false,
    ),
    HostTaskSettleSiteOperation,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, true, true, true, true, true, true, false, false,
    ),
    HostTaskValidateManagedBinding,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, true, true, true, true, true, true, true, false,
    ),
    HostTaskRejectManagedBinding,
  )
  assert_eq(
    prepare_host_task_success_step(
      true, true, true, true, true, true, true, true, true, true,
    ),
    HostTaskSuccessFinished,
  )
  assert_eq(
    prepare_host_task_success_step(
      false, true, false, false, true, false, false, false, false, false,
    ),
    HostTaskSuccessInvalid,
  )
}
