///|
test "metadata policy preserves zero wire legacy and rejects negative independent units" {
  let limits : @local.LocalImportLimits = {
    max_rows: 100,
    values: { max_nodes: 0, max_text_bytes: 0, max_depth: 1, max_work: 1, },
    wire: {
      max_columns: 1,
      max_order_work: 1,
      max_bytes: 0,
      max_nodes: 0,
      max_depth: 1,
    },
    row: { max_bytes: 0, max_nodes: 0, max_depth: 1, max_text_bytes: 0, },
    max_batch_bytes: 0,
  }
  let legacy = local_managed_metadata_limits(limits, None).unwrap()
  assert_eq(legacy.name_bytes, 0)
  assert_eq(legacy.schema.max_nodes, 0)
  assert_eq(legacy.bridge_entries, 0)
  assert_eq(legacy.completion_entries, 0)
  assert_eq(legacy.result_workspace_entries, 100)
  assert_eq(legacy.retained_bytes, 0L)
  for
    bad in [
      { ..legacy, schema: { ..legacy.schema, max_nodes: -1, }, },
      { ..legacy, schema: { ..legacy.schema, max_fields: -1, }, },
      { ..legacy, schema: { ..legacy.schema, max_bytes: -1, }, },
      { ..legacy, schema: { ..legacy.schema, max_depth: -1, }, },
      { ..legacy, name_bytes: -1, },
      { ..legacy, bridge_entries: -1, },
      { ..legacy, completion_entries: -1, },
      { ..legacy, result_workspace_entries: -1, },
      { ..legacy, retained_bytes: -1L, },
      { ..legacy, result_rows_reserved: Some(-1), },
      { ..legacy, result_rows_reserved: Some(101), },
    ] {
    assert_true(local_managed_metadata_limits(limits, Some(bad)) is None)
  }
  let independent = {
    ..legacy,
    schema: { ..legacy.schema, max_nodes: 100000, },
    bridge_entries: 100000,
    completion_entries: 100000,
    result_workspace_entries: 201,
    retained_bytes: 4096L,
  }
  assert_eq(
    local_managed_metadata_limits(limits, Some(independent)).unwrap().retained_bytes,
    4096L,
  )
  assert_eq(limits.wire.max_nodes, 0)
}

///|
test "metadata retained conversion rejects negative and overflow before reservation" {
  assert_eq(local_retained_with_metadata(0L, 0L), Some(0L))
  assert_eq(local_retained_with_metadata(123L, 456L), Some(579L))
  assert_eq(
    local_retained_with_metadata(9223372036854775806L, 1L),
    Some(9223372036854775807L),
  )
  assert_eq(local_retained_with_metadata(9223372036854775806L, 2L), None)
  assert_eq(local_retained_with_metadata(-1L, 0L), None)
  assert_eq(local_retained_with_metadata(0L, -1L), None)
}

///|
test "missing input copy quote preserves original scratch metadata export and exact copy boundaries" {
  let base = @execution.execution_capacity(3L, 5L).unwrap()
  for
    (copies, retained, execution, transfer) in [
      (0, 23L, 28L, 0L),
      (1, 34L, 39L, 37L),
      (2, 45L, 50L, 74L),
    ] {
    let actual = local_dispatch_copy_capacity(
      base, 7L, 11L, 13L, 37L, copies, true,
    ).unwrap()
    // The materializing route constructs its original transport, not the
    // managed-only logical-work diagnostic frame.
    assert_eq(actual.retained_bytes, retained)
    assert_eq(actual.execution_bytes, execution)
    assert_eq(actual.transfer_bytes, transfer)
  }
  assert_true(
    local_dispatch_copy_capacity(base, 7L, 11L, 13L, 37L, -1, true) is None,
  )
  assert_true(
    local_dispatch_copy_capacity(
      base, 9223372036854775807L, 11L, 13L, 37L, 0, true,
    )
    is None,
  )
}

