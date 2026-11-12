///|
test "selected 512MiB collection preserves retention refusal and retires original cleanup" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(536870912L),
    execution_bytes=Some(536870912L),
  ).unwrap()
  let original : Ref[LocalValuesExecutionIssue?] = Ref(None)
  collection_request_publication_case(
    100000,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
    actual_request_profile=true,
    diagnostic_failure=Some(original),
  )
  assert_true(
    original.val
    is Some(Driver(@local_driver.Execution(Physical(RetentionLimit)))),
  )
}
