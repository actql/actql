///|
test "installed retained mode snapshots required Relations on the same Task without changing default selection" {
  for retained_relation in [false, true] {
    let value = captured_tasks_fixture()
    let (run, dispatch) = metered_tail_dispatch(value)
    let operations = @local_driver.start_local_managed_dispatch_node(
      dispatch,
      retained_relation~,
    ).unwrap()
    let tasks : Array[LocalValuesTaskExecution?] = Array::make(3, None)
    tasks[1] = Some({ operations, settled: false, completed: None, })
    (operations.execute)().unwrap()
    let original_work = (operations.cumulative_provider_work)().unwrap()
    assert_eq((operations.output_row)(0).unwrap(), "{\"id\":3}")
    assert_eq((operations.output_row)(1).unwrap(), "{\"id\":2}")
    let released = Ref(false)
    let snapshot = (operations.prepare_relation_snapshot)(() => released.val).unwrap()
    if retained_relation {
      let snapshot = snapshot.unwrap()
      let wire = StringBuilder()
      let mut complete = false
      for _ in 0..<10000 {
        let next = (snapshot.advance_save)(7).unwrap()
        assert_true(next.work >= 0L && next.work <= 7L)
        wire.write_string((snapshot.take_output)().unwrap())
        if next.complete {
          complete = true
          break
        }
      }
      assert_true(complete)
      assert_eq(wire.to_string(), "[{\"id\":3},{\"id\":2}]")
      let content = (snapshot.content)().unwrap()
      assert_eq(content.bytes, 19)
      assert_true(
        (operations.cumulative_provider_work)().unwrap() > original_work,
      )
      (snapshot.release_source)(content.cid, () => !released.val).unwrap()
      assert_false((snapshot.source_available)())
      assert_true((operations.output_row)(0) is Err(_))
      (snapshot.begin_reload)().unwrap()
      (snapshot.append_reload)("{\"id\":3}").unwrap()
      (snapshot.append_reload)("{\"id\":2}").unwrap()
      (snapshot.finish_reload)().unwrap()
      released.val = true
      let mut references_closed = false
      for _ in 0..<10000 {
        if (snapshot.cleanup_references)(7) {
          references_closed = true
          break
        }
      }
      assert_true(references_closed)
      (snapshot.finish)().unwrap()
      assert_true((snapshot.source_available)())
      assert_eq((operations.output_row)(0).unwrap(), "{\"id\":3}")
      assert_eq((operations.output_row)(1).unwrap(), "{\"id\":2}")
    } else {
      assert_true(snapshot is None)
      assert_eq((operations.cumulative_provider_work)().unwrap(), original_work)
    }
    let mut closed = false
    for _ in 0..<10000 {
      if close_local_values_tasks(run, tasks) {
        closed = true
        break
      }
    }
    assert_true(closed)
    assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
    captured_tasks_close_source(value)
  }
}