///|
test "managed task projection adds only its complete diagnostic frame" {
  let plain : @strategy.PhysicalEnvelope = {
    transfer_bytes: 37L,
    retained_bytes: 101L,
    execution_bytes: 211L,
  }
  // Independently authored representation counts, not the helper's output.
  let retained = 3L * 16L + 5L * 8L + 6L * 8L + 19L * 2L
  let temporary = 3L * 16L + 6L * 8L + 5L * 8L
  let managed = local_managed_task_capacity(plain).unwrap()
  assert_eq(managed.transfer_bytes, plain.transfer_bytes)
  assert_eq(managed.retained_bytes, plain.retained_bytes + retained)
  assert_eq(
    managed.execution_bytes,
    plain.execution_bytes + retained + temporary,
  )
  assert_eq(plain.retained_bytes, 101L)
  assert_eq(plain.execution_bytes, 211L)
}

///|
test "logical work diagnostic quote retains fixed fields and preserves explicit metadata ceilings" {
  let (retained, execution) = local_managed_logical_work_diagnostic_capacity().unwrap()
  assert_eq(retained, 3L * 16L + 5L * 8L + 6L * 8L + 19L * 2L)
  assert_eq(execution - retained, 3L * 16L + 6L * 8L + 5L * 8L)
  let origin = local_dispatch_preparation_work_policy_capacity()
  assert_eq(origin.retained_bytes, 2L * 8L)
  assert_eq(origin.execution_bytes, 4L * 8L)
  assert_true(
    local_managed_task_capacity({
      transfer_bytes: 0L,
      retained_bytes: 9223372036854775807L - retained + 1L,
      execution_bytes: 9223372036854775807L,
    })
    is None,
  )
  assert_true(
    local_managed_task_capacity({
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 9223372036854775807L - execution + 1L,
    })
    is None,
  )
}

///|
test "logical work complete frame admits exact backing and refuses either one-byte-short before construction" {
  // Independent allocation sites, including the enum and Some tags. These
  // are complete new frames; no old error or metadata spare is credited.
  let issue = 16L + 4L * 8L
  let data = 16L + 5L * 8L + 2L * 8L
  let decimal = 16L + 19L * 2L
  let retained = issue + data + decimal
  let tuple_some = 2L * 16L + 2L * 8L + 3L * 8L
  let locals = 3L * 8L + 2L * 8L
  let descriptor = 16L + 8L
  let execution = retained + tuple_some + locals + descriptor
  let actual = local_managed_task_capacity({
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }).unwrap()
  for
    (r, e, expected) in [
      (retained, execution, None),
      (retained - 1L, execution, Some(@resources.RetentionLimit)),
      (retained, execution - 1L, Some(@resources.ExecutionLimit)),
    ] {
    let root = @resources.create_ledger({
      planning_work: 1,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 0L,
      retained_bytes: r,
      execution_bytes: e,
    }).unwrap()
    let calls = Ref(0)
    match
      @resources.reserve_capacity(
        root,
        actual.retained_bytes,
        actual.execution_bytes,
      ) {
      Err(issue) => {
        assert_eq(Some(issue), expected)
        assert_eq(calls.val, 0)
      }
      Ok(capacity) => {
        defer @resources.settle_capacity(root, capacity).unwrap()
        assert_eq(expected, None)
        assert_true(
          @resources.capacity_reservation_covers(
            root, capacity, retained, execution,
          ),
        )
        let construct = () => {
          calls.val += 1
          LogicalWorkLimit(43, 20000000L, SourceFreeInstallation)
        }
        let original = construct()
        assert_eq(calls.val, 1)
        assert_eq(
          local_managed_advance_logical_work_policy(original),
          Some((43, 20000000L, "installation.sourceFreeMaxWork")),
        )
      }
    }
    let after = @resources.ledger_usage(root)
    assert_eq(after.live_reservations, 0)
    assert_eq(after.reserved_retention_bytes, 0L)
    assert_eq(after.reserved_execution_bytes, 0L)
    assert_eq(@resources.ledger_limits(root).retained_bytes, r)
    assert_eq(@resources.ledger_limits(root).execution_bytes, e)
  }
}
