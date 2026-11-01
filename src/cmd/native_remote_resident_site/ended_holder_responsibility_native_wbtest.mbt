///|
fn finish_ended_holder_physical_fixture(holder : RunningHolder) -> Unit raise {
  if holder.spawn_custody.cleanup() {
    return
  }
  assert_true(holder.channel.close())
  let stop = holder.spawn_custody.poll_stop().unwrap().unwrap()
  stop.require_current(holder.spawn_custody).unwrap()
  assert_true(stop.close())
  assert_true(holder.spawn_custody.cleanup())
}

///|
fn ended_holder_physical_fixture(
  label : String,
  script : String,
) -> (RunningHolder, @slot.NativeExecutorSlot, String) raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT") is Some(root) else {
    fail("selected ended-holder cases require an owned isolated slot Root")
  }
  let name = label + "-" + @env.now().to_string()
  let path = root + "/" + name + ".lock"
  let slot = @slot.open_native_executor_slot(path).unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = match slot.prepare_scoped_holder() {
    Ready(original) => original
    Refused(original, _) => {
      assert_true(original.cleanup())
      fail("owned fixture original preparation refused")
      original
    }
  }
  original
  .spawn_with_channel("/bin/sh", [
    "-c",
    script,
    "owned-fixture",
    root + "/" + name + ".done",
  ])
  .unwrap()
  let child = original.child().unwrap()
  let channel = original.channel().unwrap()
  assert_true(child.wait(true).unwrap() is Some(_))
  let request = holder_custody_test_request("original-task", label)
  let holder : RunningHolder = {
    spawn_custody: original,
    child,
    channel,
    request,
    attempt: @remote.dispatch_request_attempt_identity(request).unwrap(),
    next_report_ms: 0UL,
    reported_revision: None,
  }
  (holder, @slot.open_native_executor_slot(path).unwrap(), name + ".done")
}

///|
test "adversarial report ACK cannot discard an unclosed original Channel" {
  let (holder, probe, _) = ended_holder_physical_fixture(
    "ended-open-channel", "exit 0",
  )
  let original : EndedHolderResponsibility = {
    original: holder,
    channel: ChannelCloseUnconfirmed,
    // Deliberate negative input; no transport/Cloud ACK is claimed by this test.
    report_evidence: OriginalStatusAcknowledged,
    startability: Some(false),
    journal: Ref(None),
    process_retirement: HolderStopPending,
  }
  assert_false(ended_holder_can_leave_window(original, probe))
  assert_true(physical_equal(original.original.channel, holder.channel))
  assert_true(holder.channel.close())
  assert_true(probe.close())
  finish_ended_holder_physical_fixture(holder)
}

///|
test "child exit and adversarial report ACK do not prove inherited descendant stop" {
  let (holder, probe, gate) = ended_holder_physical_fixture(
    "ended-live-descendant", "(while [ ! -e \"$1\" ]; do sleep 0.01; done) >/dev/null 2>&1 & exit 0",
  )
  // Retire the same real Channel before testing the independent slot fence.
  assert_true(holder.channel.close())
  let original : EndedHolderResponsibility = {
    original: holder,
    channel: ChannelDescriptorsRetired,
    report_evidence: OriginalStatusAcknowledged, // Negative input only.
    startability: Some(false),
    journal: Ref(None),
    process_retirement: HolderStopPending,
  }
  assert_true(probe.try_acquire() == Ok(false))
  assert_false(ended_holder_can_leave_window(original, probe))
  // This test makes no cleanup ACK from waiting/termination or this status.
  assert_true(holder.child.wait(false).unwrap() is Some(_))
  // Release the owned descendant's explicit fixture gate only after the
  // rejection. No elapsed-time assumption is used to keep it alive.
  let root = @filesystem.open_root_with_custody(
    @env.get_env_var("ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT").unwrap(),
  ).unwrap()
  let writer = root.create_writer(gate + ".staging", 0L).unwrap()
  writer.seal(gate).unwrap() |> ignore
  root.close().unwrap()
  let mut stopped = false
  // Same finite five-second barrier used by the existing slot cases. Waiting
  // alone is not evidence: only the real exclusive slot observation is used.
  for _ in 0..<100 {
    if retire_ended_holder_process(original) {
      stopped = true
      break
    }
    @slot.native_wait_milliseconds(50)
  }
  assert_true(stopped)
  assert_true(probe.try_acquire() == Ok(true))
  assert_true(probe.verify_current_hold() is Ok(_))
  assert_true(ended_holder_can_leave_window(original, probe))
  assert_true(probe.close())
  finish_ended_holder_physical_fixture(holder)
}

