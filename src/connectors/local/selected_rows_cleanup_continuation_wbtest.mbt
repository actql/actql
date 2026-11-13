///|
test "selected row provider retains its original bounded cleanup continuation" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"filter\":\"id > 0\",\"as\":\"positive\"}]",
  )
  let active = selected_binding_rows_execution(
    sequence,
    managed_provider_relation_input(read),
    chain_lifetime_limits(),
    10000,
    0,
  ).unwrap()
  assert_true(active.cleanup_continuation is Some(_))
  assert_eq(managed_provider_cleanup_continuation(active), -1L)
  cancel_managed_provider(active) |> ignore
  for _ in 0..<100 {
    advance_managed_provider(active, 1).unwrap() |> ignore
    if managed_provider_stopped(active) {
      break
    }
  }
  assert_true(managed_provider_stopped(active))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(managed_provider_cleanup_continuation(active), -1L)
  assert_true(@execution.completed_output_available(source))
}
