///|
fn retained_output_test_root() -> String {
  @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap_or_else(() => {
    abort("retained output Native tests require a private physical root")
  })
}

///|
fn retained_output_test_limits() -> NativeRemoteStandardTaskLimits {
  {
    output_export: {
      max_result_fields: 10,
      max_result_mapping_work: 100,
      max_result_order_work: 100,
      max_result_workspace_entries: 100,
      max_rows: 100,
      values: retained_source_limits().values,
      payload_wire: {
        max_columns: 10,
        max_order_work: 100,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      logical_wire: {
        max_columns: 10,
        max_order_work: 100,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      schema: {
        max_fields: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      max_batch_bytes: 64,
    },
    max_manifest_bytes: 10000,
    max_retained_bytes: 1000L,
  }
}

///|

///|
fn retained_output_acquired_fixture() -> (
  @publication_host.PublicationOutputExport,
  @remote.DispatchRequest,
  () -> Bool,
  Ref[Int],
  Ref[Int],
) {
  let original = retained_transfer_run()
  let (input, dispatch, sequence, program, current, codec) = retained_source_setup(
    run=Some(original),
  )
  let captures = Ref(0)
  let closes = Ref(0)
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => closes.val == 0,
    (max_bytes, emit) => {
      captures.val += 1
      let row = b"{\"id\":3}"
      let mut offset = 0
      while offset < row.length() {
        let count = Int::min(max_bytes, row.length() - offset)
        match
          emit(
            0,
            Bytes::from_array(Array::makei(count, index => row[offset + index])),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        offset += count
      }
      Ok(())
    },
    () => {
      closes.val += 1
      true
    },
  )
  let acquired = acquire_native_remote_retained_physical_source(
    input,
    physical,
    dispatch,
    codec,
    sequence,
    program,
    retained_source_limits(),
    current,
  ).unwrap()
  let source = native_remote_standard_transfer_captured_source(acquired)
  let run = @publication_host.open_prepared_captured_client_run(
    original.0,
    source,
    {
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 1000000L,
      retained_bytes: 1000000L,
      execution_bytes: 1000000L,
    },
  ).unwrap()
  let limits = retained_output_test_limits()
  let output_export = @publication_host.prepare_acquired_task_publication_export(
    run,
    0,
    source,
    limits.output_export,
  ).unwrap()
  (
    output_export,
    dispatch,
    () => {
      @strategy.stop_captured_dag(run)
      finish_native_remote_standard_transfer_source(acquired)
    },
    captures,
    closes,
  )
}

///|
test "native retained file handoff preserves output while original cleanup waits" {
  let (output_export, _, release_run, captures, closes) = retained_output_acquired_fixture()
  let file = @retained_file.begin_native_retained_task_file(
    retained_output_test_root(),
    "handoff-pending-" + @env.now().to_string(),
    1000L,
  ).unwrap()
  while output_export.next().unwrap() is Some(text) {
    file.append(text).unwrap()
  }
  file.append(output_export.finish().unwrap()).unwrap()
  file.seal("sha256:" + @sha.hex(b"[{\"id\":3}]"), 10).unwrap()
  let attempts = Ref(0)
  let retirements = Ref(0)
  let allow_cleanup = Ref(false)
  let allow_retirement = Ref(false)
  let owner : NativeRemoteStandardOutputOwner = {
    output_export: Some(output_export),
    release_run: retain_standard_output_cleanup(Some(file), () => true),
    handoff_cleanup: Some(() => {
      attempts.val += 1
      allow_cleanup.val && release_run()
    }),
    retired_input_cleanup: Some(() => {
      retirements.val += 1
      closes.val == 1 && allow_retirement.val
    }),
    handoff_committed: false,
    retained_file: Some(file),
    chunk_byte_lengths: [10L],
    export_cancelled: false,
    released: false,
  }
  assert_true(
    owner.open_manifest_reader() is Err("output-input-cleanup-pending"),
  )
  assert_eq(attempts.val, 0)
  assert_eq(closes.val, 0)
  assert_eq(retirements.val, 0)
  owner.confirm_file_handoff()
  assert_eq(attempts.val, 1)
  assert_eq(closes.val, 0)
  assert_true(owner.output_export is None)
  assert_true(owner.handoff_cleanup is Some(_))
  assert_true(
    owner.open_manifest_reader() is Err("output-input-cleanup-pending"),
  )
  assert_eq(attempts.val, 2)
  assert_true(owner.open_reader() is Ok(_))
  let reader = file.open_reader().unwrap()
  assert_eq(reader.next(100).unwrap().bytes, b"[{\"id\":3}]")
  assert_true(reader.next(100).unwrap().eof)
  reader.finish().unwrap()
  allow_cleanup.val = true
  assert_true(
    owner.open_manifest_reader() is Err("output-input-cleanup-pending"),
  )
  assert_eq(attempts.val, 3)
  assert_eq(closes.val, 1)
  assert_eq(retirements.val, 1)
  assert_eq(captures.val, 1)
  assert_true(owner.handoff_cleanup is None)
  assert_true(owner.retired_input_cleanup is Some(_))
  assert_false(owner.release())
  assert_false(owner.released)
  assert_true(owner.retired_input_cleanup is Some(_))
  assert_eq(retirements.val, 2)
  allow_retirement.val = true
  assert_true(owner.release())
  assert_true(owner.release())
  assert_eq(retirements.val, 3)
  assert_true(owner.retired_input_cleanup is None)
  assert_eq(attempts.val, 3)
  assert_true(file.release_confirmed())
}

///|
test "native retained file abandonment does not retire an uncommitted input" {
  let (output_export, _, release_run, captures, closes) = retained_output_acquired_fixture()
  let file = @retained_file.begin_native_retained_task_file(
    retained_output_test_root(),
    "handoff-uncommitted-" + @env.now().to_string(),
    1000L,
  ).unwrap()
  while output_export.next().unwrap() is Some(text) {
    file.append(text).unwrap()
  }
  file.append(output_export.finish().unwrap()).unwrap()
  file.seal("sha256:" + @sha.hex(b"[{\"id\":3}]"), 10).unwrap()
  let retirements = Ref(0)
  let owner : NativeRemoteStandardOutputOwner = {
    output_export: Some(output_export),
    release_run: retain_standard_output_cleanup(Some(file), () => true),
    handoff_cleanup: Some(release_run),
    retired_input_cleanup: Some(() => {
      retirements.val += 1
      false
    }),
    handoff_committed: false,
    retained_file: Some(file),
    chunk_byte_lengths: [10L],
    export_cancelled: false,
    released: false,
  }
  assert_true(owner.release())
  assert_true(owner.release())
  assert_eq(retirements.val, 0)
  assert_eq(captures.val, 1)
  assert_eq(closes.val, 1)
  assert_true(file.release_confirmed())
}

///|
test "native retained output seals the exact acquired task stream without another capture" {
  let (output_export, dispatch, release_run, captures, closes) = retained_output_acquired_fixture()
  let limits = retained_output_test_limits()
  let occurrence = "acquired-output-" + @env.now().to_string()
  let root = retained_output_test_root()
  let file = @retained_file.begin_native_retained_task_file(
    root, occurrence, 1000L,
  ).unwrap()
  assert_true(
    prepare_native_remote_standard_output_from_export(
      dispatch,
      0,
      output_export,
      release_run,
      limits,
      @remote.prepare_remote_dispatch_budget(1000L, 1000L).unwrap(),
      retained_file=Some(file),
    )
    is @runtime.NativeRemoteOutputReady(_),
  )
  let cid = "sha256:" + @sha.hex(b"[{\"id\":3}]")
  assert_eq(file.sealed_content(), Some((cid, 10L)))
  let generation = file.sealed_generation().unwrap()
  // Discard the replay/capture; restoration reads only the original file.
  output_export.cancel()
  assert_true(release_run())
  let restored = @retained_file.restore_native_retained_task_file(
    root, occurrence, generation, cid, 1000L,
  ).unwrap()
  let reader : NativeRemoteStandardRetainedManifestReader = {
    reader: restored.open_reader().unwrap(),
    lengths: [10L],
    next_index: 0,
    closed: false,
  }
  assert_eq(reader.next(0).unwrap(), b"[{\"id\":3}]")
  reader.finish().unwrap()
  reader.close().unwrap()
  assert_eq(captures.val, 1)
  assert_eq(closes.val, 1)
  restored.release().unwrap()
  assert_true(restored.release_confirmed())
}

///|
test "native retained output verifies exact manifest extent order and content before finish" {
  let occurrence = "retained-output-manifest-" + @env.now().to_string()
  let file = @retained_file.begin_native_retained_task_file(
    retained_output_test_root(),
    occurrence,
    7L,
  ).unwrap()
  file.append("[1,2,3]").unwrap()
  file.seal("sha256:" + @sha.hex(b"[1,2,3]"), 7).unwrap()
  let reader : NativeRemoteStandardRetainedManifestReader = {
    reader: file.open_reader().unwrap(),
    lengths: [3L, 2L, 2L],
    next_index: 0,
    closed: false,
  }
  assert_true(reader.next(1) is Err("invalid-manifest-reader-state"))
  assert_true(reader.finish() is Err("output-manifest-reader-incomplete"))
  assert_eq(reader.next(0).unwrap(), b"[1,")
  assert_true(reader.next(0) is Err("invalid-manifest-reader-state"))
  assert_eq(reader.next(1).unwrap(), b"2,")
  assert_eq(reader.next(2).unwrap(), b"3]")
  reader.finish().unwrap()
  reader.finish().unwrap()
  let short : NativeRemoteStandardRetainedManifestReader = {
    reader: file.open_reader().unwrap(),
    lengths: [6L],
    next_index: 0,
    closed: false,
  }
  ignore(short.next(0).unwrap())
  assert_true(short.finish() is Err("output-retained-extent"))
  short.close().unwrap()
  let wrong = @retained_file.restore_native_retained_task_file(
    retained_output_test_root(),
    occurrence,
    file.sealed_generation().unwrap(),
    "sha256:" + @sha.hex(b"different"),
    7L,
  ).unwrap()
  let mismatched : NativeRemoteStandardRetainedManifestReader = {
    reader: wrong.open_reader().unwrap(),
    lengths: [7L],
    next_index: 0,
    closed: false,
  }
  assert_eq(mismatched.next(0).unwrap(), b"[1,2,3]")
  assert_true(mismatched.finish() is Err("output-retained-finish"))
  assert_false(wrong.available())
  mismatched.close().unwrap()
  file.release().unwrap()
}

///|
test "native retained output cleanup retains the Run owner until exact physical cleanup succeeds" {
  let root_path = retained_output_test_root()
  let occurrence = "retained-output-cleanup-" + @env.now().to_string()
  let file = @retained_file.begin_native_retained_task_file(
    root_path, occurrence, 3L,
  ).unwrap()
  file.append("abc").unwrap()
  file.seal("sha256:" + @sha.hex(b"abc"), 3).unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let run_released = Ref(false)
  let calls = Ref(0)
  let cleanup = retain_standard_output_cleanup(Some(file), () => {
    if !run_released.val {
      calls.val += 1
      run_released.val = true
    }
    true
  })
  let generation = file.sealed_generation().unwrap()
  let pinned = root.open_reader("output-" + occurrence, generation).unwrap()
  root.reclaim_generation("output-" + occurrence, generation).unwrap()
  let replacement = root.create_writer("replacement-" + occurrence, 3L).unwrap()
  replacement.append(b"xyz").unwrap()
  let replacement_generation = replacement.seal("output-" + occurrence).unwrap()
  assert_false(cleanup())
  assert_false(file.release_confirmed())
  assert_eq(calls.val, 0)
  assert_true(
    root.verify_generation("output-" + occurrence, replacement_generation),
  )
  pinned.close().unwrap()
  replacement.cancel().unwrap()
  assert_true(cleanup())
  assert_true(file.release_confirmed())
  assert_eq(calls.val, 1)
  assert_true(cleanup())
  assert_eq(calls.val, 1)
}

///|
test "native retained output append failure cleans the original capture without a replacement" {
  let (output_export, dispatch, release_run, captures, closes) = retained_output_acquired_fixture()
  let occurrence = "retained-output-append-failure-" + @env.now().to_string()
  let root_path = retained_output_test_root()
  let file = @retained_file.begin_native_retained_task_file(
    root_path, occurrence, 1L,
  ).unwrap()
  assert_true(
    prepare_native_remote_standard_output_from_export(
      dispatch,
      0,
      output_export,
      release_run,
      retained_output_test_limits(),
      @remote.prepare_remote_dispatch_budget(1000L, 1000L).unwrap(),
      retained_file=Some(file),
    )
    is @runtime.NativeRemoteExecutionFailed(_),
  )
  assert_eq(captures.val, 1)
  assert_eq(closes.val, 1)
  assert_true(file.release_confirmed())
  let root = @filesystem.open_root(root_path).unwrap()
  assert_true(root.inspect_generation("stage-" + occurrence) is Ok(None))
  assert_true(root.inspect_generation("output-" + occurrence) is Ok(None))
}
