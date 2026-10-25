///|
priv struct LocalStatusWatchProbe {
  operations : LocalStatusWatchOperations
  reads : Ref[Int]
  emitted : Array[String]
  current : Ref[Bool]
  interrupted : Ref[Bool]
  clock : Ref[Int64]
}

///|
// Callback loop probes are component evidence only, not a saved Host/Store.
fn local_status_watch_probe(wires : Array[String]) -> LocalStatusWatchProbe {
  let reads = Ref(0)
  let emitted = []
  let current = Ref(true)
  let interrupted = Ref(false)
  let clock = Ref(0L)
  {
    reads,
    emitted,
    current,
    interrupted,
    clock,
    operations: {
      read_original: () => {
        let index = reads.val
        reads.val += 1
        wires[if index < wires.length() { index } else { wires.length() - 1 }]
      },
      current: () => current.val,
      interrupted: () => interrupted.val,
      now_ms: () => clock.val,
      pause_ms: milliseconds => {
        clock.val += milliseconds.to_int64()
        true
      },
      progress: wire => {
        emitted.push(wire)
        true
      },
    },
  }
}

///|
fn local_status_watch_issue(
  options : LocalStatusWatchOptions,
  operations : LocalStatusWatchOperations,
) -> String {
  try {
    ignore(local_status_watch_loop(options, operations))
    "unexpected success"
  } catch {
    ClientStop(issue) => issue
  }
}

///|
let local_watch_test_options : LocalStatusWatchOptions = {
  watch: true,
  final_only: false,
  timeout_ms: 1000L,
}

///|
test "status durations preserve exact milliseconds and reject overflow or submillisecond loss" {
  for
    (text, expected) in [
      ("30", 30000L),
      ("1ms", 1L),
      ("1.25s", 1250L),
      ("0.001s", 1L),
      ("2m", 120000L),
      ("0.25h", 900000L),
      ("9223372036854775807ms", 9223372036854775807L),
    ] {
    assert_eq(local_status_duration(text), expected)
  }
  for
    text in [
      "0", "-1s", "+1s", "1e3s", "1 ms", "1.", ".1s", "0.1ms", "0.0001s", "9223372036854775808ms",
      "9223372036854776s",
    ] {
    assert_eq(
      try {
        ignore(local_status_duration(text))
        "unexpected success"
      } catch {
        ClientStop(issue) => issue
      },
      "InvalidLocalStatusTimeout",
    )
  }
}

///|
test "status watch validates the original selector and options before project IO" {
  let parsed = command().parse(
    argv=[
      "--mode", "local", "status", "original-run", "--watch", "--timeout", "1.25s",
    ],
    env=Map([]),
  )
  normalize_native_status_arguments(parsed)
  let child = parsed.subcommand.unwrap().1
  let selected = local_status_watch_options(child).unwrap()
  assert_true(selected.watch)
  assert_eq(selected.timeout_ms, 1250L)
  assert_eq(optional(child, "run-id"), Some("original-run"))
  let plain = command().parse(argv=["status", "original-run"], env=Map([]))
  assert_true(local_status_watch_options(plain.subcommand.unwrap().1) is None)
  for
    (options, expected) in [
      (["--until", "final"], "LocalStatusUntilRequiresWatch"),
      (["--watch", "--until", "invented"], "InvalidLocalStatusUntil"),
      (["--watch", "--timeout", "0"], "InvalidLocalStatusTimeout"),
    ] {
    let argv = [
      "--mode", "local", "--config", "must-not-open.json", "status", "original-run",
      ..options,
    ]
    let selected = command().parse(argv=argv[:], env=Map([]))
    assert_eq(
      try {
        ignore(execute_native_project_selection(selected))
        "unexpected success"
      } catch {
        ClientStop(issue) => issue
      },
      expected,
    )
  }
}

///|
test "watch emits only original revision changes then returns the stable original" {
  let running = run_display_minimal
  let timestamp_only = running.replace(old="00:00:00.000Z", new="00:00:01.000Z")
  let succeeded = running
    .replace(old="\"running\"", new="\"succeeded\"")
    .replace(old="\"revision\":7", new="\"revision\":8")
  let probe = local_status_watch_probe([running, timestamp_only, succeeded])
  assert_eq(
    local_status_watch_loop(local_watch_test_options, probe.operations),
    succeeded,
  )
  assert_eq(probe.reads.val, 3)
  assert_eq(probe.emitted, [running])
}

///|
test "watch retains timeout interruption original Unknown and failed output" {
  let probe = local_status_watch_probe([run_display_minimal])
  assert_eq(
    local_status_watch_issue(
      { ..local_watch_test_options, timeout_ms: 1L, },
      probe.operations,
    ),
    "WaitTimeout",
  )
  assert_eq(probe.reads.val, 1)
  let stopped = local_status_watch_probe([run_display_minimal])
  stopped.interrupted.val = true
  assert_eq(
    local_status_watch_issue(local_watch_test_options, stopped.operations),
    "WaitAborted",
  )
  assert_eq(stopped.reads.val, 0)
  let failed = local_status_watch_probe([run_display_minimal])
  assert_eq(
    local_status_watch_issue(local_watch_test_options, {
      ..failed.operations,
      read_original: () => stop("LocalRunStateLookupUnknown"),
    }),
    "LocalRunStateLookupUnknown",
  )
  assert_eq(failed.emitted, [])
  assert_eq(
    local_status_watch_issue(local_watch_test_options, {
      ..failed.operations,
      progress: _ => false,
    }),
    "LocalStatusProgressWriteFailed",
  )
}

