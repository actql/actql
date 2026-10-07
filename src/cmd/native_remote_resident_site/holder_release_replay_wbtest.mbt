///|
/// These command-routing tests use the real durable Site journal and release
/// transitions. HTTP delivery is a fault boundary, not public-Run acceptance.
fn holder_release_test_status(
  journal : @journal.Journal,
  request : @remote.DispatchRequest,
) -> String {
  let observation = journal.observation(request).unwrap()
  @remote.remote_dispatch_status_json(
    @journal.recovered_site_dispatch_record(observation),
    @journal.recovered_site_dispatch_evidence(observation),
    @journal.recovered_site_dispatch_subject(observation),
    @journal.recovered_site_dispatch_measurement(observation),
    source_observation=@journal.recovered_site_dispatch_source_observation(
      observation,
    ),
  ).unwrap()
}

///|
test "holder release replay reports the same durable cleanup without releasing twice" {
  let (_, journal, request, _, _) = cleanup_test_open("holder-release-replay")
  ignore(journal.accept(request).unwrap())
  ignore(journal.request_cancellation(request).unwrap())
  let identity = @remote.dispatch_request_identity(request)
  let task = new_holder_task_custody(request, None, None, None)
  let tasks : Map[String, HolderTaskCustody] = Map([(identity, task)])
  let order = [identity]
  let cleanup_calls = Ref(0)
  let reports : Array[String] = []
  let results : Array[Bool] = []
  let release = fn(selected) {
    results.push(
      reconcile_holder_task_release(
        selected,
        () => {
          cleanup_calls.val += 1
          confirm_unstarted_consumer_cleanup(journal, selected.request)
        },
        current => reports.push(holder_release_test_status(journal, current)),
      ),
    )
  }
  // The first actual journal observation is lost by the transport. No caller
  // may infer Cloud receipt from the holder's physical-cleanup flag.
  assert_true(handle_holder_release_frame(tasks, order, identity, release))
  assert_true(task.released)
  assert_eq(reports.length(), 1)
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_eq(
    @remote.dispatch_record_state_codes(journal.require(request).unwrap()),
    [5, 0, 2, 0, 0],
  )
  assert_true(handle_holder_release_frame(tasks, order, identity, release))
  assert_eq(reports, [reports[0], reports[0]])
  assert_eq(cleanup_calls.val, 1)
  assert_eq(results, [true, true])
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_eq(journal.start_claimant(request).unwrap(), None)
  assert_false(
    handle_holder_release_frame(tasks, order, "foreign-dispatch", release),
  )
  assert_eq(reports.length(), 2)
  assert_eq(cleanup_calls.val, 1)
  assert_true(journal.close())
}

///|
test "holder release pending save emits no cleanup observation and retries the same journal" {
  let (library, journal, request, path, _) = cleanup_test_open(
    "holder-release-pending",
  )
  ignore(journal.accept(request).unwrap())
  let cancelled = journal.request_cancellation(request).unwrap()
  let revision = @remote.dispatch_record_revision(cancelled)
  let identity = @remote.dispatch_request_identity(request)
  let task = new_holder_task_custody(request, None, None, None)
  let tasks : Map[String, HolderTaskCustody] = Map([(identity, task)])
  let order = [identity]
  let reports : Array[String] = []
  let results : Array[Bool] = []
  let release = fn(selected) {
    results.push(
      reconcile_holder_task_release(
        selected,
        () => confirm_unstarted_consumer_cleanup(journal, selected.request),
        current => reports.push(holder_release_test_status(journal, current)),
      ),
    )
  }
  let blocker = library.open_database(path, 262144L).unwrap()
  blocker.begin_immediate().unwrap()
  assert_true(handle_holder_release_frame(tasks, order, identity, release))
  assert_false(task.released)
  assert_eq(reports.length(), 0)
  assert_eq(results, [false])
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  blocker.rollback().unwrap()
  blocker.close_checked().unwrap()
  assert_true(handle_holder_release_frame(tasks, order, identity, release))
  assert_true(task.released)
  assert_eq(reports.length(), 1)
  assert_eq(results, [false, true])
  assert_true(journal.close())
}

///|
test "holder control loss cleans once without claiming observation delivery" {
  let (_, journal, request, _, _) = cleanup_test_open("holder-release-eof")
  ignore(journal.accept(request).unwrap())
  ignore(journal.request_cancellation(request).unwrap())
  let task = new_holder_task_custody(request, None, None, None)
  let cleanups = Ref(0)
  let reports = Ref(0)
  let cleanup = fn() {
    cleanups.val += 1
    confirm_unstarted_consumer_cleanup(journal, request)
  }
  let observe = fn(_) { reports.val += 1 }
  assert_true(
    reconcile_holder_task_release(task, cleanup, observe, control_ended=true),
  )
  assert_true(
    reconcile_holder_task_release(task, cleanup, observe, control_ended=true),
  )
  assert_eq(cleanups.val, 1)
  assert_eq(reports.val, 0)
  assert_true(task.released)
  assert_true(journal.close())
}