///|
test "unreadable original execution record never becomes startable from status ACK alone" {
  let (holder, probe, _) = ended_holder_physical_fixture(
    "ended-missing-record", "exit 0",
  )
  // Close confirmation and a current acquired slot must not replace the
  // missing original execution-record observation.
  assert_true(holder.channel.close())
  let original : EndedHolderResponsibility = {
    original: holder,
    channel: ChannelDescriptorsRetired,
    report_evidence: OriginalStatusAcknowledged, // Negative input only.
    startability: None,
    journal: Ref(None),
    process_retirement: HolderStopPending,
  }
  assert_true(probe.try_acquire() == Ok(true))
  assert_true(probe.verify_current_hold() is Ok(_))
  assert_true(original.startability is None)
  assert_false(ended_holder_can_leave_window(original, probe))
  assert_true(original.startability is None)
  assert_true(probe.close())
  finish_ended_holder_physical_fixture(holder)
}

///|
test "ended holder observation reuses its original Journal before any replacement" {
  let (physical, probe, _) = ended_holder_physical_fixture(
    "ended-original-journal", "exit 0",
  )
  let (library, journal, request, path, _) = cleanup_test_open(
    "ended-original-journal",
  )
  // Use the request issued for this real Journal's Site, not the unrelated
  // channel fixture's default request. No transport or status ACK is supplied.
  let holder : RunningHolder = {
    ..physical,
    request,
    attempt: @remote.dispatch_request_attempt_identity(request).unwrap(),
  }
  let original = retain_ended_holder(holder)
  journal.accept(request).unwrap() |> ignore
  original.journal.val = Some(ReplayJournalHandle(journal))
  let foreign = replay_journal_test_environment(library, path + ".replacement")
  let observed = open_ended_holder_observation_journal(original, foreign).unwrap()
  assert_true(physical_equal(observed, journal))
  assert_eq(
    @remote.dispatch_record_revision(observed.require(holder.request).unwrap()),
    0,
  )
  assert_true(original.report_evidence is OriginalStatusPending)
  assert_true(original.startability is None)
  assert_false(ended_holder_can_leave_window(original, probe))
  assert_true(retry_control_replay_journal_cleanup(original.journal))
  assert_true(original.journal.val is None)
  // Deliberate report input is a refusal counterexample, not a transport ACK.
  original.report_evidence = OriginalStatusAcknowledged
  assert_true(open_ended_holder_observation_journal(original, foreign) is None)
  assert_true(original.journal.val is None)
  assert_false(ended_holder_can_leave_window(original, probe))
  assert_true(probe.close())
  finish_ended_holder_physical_fixture(holder)
}

///|
test "ended holder failed Journal open retains original cleanup before status observation" {
  let (holder, probe, _) = ended_holder_physical_fixture(
    "ended-failed-journal", "exit 0",
  )
  let original = retain_ended_holder(holder)
  let (library, initial, _, path, _) = cleanup_test_open("ended-failed-journal")
  initial.close_checked().unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  assert_true(
    open_ended_holder_observation_journal(
      original,
      replay_journal_test_environment(library, root),
    )
    is None,
  )
  let failure = match original.journal.val {
    Some(ReplayJournalOpenFailure(value)) => value
    _ => {
      fail("ended holder lost its original physical open failure")
      return
    }
  }
  assert_true(failure.issue() is @journal.Physical(@sqlite.DatabaseOpen(_)))
  assert_true(
    open_ended_holder_observation_journal(
      original,
      replay_journal_test_environment(library, path),
    )
    is None,
  )
  assert_true(
    original.journal.val is Some(ReplayJournalOpenFailure(value)) &&
    physical_equal(value, failure),
  )
  assert_true(original.report_evidence is OriginalStatusPending)
  assert_true(original.startability is None)
  assert_false(ended_holder_can_leave_window(original, probe))
  assert_true(retry_control_replay_journal_cleanup(original.journal))
  assert_true(original.journal.val is None)
  assert_true(failure.issue() is @journal.Physical(@sqlite.DatabaseOpen(_)))
  assert_true(probe.close())
  finish_ended_holder_physical_fixture(holder)
}