///|
test "watch refuses post-read current loss missing revision foreign Run and regression" {
  let probe = local_status_watch_probe([run_display_minimal])
  let changed = {
    ..probe.operations,
    read_original: () => {
      probe.current.val = false
      run_display_minimal
    },
  }
  assert_eq(
    local_status_watch_issue(local_watch_test_options, changed),
    "LocalRunStateReadAuthorizationDenied",
  )
  assert_eq(probe.emitted, [])
  let missing = local_status_watch_probe([
    run_display_minimal.replace(old="\"revision\":7,", new=""),
  ])
  assert_eq(
    local_status_watch_issue(local_watch_test_options, missing.operations),
    "LocalOriginalRunStateUnavailable",
  )
  let foreign = local_status_watch_probe([
    run_display_minimal,
    run_display_minimal.replace(old="original-run", new="another-run"),
  ])
  assert_eq(
    local_status_watch_issue(local_watch_test_options, foreign.operations),
    "LocalOriginalRunReferenceMismatch",
  )
  let backwards = local_status_watch_probe([
    run_display_minimal,
    run_display_minimal.replace(old="\"revision\":7", new="\"revision\":6"),
  ])
  assert_eq(
    local_status_watch_issue(local_watch_test_options, backwards.operations),
    "LocalRunStateRevisionRegressed",
  )
}

///|
test "watch uses the actual monotonic clock and restores its original signal handlers" {
  assert_true(local_status_watch_begin_ffi())
  let before = local_status_watch_now_ffi()
  assert_true(before >= 0L)
  assert_true(local_status_watch_pause_ffi(1))
  assert_true(local_status_watch_now_ffi() >= before)
  assert_false(local_status_watch_interrupted_ffi())
  assert_true(local_status_watch_end_ffi())
  assert_true(local_status_watch_begin_ffi())
  assert_true(local_status_watch_end_ffi())
}

///|
test "watch refuses unavailable backwards clock and post-progress current loss" {
  let missing = local_status_watch_probe([run_display_minimal])
  missing.clock.val = -1L
  assert_eq(
    local_status_watch_issue(local_watch_test_options, missing.operations),
    "LocalStatusClockUnavailable",
  )
  assert_eq(missing.reads.val, 0)
  let probe = local_status_watch_probe([run_display_minimal])
  let calls = Ref(0)
  let backwards = {
    ..probe.operations,
    now_ms: () => {
      calls.val += 1
      if calls.val < 3 {
        1L
      } else {
        0L
      }
    },
  }
  assert_eq(
    local_status_watch_issue(local_watch_test_options, backwards),
    "LocalStatusClockUnavailable",
  )
  let invalidated = local_status_watch_probe([run_display_minimal])
  let operations = {
    ..invalidated.operations,
    progress: _ => {
      invalidated.current.val = false
      true
    },
  }
  assert_eq(
    local_status_watch_issue(local_watch_test_options, operations),
    "LocalRunStateReadAuthorizationDenied",
  )
  assert_eq(invalidated.reads.val, 1)
}

///|
test "final watch passes original Checkpoint and reconciliation without changing their meaning" {
  let checkpoint =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"waiting_checkpoint","revision":5,"updated_at":"2026-10-17T00:00:00.000Z","checkpoint":{"checkpoint_id":"original-checkpoint","checkpoint_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"effect_set"},"next_action":{"kind":"resolve_checkpoint","checkpoint_id":"original-checkpoint"},"result_available":false,"result_availability":{}}
  let reconciliation =
    #|{"version":"actql-run-state/0.1","run_id":"original-run","status":"needs_reconciliation","revision":6,"updated_at":"2026-10-17T00:00:00.000Z","next_action":{"kind":"reconcile_run","reason":"execution_unknown"},"result_available":false,"result_availability":{}}
  let succeeded = run_display_minimal.replace(
    old="\"running\"",
    new="\"succeeded\"",
  )
  let final_status = local_status_watch_probe([
    checkpoint, reconciliation, succeeded,
  ])
  assert_eq(
    local_status_watch_loop(
      { ..local_watch_test_options, final_only: true, },
      final_status.operations,
    ),
    succeeded,
  )
  assert_eq(final_status.reads.val, 3)
  assert_eq(final_status.emitted, [checkpoint, reconciliation])
  let stable = local_status_watch_probe([checkpoint])
  assert_eq(
    local_status_watch_loop(local_watch_test_options, stable.operations),
    checkpoint,
  )
  assert_eq(stable.reads.val, 1)
  assert_eq(stable.emitted, [])
}
