///|
/// Routing-index tests only: no report, Review, Ledger or authority is mocked.
test "Effect current routing selects the exact task and does not adopt a foreign attempt" {
  let original = holder_custody_test_request("task_1", "effect-original")
  let task = new_holder_task_custody(original, None, None, None)
  let identity = @remote.dispatch_request_identity(original)
  let tasks : Map[String, HolderTaskCustody] = Map([(identity, task)])
  assert_true(
    holder_effect_current_task(tasks, original) is Some(selected) &&
    physical_equal(selected, task),
  )
  let foreign = holder_custody_test_request("task_1", "effect-foreign")
  assert_true(holder_effect_current_task(tasks, foreign) is None)
  // An index-key substitution still cannot select a different task owner.
  tasks.set(@remote.dispatch_request_identity(foreign), task)
  assert_true(holder_effect_current_task(tasks, foreign) is None)
  assert_true(task.effect_review is None)
}

///|
test "Effect current routing preserves pending release observation without releasing task custody" {
  let request = holder_custody_test_request("task_1", "effect-release")
  let task = new_holder_task_custody(request, None, None, None)
  let tasks : Map[String, HolderTaskCustody] = Map([
    (@remote.dispatch_request_identity(request), task),
  ])
  task.release_requested = true
  assert_true(holder_effect_current_task(tasks, request) is Some(_))
  assert_false(task.released)
  assert_true(task.release_requested)
  // Closing an absent review grants no physical cleanup or release proof.
  assert_true(close_holder_effect_review(task))
  assert_false(task.released)
  task.released = true
  assert_true(holder_effect_current_task(tasks, request) is None)
}
