///|
test "worker selection reply retains the same nominal original and supplies no acquire" {
  let prepared = prepared_reply(0L)
  let host = prepared.original_host().unwrap()
  let reply = installed_arena_worker_selection_reply(host)
  assert_true(physical_equal(reply.original_host(), host))
  assert_eq(reply.issue_family(), 0)
  assert_eq(reply.operation_tag(), 1)
  let selection = reply.original_selection().unwrap()
  let current = current_installed_arena_worker_selection_reply(host, selection)
  assert_eq(current.operation_tag(), 2)
  assert_eq(current.issue_family(), 0)
  assert_true(physical_equal(current.original_selection().unwrap(), selection))
  let (source, recipe, generation) = installed_worker_selection_data(selection).unwrap()
  assert_eq(source, "0123456789012345678901234567890123456789")
  assert_eq(recipe, Bytes::make(32, 17))
  assert_eq(generation, 1L)
  assert_true(physical_equal(selection.host, host))
  assert_true(host.require_current() is Err(@bootstrap.Unavailable))
  assert_false(host.acquisition_started)
  host.try_close().unwrap()
  assert_true(
    installed_worker_selection_data(selection) is Err(@bootstrap.Closing),
  )
}

///|
test "worker selection refuses closing original and never adopts equal DATA" {
  let first = prepared_reply(0L).original_host().unwrap()
  let second = prepared_reply(0L).original_host().unwrap()
  let selected = installed_arena_worker_selection_reply(first)
    .original_selection()
    .unwrap()
  assert_false(physical_equal(selected.host, second))
  first.try_close().unwrap()
  let reply = installed_arena_worker_selection_reply(first)
  assert_true(physical_equal(reply.original_host(), first))
  assert_eq(reply.issue_family(), 4)
  assert_true(reply.original_selection() is None)
  assert_eq(installed_arena_worker_selection_reply(second).issue_family(), 0)
  second.try_close().unwrap()
}

///|
test "worker selection current preserves original refusal and nominal lineage" {
  let first = prepared_reply(0L).original_host().unwrap()
  let second = prepared_reply(0L).original_host().unwrap()
  let selection = installed_arena_worker_selection_reply(first)
    .original_selection()
    .unwrap()
  let foreign = current_installed_arena_worker_selection_reply(
    second, selection,
  )
  assert_eq(foreign.operation_tag(), 2)
  assert_eq(foreign.issue_family(), 2)
  assert_true(physical_equal(foreign.original_host(), second))
  assert_true(foreign.original_selection() is None)
  first.try_close().unwrap()
  let closed = current_installed_arena_worker_selection_reply(first, selection)
  assert_eq(closed.issue_family(), 4)
  assert_true(physical_equal(closed.original_selection().unwrap(), selection))
  second.try_close().unwrap()
}
