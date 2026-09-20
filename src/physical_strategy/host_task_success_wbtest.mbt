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

///|
test "Host task success progress owns observations and their order" {
  let progress = begin_host_task_success_progress(true, true)
  assert_eq(
    prepare_host_task_success_progress_step(progress),
    HostTaskCheckSiteCompletion,
  )
  assert_true(!record_host_task_common_completion(progress, true))
  assert_true(record_host_task_site_completion(progress, true))
  assert_true(!record_host_task_site_completion(progress, true))
  assert_eq(
    prepare_host_task_success_progress_step(progress),
    HostTaskCheckCommonCompletion,
  )
  assert_true(record_host_task_common_completion(progress, true))
  assert_true(record_host_task_output_retained(progress))
  assert_true(record_host_task_site_operation_settled(progress))
  assert_true(record_host_task_managed_binding(progress, true))
  assert_eq(
    prepare_host_task_success_progress_step(progress),
    HostTaskSuccessFinished,
  )
}

///|
test "Host task success progress preserves negative observations" {
  let site_rejected = begin_host_task_success_progress(false, false)
  assert_true(record_host_task_site_completion(site_rejected, false))
  assert_eq(
    prepare_host_task_success_progress_step(site_rejected),
    HostTaskRejectSiteCompletion,
  )
  let common_rejected = begin_host_task_success_progress(false, false)
  assert_true(record_host_task_site_completion(common_rejected, true))
  assert_true(record_host_task_common_completion(common_rejected, false))
  assert_eq(
    prepare_host_task_success_progress_step(common_rejected),
    HostTaskRejectCommonCompletion,
  )
}
