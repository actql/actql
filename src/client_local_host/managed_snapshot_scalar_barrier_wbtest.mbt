///|
// Actual checked Source, Task, importer and Ledger. The finite String array
// stands in for Store body custody; this is not a physical Store ACK test.
fn managed_scalar_snapshot_barrier(cancel_on_release : Bool) -> Unit raise {
  let prepared = single_installed_prepared(
    document=(
      #|{"version":"actql/0.1","id":"snapshot-scalar-barrier","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id >= 2"},{"derive":{"label":{"literal":"scalar text"}}},{"select":["id","label"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","label"]}}},{"id":"finish","inputs":{"r":{"result":{"stage":"compute","result":"rows"}}},"steps":[{"filter":"id < 3"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"rows"}}}}
    ),
  )
  let value = captured_tasks_fixture(original=Some(prepared))
  let before = @resources.ledger_usage(value.ledger)
  let (run, dispatch) = metered_tail_dispatch(value)
  let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
  let task : LocalValuesTaskExecution = {
    operations,
    settled: false,
    completed: None,
  }
  let tasks : Array[LocalValuesTaskExecution?] = [None, Some(task), None]
  (operations.execute)().unwrap()
  let released = Ref(false)
  let present = Ref(true)
  let cancel_armed = Ref(false)
  let release_calls = Ref(0)
  let snapshot = (operations.prepare_relation_snapshot)(() => {
      release_calls.val += 1
      if cancel_armed.val && cancel_on_release {
        (operations.request_cancel)() |> ignore
      }
      released.val
    })
    .unwrap()
    .unwrap()
  let parts : Array[String] = []
  let mut saved = false
  for _ in 0..<10000 {
    let progress = (snapshot.advance_save)(32).unwrap()
    parts.push((snapshot.take_output)().unwrap())
    if progress.complete {
      saved = true
      break
    }
  }
  assert_true(saved)
  let content = (snapshot.content)().unwrap()
  (snapshot.release_source)(content.cid, () => present.val).unwrap()
  assert_false((snapshot.source_available)())
  (snapshot.begin_reload)().unwrap()
  let limits = snapshot.frames
  let frames = @publication.prepare_durable_result_row_frames(
    limits.maxBytes,
    limits.maxRows,
    limits.maxRowBytes,
    limits.maxDepth,
    limits.maxFrameBytes,
  ).unwrap()
  for part in parts {
    for
      row in @publication.feed_durable_result_row_frames(
        frames,
        @utf8.encode(part),
      ).unwrap() {
      (snapshot.append_reload)(row).unwrap()
    }
  }
  let usage = @publication.finish_durable_result_row_frames(frames).unwrap()
  assert_eq(usage.bytes, content.bytes)
  @publication.cancel_durable_result_row_frames(frames)
  assert_true((snapshot.finish)() is Err(_))
  (snapshot.finish_reload)().unwrap()
  let reloaded = @resources.ledger_usage(value.ledger)
  // A completed importer does not acknowledge the still-live body or old
  // references, and cannot publish overlap before that original barrier.
  assert_true((snapshot.finish)() is Err(_))
  assert_eq(@resources.ledger_usage(value.ledger), reloaded)
  present.val = false
  parts.clear()
  assert_false((snapshot.cleanup_references)(32))
  released.val = true
  // The body can be gone while the original retained-reference duty remains.
  assert_true((snapshot.finish)() is Err(_))
  let mut cleaned = false
  for _ in 0..<10000 {
    if (snapshot.cleanup_references)(32) {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  assert_eq(@resources.ledger_usage(value.ledger), reloaded)
  cancel_armed.val = true
  if cancel_on_release {
    // Original cancellation also retires the snapshot's restored alias, so
    // the pre-existing phase guard may refuse before the new post-call fence.
    assert_true(
      (snapshot.finish)() is Err(@local_driver.Configuration(InvalidLimits)),
    )
    assert_true(
      (operations.prepare_finalization)(1, operations.storage_bytes, () => true)
      is Err(_),
    )
  } else {
    (snapshot.finish)().unwrap()
    // Finish only changes representation; its original reservation does not
    // shrink or issue a second credit. Later work uses this exact same Task.
    assert_eq(@resources.ledger_usage(value.ledger), reloaded)
    assert_true((snapshot.finish)() is Err(_))
    let payload = Ref(true)
    (operations.prepare_finalization)(1, operations.storage_bytes, () => {
      payload.val
    }).unwrap()
    let mut finished = false
    for _ in 0..<10000 {
      if (operations.advance_finalization)(1).unwrap().complete {
        finished = true
        break
      }
    }
    assert_true(finished)
    (operations.settle)().unwrap()
    task.settled = true
    task.completed = Some(
      (operations.complete)(1, operations.storage_bytes, () => payload.val).unwrap(),
    )
    payload.val = false
  }
  assert_true(release_calls.val >= 3)
  let mut closed = false
  for _ in 0..<10000 {
    if close_local_values_tasks(run, tasks) {
      closed = true
      break
    }
  }
  assert_true(closed)
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  captured_tasks_close_source(value)
}

///|
test "snapshot scalar overlap waits for original body and reference barrier on the same Task" {
  managed_scalar_snapshot_barrier(false)
}

///|
test "snapshot storage callback cancellation cannot enable completed-import overlap" {
  managed_scalar_snapshot_barrier(true)
}
