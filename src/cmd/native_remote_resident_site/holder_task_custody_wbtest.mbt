///|
fn holder_custody_test_request(
  task : String,
  dispatch : String,
) -> @remote.DispatchRequest {
  let cid = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @remote.prepare_dispatch_request(
    "holder-test-coordinator", cid, task, 1, dispatch, "holder-test-site", 1, cid,
    "local", "local/1", "strategy/1", cid, cid, cid, cid, cid,
  ).unwrap()
}

///|
/// These tests exercise the command's physical-custody index. They do not
/// construct a consumer capability, completion, holding or cleanup proof.
test "holder keeps three exact task entries and rejects a replacement successor" {
  let first = holder_custody_test_request("task_0", "source")
  let second = holder_custody_test_request("task_1", "middle")
  let third = holder_custody_test_request("task_2", "last")
  let first_id = @remote.dispatch_request_identity(first)
  let second_id = @remote.dispatch_request_identity(second)
  let third_id = @remote.dispatch_request_identity(third)
  let root = new_holder_task_custody(first, None, None, None)
  let middle = new_holder_task_custody(second, None, None, Some(first_id))
  let last = new_holder_task_custody(third, None, None, Some(second_id))
  let tasks : Map[String, HolderTaskCustody] = Map([(first_id, root)])
  let order = [first_id]
  assert_true(remember_holder_successor(tasks, order, root, middle) is Some(_))
  assert_true(remember_holder_successor(tasks, order, middle, last) is Some(_))
  assert_eq(order, [first_id, second_id, third_id])
  assert_eq(root.successor_identity, Some(second_id))
  assert_eq(middle.successor_identity, Some(third_id))
  let replay = new_holder_task_custody(second, None, None, Some(first_id))
  let restored = remember_holder_successor(tasks, order, root, replay).unwrap()
  assert_true(physical_equal(restored, middle))
  assert_eq(order.length(), 3)
  let replacement = new_holder_task_custody(
    holder_custody_test_request("task_1", "another-attempt"),
    None,
    None,
    Some(first_id),
  )
  assert_true(
    remember_holder_successor(tasks, order, root, replacement) is None,
  )
  assert_eq(order, [first_id, second_id, third_id])
  assert_eq(root.successor_identity, Some(second_id))
  assert_true(physical_equal(tasks.get(second_id).unwrap(), middle))
}

///|
test "deferred producer release permits its admitted successor without replacing custody" {
  let request = holder_custody_test_request("task_0", "deferred-source")
  let identity = @remote.dispatch_request_identity(request)
  let root = new_holder_task_custody(request, None, None, None)
  let tasks : Map[String, HolderTaskCustody] = Map([(identity, root)])
  let order = [identity]
  root.release_requested = true
  let child = new_holder_task_custody(
    holder_custody_test_request("task_1", "deferred-consumer"),
    None,
    None,
    Some(identity),
  )
  // The caller has already admitted the exact existing handoff's consumer.
  // Remembering an early parent release must not block that completion path.
  assert_true(remember_holder_successor(tasks, order, root, child) is Some(_))
  assert_true(root.release_requested)
  assert_false(holder_successor_released(root, tasks))
  assert_true(
    physical_equal(
      remember_holder_successor(tasks, order, root, child).unwrap(),
      child,
    ),
  )
  root.released = true
  assert_true(remember_holder_successor(tasks, order, root, child) is None)
}

///|
test "EOF cleanup leaves absent and accepted consumers unstarted without fabricating cancellation" {
  let (_, journal, request, _, _) = cleanup_test_open("holder-eof-unstarted")
  assert_true(confirm_holder_consumer_cleanup(journal, request, true))
  assert_true(journal.require(request) is Err(@journal.MissingDispatch))
  assert_false(confirm_holder_consumer_cleanup(journal, request, false))
  let (_, accepted) = journal.accept(request).unwrap()
  let revision = @remote.dispatch_record_revision(accepted)
  assert_true(confirm_holder_consumer_cleanup(journal, request, true))
  let retained = journal.require(request).unwrap()
  assert_true(@remote.remote_runtime_record_startable(retained))
  assert_eq(@remote.dispatch_record_revision(retained), revision)
  assert_eq(journal.start_claimant(request).unwrap(), None)
  assert_false(confirm_holder_consumer_cleanup(journal, request, false))
  assert_true(journal.close())
}

///|
test "EOF cleanup retains a consumer with an unresolved original start claim" {
  let (_, journal, request, _, site) = cleanup_test_open("holder-eof-claimed")
  let (_, record) = journal.accept(request).unwrap()
  let capability = @remote.register_remote_execution_capability(
    site,
    cleanup_test_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    "local",
    "local/1",
    "strategy/1",
    cleanup_test_cid(
      "4444444444444444444444444444444444444444444444444444444444444444",
    ),
  ).unwrap()
  assert_eq(
    journal
    .claim_start(
      @remote.prepare_begin_provisioning(record, capability).unwrap(),
      "original-holder-claim",
    )
    .unwrap(),
    @journal.Won,
  )
  let saved = journal.require(request).unwrap()
  assert_false(confirm_holder_consumer_cleanup(journal, request, true))
  assert_eq(
    journal.start_claimant(request).unwrap(),
    Some("original-holder-claim"),
  )
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    @remote.dispatch_record_revision(saved),
  )
  assert_true(journal.close())
}

///|
test "holder release waits for each descendant and never treats a missing task as released" {
  let root_request = holder_custody_test_request("task_0", "source-release")
  let middle_request = holder_custody_test_request("task_1", "middle-release")
  let last_request = holder_custody_test_request("task_2", "last-release")
  let root_id = @remote.dispatch_request_identity(root_request)
  let middle_id = @remote.dispatch_request_identity(middle_request)
  let root = new_holder_task_custody(root_request, None, None, None)
  let middle = new_holder_task_custody(
    middle_request,
    None,
    None,
    Some(root_id),
  )
  let last = new_holder_task_custody(last_request, None, None, Some(middle_id))
  let tasks : Map[String, HolderTaskCustody] = Map([(root_id, root)])
  let order = [root_id]
  ignore(remember_holder_successor(tasks, order, root, middle).unwrap())
  ignore(remember_holder_successor(tasks, order, middle, last).unwrap())
  root.release_requested = true
  middle.release_requested = true
  assert_false(holder_successor_released(root, tasks))
  assert_false(holder_successor_released(middle, tasks))
  assert_true(holder_successor_released(last, tasks))
  // A child cleanup still pending leaves both ancestors fenced. Only the
  // actual cleanup caller sets each entry's released flag in production.
  last.release_requested = true
  assert_false(holder_successor_released(middle, tasks))
  last.released = true
  assert_true(holder_successor_released(middle, tasks))
  assert_false(holder_successor_released(root, tasks))
  middle.released = true
  assert_true(holder_successor_released(root, tasks))
  tasks.remove(middle_id)
  assert_false(holder_successor_released(root, tasks))
}
