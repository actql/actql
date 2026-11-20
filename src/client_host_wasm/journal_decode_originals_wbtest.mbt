///|
// Pure closed decoder/real Ledger controls. No Store, Account grant, dispatch,
// normal Host or fuel qualification is supplied by this fixture.
fn journal_decode_fixture(
  cleanup? : () -> Bool = () => true,
  retention? : Int64 = 33554432L,
  execution? : Int64 = 268435456L,
) -> (
  Instance,
  StoredJournalObservation,
  StoredJournalDecodeFrame,
  @buffers.BufferSlot,
) raise {
  let (value, _, parent) = sdk_row_original_fixture(retention, execution~)
  let slot = @buffers.reserve_output_buffer(value.pool, 2, 0L, cleanup).unwrap()
  let row = submission_append_run_inspection(
    submission_identity_row(@utf8.encode(submission_identity_wire)),
  ).unwrap()
  let child : StoredJournalObservation = {
    material: 0,
    configuration: 0,
    physical: 43,
    slot,
    invoked: true,
    closing: false,
    outcome: None,
    admission_produced: false,
  }
  value.journal_observations[73] = child
  let frame = open_journal_decode_frame(
    value,
    73,
    child,
    @host.client_request_scope_cid(row.request),
  ).unwrap()
  (value, child, frame, parent)
}

///|
fn journal_decode_fixture_row() -> @host.ClientJournalPhysicalRow {
  let body = @utf8.encode(submission_identity_wire)
  let original = submission_append_run_inspection(submission_identity_row(body)).unwrap()
  { key: @host.client_request_scope_cid(original.request), revision: 7L, body, }
}

///|
test "journal typed observation quote refuses the original smaller component profile" {
  let (value, _, _, parent) = journal_decode_fixture()
  let (retention, peak) = journal_observation_construction_capacity().unwrap()
  let limits = @resources.ledger_limits(value.root)
  println(
    "nested observation preconstructor bytes: retention=\{retention}; execution=\{peak}; fixture retained limit=\{limits.retained_bytes}; fixture execution limit=\{limits.execution_bytes}",
  )
  // This test does not lift the fixture profile to accommodate a quote.
  // Actual reserve refuses if any same-Root constructor overlap cannot fit.
  let reserved = @resources.reserve_capacity(value.root, retention, peak)
  assert_true(peak > limits.execution_bytes)
  assert_true(reserved is Err(_))
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
// These quantities are the unchanged _ordinary_core_limits Source, not a
// raised product profile. Existing parent/input/pool/output holdings coexist.
fn journal_observation_profile_fixture(
  cleanup? : () -> Bool = () => true,
) -> (
  Instance,
  StoredJournalObservation,
  StoredJournalDecodeFrame,
  @buffers.BufferSlot,
) raise {
  journal_decode_fixture(cleanup~, retention=536870912L, execution=603979776L)
}

///|
fn journal_observation_fixture_row() -> @host.ClientJournalPhysicalRow {
  let cid = (digit : String) => "sha256:" + digit.repeat(64)
  let prepared = @publication.seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\",\"invocation_template_cid\":\"" +
    cid("6") +
    "\",\"compiled_plan_cid\":\"" +
    cid("1") +
    "\",\"execution_context_cid\":\"" +
    cid("2") +
    "\",\"host_policy_cid\":\"" +
    cid("5") +
    "\",\"policy_decision\":\"allow\",\"expires_at\":\"2099-01-01T00:00:00.000Z\"}",
    131072,
    8192,
    64,
  ).unwrap()
  let authorization = @publication.seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\",\"prepared_invocation_cid\":\"" +
    @publication.run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    cid("2") +
    "\",\"host_policy_cid\":\"" +
    cid("5") +
    "\",\"decision\":\"allowed\"}",
    131072,
    8192,
    64,
  ).unwrap()
  let envelope = @encode.writer(131072, 8, 1) catch {
    _ => abort("fixture writer")
  }
  @encode.begin_object(envelope) catch {
    _ => abort("fixture begin")
  }
  @encode.key(envelope, "authorization") catch {
    _ => abort("fixture key")
  }
  @encode.string_value(
    envelope,
    @publication.run_evidence_value_json(authorization),
  ) catch {
    _ => abort("fixture authorization")
  }
  @encode.key(envelope, "prepared") catch {
    _ => abort("fixture key")
  }
  @encode.string_value(envelope, @publication.run_evidence_value_json(prepared)) catch {
    _ => abort("fixture prepared")
  }
  @encode.end_object(envelope) catch {
    _ => abort("fixture end")
  }
  let wire = @encode.finish(envelope) catch { _ => abort("fixture finish") }
  let row = journal_decode_fixture_row()
  let (original, _, _) = @host.decode_client_run_journal_row_with_observation_originals(
    row.body,
  ).unwrap()
  let body = @host.client_run_journal_row_body(
    original,
    run_observation_originals=Some(wire),
  ).unwrap()
  { ..row, body, }
}

///|
fn journal_assert_observation_reuse(
  value : Instance,
  child : StoredJournalObservation,
  frame : StoredJournalDecodeFrame,
  row : @host.ClientJournalPhysicalRow,
) -> Unit raise {
  let constructions = Ref(0)
  let initial = @resources.ledger_usage(value.root)
  let parent = value.runs.get(1).unwrap()
  let input = parent.borrow
  let overlap = Ref(false)
  let before = () => {
    constructions.val += 1
    overlap.val = journal_decode_frame_current(value, child, frame) &&
      @resources.capacity_reservation_open(frame.capacity) &&
      !input.returned &&
      @buffers.buffer_length(value.pool, parent.slot) == Some(2) &&
      @buffers.buffer_output_limit(value.pool, child.slot) == Some(2) &&
      frame.rows is Some(cell) &&
      @resources.capacity_reservation_open(cell.capacity) &&
      @resources.ledger_usage(value.root).reserved_execution_bytes >
      initial.reserved_execution_bytes
  }
  let first = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_observation=Some(before),
  ).unwrap()
  assert_eq(constructions.val, 1)
  // This was observed INSIDE the actual nested constructor call, while the
  // SAME current frame, borrowed parent input and physical output remained.
  // It does not assert a normal Host/Account or physical ACK qualification.
  assert_true(overlap.val)
  let cell = frame.selected.unwrap()
  let original = cell.observation.unwrap()
  let retained = @resources.ledger_usage(value.root)
  assert_true(
    retained.reserved_retention_bytes > initial.reserved_retention_bytes,
  )
  assert_eq(retained.reserved_execution_bytes, initial.reserved_execution_bytes)
  let same = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_observation=Some(before),
  ).unwrap()
  assert_eq(constructions.val, 1)
  assert_true(physical_equal(original, cell.observation.unwrap()))
  assert_eq(
    @publication.publication_contract_identity(first.definition),
    @publication.publication_contract_identity(same.definition),
  )
  let decoded = cell.decoded.unwrap()
  assert_true(
    validate_sdk_run_row_decoded(
      Ok(({ ..decoded.0, checkpoint: Some([]), }, decoded.1, decoded.2)),
      observation_original=Some(original),
    )
    is Err(-42),
  )
  let bad_definition = @publication.seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"other\",\"compiled_plan_cid\":\"sha256:" +
    "f".repeat(64) +
    "\",\"invocation_template_cid\":\"sha256:" +
    "6".repeat(64) +
    "\",\"authorization_context_cid\":\"sha256:" +
    "2".repeat(64) +
    "\",\"input_artifact_set_cid\":\"sha256:" +
    "3".repeat(64) +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\",\"valid_until\":\"2099-01-01T00:00:00.000Z\"}",
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    validate_sdk_run_row_decoded(
      Ok(({ ..decoded.0, definition: bad_definition, }, decoded.1, decoded.2)),
      observation_original=Some(original),
    )
    is Err(-31),
  )
  assert_true(
    journal_decode_run_inspection(value, { ..child, physical: 99, }, frame, row)
    is Err(-2),
  )
  assert_true(
    journal_decode_run_inspection(value, child, { ..frame, handle: 99, }, row)
    is Err(-2),
  )
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      { ..row, revision: row.revision + 1L, },
      before_observation=Some(before),
    ).unwrap(),
  )
  assert_eq(constructions.val, 2)
}

///|
test "journal typed observation reuses actual restore while preserving same-frame overlap and fresh refusals" {
  let (value, child, frame, parent) = journal_observation_profile_fixture()
  let row = journal_observation_fixture_row()
  journal_assert_observation_reuse(value, child, frame, row)
  // The assertion helper returned; no test-held nested DATA loan crosses close.
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal typed observation exact construction allowance admits and one-short refuses before restore" {
  for short in [false, true] {
    let (value, child, frame, parent) = journal_observation_profile_fixture()
    let row = journal_observation_fixture_row()
    let (_, outer) = journal_decode_row_capacity(row).unwrap()
    let (_, nested) = journal_observation_construction_capacity().unwrap()
    let required = outer + nested
    let usage = @resources.ledger_usage(value.root)
    let available = @resources.ledger_limits(value.root).execution_bytes -
      usage.reserved_execution_bytes
    let blocker = @resources.reserve_capacity(
      value.root,
      0L,
      available - required + (if short { 1L } else { 0L }),
    ).unwrap()
    let constructions = Ref(0)
    let before = () => constructions.val += 1
    let first = journal_decode_run_inspection(
      value,
      child,
      frame,
      row,
      before_observation=Some(before),
    )
    if short {
      assert_true(first is Err(-4))
      assert_eq(constructions.val, 0)
      assert_true(frame.rows.unwrap().observation is None)
      assert_true(
        @resources.capacity_reservation_open(frame.rows.unwrap().capacity),
      )
      let (record, local_policy, observation) = @host.decode_client_run_journal_row_with_observation_originals(
        row.body,
      ).unwrap()
      assert_true(
        validate_sdk_run_row_decoded(
          Ok(({ ..record, checkpoint: Some([]), }, local_policy, observation)),
          observation_construction_issue=-4,
          before_observation=Some(before),
        )
        is Err(-42),
      )
    } else {
      assert_true(first is Ok(_))
      assert_eq(constructions.val, 1)
      assert_true(frame.selected.unwrap().observation is Some(_))
    }
    let second = journal_decode_run_inspection(
      value,
      child,
      frame,
      row,
      before_observation=Some(before),
    )
    assert_eq(second is Err(-4), short)
    assert_eq(constructions.val, if short { 0 } else { 1 })
    assert_eq(close_journal_observation(value.nonce, 73), 0)
    @resources.settle_capacity(value.root, blocker).unwrap()
    sdk_row_original_fixture_close(value, parent)
  }
}

///|
test "journal typed observation drops selected and foreign aliases before exact close debt and physical pending" {
  let ready = Ref(false)
  let (value, child, frame, parent) = journal_observation_profile_fixture(cleanup=() => {
    ready.val
  })
  let row = journal_observation_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  ignore(
    journal_decode_run_inspection(value, child, frame, {
      ..row,
      key: "foreign-key",
    }).unwrap(),
  )
  assert_true(frame.rows.unwrap().observation is Some(_))
  assert_true(frame.selected.unwrap().observation is Some(_))
  assert_eq(dispose_journal_decode_rows(value, frame, true), 0)
  let selected = frame.selected.unwrap()
  assert_true(selected.observation is None)
  assert_true(selected.decoded is Some(_) && selected.row is Some(_))
  assert_true(@resources.capacity_reservation_open(selected.capacity))
  @resources.settle_capacity(value.root, selected.capacity).unwrap()
  frame.issue = -42
  assert_true(close_journal_observation(value.nonce, 73) != 0)
  assert_true(child.outcome is Some(Observed(Err(-42), None)))
  ready.val = true
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal typed observation constructor and later validation errors keep original funded cleanup" {
  for later in [false, true] {
    let ready = Ref(false)
    let (value, child, frame, parent) = journal_observation_profile_fixture(cleanup=() => {
      ready.val
    })
    let row = journal_observation_fixture_row()
    let (record, _, wire) = @host.decode_client_run_journal_row_with_observation_originals(
      row.body,
    ).unwrap()
    let bad = if later {
      @host.client_run_journal_row_body(
        { ..record, publication_policy_originals: Some("{}"), },
        run_observation_originals=wire,
      ).unwrap()
    } else {
      @host.client_run_journal_row_body(
        record,
        run_observation_originals=Some(wire.unwrap() + " "),
      ).unwrap()
    }
    let constructions = Ref(0)
    assert_true(
      journal_decode_run_inspection(
        value,
        child,
        frame,
        { ..row, body: bad, },
        before_observation=Some(() => constructions.val += 1),
      )
      is Err(-31),
    )
    assert_eq(constructions.val, 1)
    assert_eq(frame.rows.unwrap().observation is Some(_), later)
    assert_true(
      @resources.capacity_reservation_open(frame.rows.unwrap().capacity),
    )
    assert_true(close_journal_observation(value.nonce, 73) != 0)
    assert_true(child.outcome is Some(Observed(Err(-31), None)))
    ready.val = true
    assert_eq(close_journal_observation(value.nonce, 73), 0)
    sdk_row_original_fixture_close(value, parent)
  }
}

///|
test "journal same-frame pure original avoids repeated construction but keeps row changes distinct" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let constructions = Ref(0)
  let observe = _ => {
    constructions.val += 1
    Ok(())
  }
  let first = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_construction=Some(observe),
  ).unwrap()
  assert_eq(constructions.val, 3)
  let usage = @resources.ledger_usage(value.root)
  let same = journal_decode_run_inspection(
    value,
    child,
    frame,
    { ..row, body: @utf8.encode(submission_identity_wire), },
    before_construction=Some(observe),
  ).unwrap()
  assert_true(physical_equal(first.request, same.request))
  assert_true(physical_equal(first.definition, same.definition))
  assert_eq(constructions.val, 3)
  assert_eq(@resources.ledger_usage(value.root), usage)
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      { ..row, revision: 8L, },
      before_construction=Some(observe),
    ).unwrap(),
  )
  assert_eq(constructions.val, 6)
  let changed = {
    ..row,
    body: @utf8.encode(
      submission_identity_wire.replace(
        old="\"cancellation_requested\":false",
        new="\"cancellation_requested\":true",
      ),
    ),
  }
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      changed,
      before_construction=Some(observe),
    ).unwrap(),
  )
  assert_eq(constructions.val, 9)
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      { ..row, key: "foreign-key", },
      before_construction=Some(observe),
    ).unwrap(),
  )
  assert_eq(constructions.val, 12)
  let returned = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_construction=Some(observe),
  ).unwrap()
  assert_eq(constructions.val, 12)
  assert_true(physical_equal(first.request, returned.request))
  assert_true(
    journal_decode_run_inspection(value, { ..child, physical: 44, }, frame, row)
    is Err(-2),
  )
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  assert_true(
    journal_decode_run_inspection(value, child, frame, row) is Err(-2),
  )
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame one-short retention keeps the original full decoder path" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let (retention, _) = journal_decode_row_capacity(row).unwrap()
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(
    value.root,
    available - retention + 1L,
    0L,
  ).unwrap()
  let limited = @resources.ledger_usage(value.root)
  let constructions = Ref(0)
  for _ in 0..<2 {
    ignore(
      journal_decode_run_inspection(
        value,
        child,
        frame,
        row,
        before_construction=Some(_ => {
          constructions.val += 1
          Ok(())
        }),
      ).unwrap(),
    )
  }
  assert_eq(constructions.val, 6)
  assert_true(frame.rows is None)
  assert_eq(@resources.ledger_usage(value.root), limited)
  @resources.settle_capacity(value.root, blocker).unwrap()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  assert_true(frame.rows is Some(_))
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame selected output backing survives frame exit until actual child close" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let selected = journal_decode_run_inspection(value, child, frame, row).unwrap()
  let selected_cell = frame.selected.unwrap()
  let selected_token = selected_cell.capacity
  ignore(
    journal_decode_run_inspection(value, child, frame, {
      ..row,
      key: "other-row",
    }).unwrap(),
  )
  let foreign_token = frame.rows.unwrap().capacity
  assert_eq(dispose_journal_decode_rows(value, frame, true), 0)
  assert_false(@resources.capacity_reservation_open(foreign_token))
  assert_true(@resources.capacity_reservation_open(selected_token))
  assert_true(physical_equal(frame.rows.unwrap(), selected_cell))
  assert_true(
    physical_equal(selected_cell.decoded.unwrap().0.request, selected.request),
  )
  assert_true(
    journal_decode_run_inspection(value, child, frame, row) is Err(-2),
  )
  // Result DATA is consumed while its SAME original child still owns backing.
  assert_true(
    @resources.capacity_reservation_covers(
      value.root,
      selected_token,
      selected_cell.retention,
      0L,
    ),
  )
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let close_blocker = @resources.reserve_capacity(
    value.root,
    available - 1L,
    0L,
  ).unwrap()
  // Close needs no fresh storage/admission even with only one free byte.
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(value.root, close_blocker).unwrap()
  assert_false(@resources.capacity_reservation_open(selected_token))
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame reentry and unsupported originals retain their primary refusal" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let entered = Ref(false)
  let nested_refusal = Ref(false)
  let refusal = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_construction=Some(_ => {
      if !entered.val {
        entered.val = true
        nested_refusal.val = journal_decode_run_inspection(
            value, child, frame, row,
          )
          is Err(-33)
      }
      // Ignoring a nested refusal must not turn the outer construction green.
      Ok(())
    }),
  )
  assert_true(refusal is Err(-33))
  assert_true(nested_refusal.val)
  assert_true(frame.rows.unwrap().decoded is None)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
  let (value, child, frame, parent) = journal_decode_fixture()
  let unsupported = {
    ..row,
    body: @utf8.encode(
      submission_identity_wire.replace(
        old="\"checkpoint\":null",
        new="\"checkpoint\":\"[]\"",
      ),
    ),
  }
  assert_true(
    journal_decode_run_inspection(value, child, frame, unsupported) is Err(-42),
  )
  assert_true(frame.rows.unwrap().decoded is None)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame partial cleanup retains only exact pending tokens and original error" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  let tail = frame.rows.unwrap()
  ignore(
    journal_decode_run_inspection(value, child, frame, { ..row, revision: 8L, }).unwrap(),
  )
  let head = frame.rows.unwrap()
  let foreign = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 1024L,
    execution_bytes: 1024L,
  }).unwrap()
  let foreign_token = @resources.reserve_capacity(foreign, 1L, 0L).unwrap()
  let wrong = { ..tail, capacity: foreign_token, }
  head.next = Some(wrong)
  child.outcome = Some(Observed(Err(-42), Some(frame)))
  assert_eq(close_journal_observation(value.nonce, 73), -4)
  assert_false(@resources.capacity_reservation_open(head.capacity))
  assert_true(@resources.capacity_reservation_open(tail.capacity))
  assert_true(@resources.capacity_reservation_open(foreign_token))
  assert_true(physical_equal(frame.rows.unwrap(), wrong))
  assert_true(
    child.outcome is Some(Decoding(debt)) &&
    physical_equal(debt, frame) &&
    debt.issue == -42,
  )
  // Restore this explicit foreign-token corruption fixture, not business state.
  frame.rows = Some(tail)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(foreign, foreign_token).unwrap()
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame one-short frame admission preserves unmodified pure inspection" {
  let (value, child, _, parent) = journal_decode_fixture()
  assert_eq(prepare_journal_observation_close(value, child), 0)
  assert_eq(settle_journal_observation_close_capacity(value, child), 0)
  child.closing = false
  let row = journal_decode_fixture_row()
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(
    value.root,
    available - journal_decode_frame_capacity(indexed=true).unwrap() + 1L,
    0L,
  ).unwrap()
  let before = @resources.ledger_usage(value.root)
  assert_true(open_journal_decode_frame(value, 73, child, row.key) is None)
  assert_true(child.outcome is None)
  assert_eq(@resources.ledger_usage(value.root), before)
  let original = submission_append_run_inspection(row).unwrap()
  assert_eq(@host.client_request_scope_cid(original.request), row.key)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(value.root, blocker).unwrap()
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame outer codec reuse never skips the original SDK purpose validator" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  let cell = frame.rows.unwrap()
  let (decoded, policy, observation) = cell.decoded.unwrap()
  // Explicit private-DATA corruption control: the purpose validator must still
  // see this unsupported field even on the exact-body outer-codec hit.
  cell.decoded = Some(
    ({ ..decoded, checkpoint: Some("[]"), }, policy, observation),
  )
  assert_true(
    journal_decode_run_inspection(value, child, frame, row) is Err(-42),
  )
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal close resumes exact completed token settlement before pointer unlink" {
  for position in ["row", "frame", "pending"] {
    let (value, child, frame, parent) = journal_decode_fixture()
    if position == "row" {
      ignore(
        journal_decode_run_inspection(
          value,
          child,
          frame,
          journal_decode_fixture_row(),
        ).unwrap(),
      )
      let cell = frame.rows.unwrap()
      cell.decoded = None
      cell.row = None
      frame.selected = None
      // Execute the ACTUAL trusted settlement, then leave its link intact:
      // precisely the completed-settlement / pre-unlink interruption boundary.
      @resources.settle_capacity(value.root, cell.capacity).unwrap()
    } else if position == "pending" {
      let pending = @resources.reserve_capacity(value.root, 1L, 0L).unwrap()
      frame.pending = Some(pending)
      @resources.settle_capacity(value.root, pending).unwrap()
    } else {
      assert_eq(prepare_journal_observation_close(value, child), 0)
      guard child.outcome is Some(ReservingDecode(capacity, _)) else {
        fail("Expected token-only debt, no frame before its settlement")
      }
      @resources.settle_capacity(value.root, capacity).unwrap()
    }
    assert_eq(close_journal_observation(value.nonce, 73), 0)
    sdk_row_original_fixture_close(value, parent)
  }
}

///|
test "journal close drops success payload before selected settlement and later frame failure" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let foreign = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 1024L,
    execution_bytes: 1024L,
  }).unwrap()
  let foreign_token = @resources.reserve_capacity(foreign, 1L, 0L).unwrap()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  let selected_token = frame.selected.unwrap().capacity
  let wrong_frame = { ..frame, capacity: foreign_token, }
  // Exercise the ACTUAL payload-to-debt function with a real selected codec
  // alias. Production instantiates this same function with its opaque saved
  // observation. The returned variant cannot retain any successful T value.
  child.outcome = Some(
    journal_close_payload(
      Ok(journal_decode_run_inspection(value, child, frame, row).unwrap()),
      wrong_frame,
    ),
  )
  assert_true(child.outcome is Some(Decoding(_)))
  assert_true(@resources.capacity_reservation_open(selected_token))
  assert_eq(close_journal_observation(value.nonce, 73), -4)
  // The selected token really settled; later frame failure must leave NO
  // Observed(Ok(...)) payload borrowing its now-unfunded request/Definition.
  assert_false(@resources.capacity_reservation_open(selected_token))
  assert_true(
    child.outcome is Some(ReservingDecode(token, 0)) &&
    physical_equal(token, foreign_token),
  )
  assert_true(wrong_frame.selected is None && wrong_frame.rows is None)
  // Restore only the explicit foreign-token fixture. The SAME original frame
  // still has its already-spent cell linked, which close must recognize.
  child.outcome = Some(Decoding(frame))
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(foreign, foreign_token).unwrap()
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal close never skips foreign spent tokens or loses error across physical pending" {
  let ready = Ref(false)
  let (value, child, frame, parent) = journal_decode_fixture(cleanup=() => {
    ready.val
  })
  let row = journal_decode_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  let original = frame.rows.unwrap()
  let foreign = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 1024L,
    execution_bytes: 1024L,
  }).unwrap()
  let foreign_spent = @resources.reserve_capacity(foreign, 1L, 0L).unwrap()
  @resources.settle_capacity(foreign, foreign_spent).unwrap()
  assert_false(@resources.capacity_reservation_open(foreign_spent))
  let wrong = { ..original, capacity: foreign_spent, }
  frame.rows = Some(wrong)
  child.outcome = Some(Observed(Err(-42), Some(frame)))
  assert_eq(close_journal_observation(value.nonce, 73), -4)
  assert_true(child.outcome is Some(Decoding(debt)) && debt.issue == -42)
  assert_true(@resources.capacity_reservation_open(original.capacity))
  // A false open Bool was not sufficient: the trusted same-Ledger settlement
  // refused the foreign token. Restore the negative fixture's original debt.
  frame.rows = Some(original)
  assert_true(close_journal_observation(value.nonce, 73) != 0)
  assert_false(@resources.capacity_reservation_open(original.capacity))
  assert_false(@resources.capacity_reservation_open(frame.capacity))
  // Even though physical cleanup is pending, NO frame/controller remains
  // reachable under its spent token: only the existing scalar error survives.
  assert_true(child.outcome is Some(Observed(Err(-42), None)))
  ready.val = true
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame index probes distinct rows without re-decoding on exact repeat" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let index = frame.index.unwrap()
  let original = journal_decode_fixture_row()
  let constructions = Ref(0)
  let observe = _ => {
    constructions.val += 1
    Ok(())
  }
  assert_eq(journal_decode_frame_capacity(), Some(296L))
  assert_eq(journal_decode_frame_capacity(indexed=true), Some(49568L))
  assert_true(
    @resources.capacity_reservation_matches(
      value.root,
      frame.capacity,
      49568L,
      49568L,
    ),
  )
  let mut probes = 0
  for ordinal in 0..<32 {
    let row = { ..original, key: "index-fixture-key-\{ordinal}", }
    let (slot, steps) = journal_decode_index_probe(index, row.key)
    assert_true(slot >= 0 && index[slot] is None)
    probes += steps
    ignore(
      journal_decode_run_inspection(
        value,
        child,
        frame,
        row,
        before_construction=Some(observe),
      ).unwrap(),
    )
    assert_true(
      index[slot] is Some(cell) &&
      cell.row is Some(saved) &&
      saved.key == row.key,
    )
  }
  assert_eq(frame.indexed_rows, 32)
  assert_eq(constructions.val, 96)
  for ordinal in 0..<32 {
    let row = { ..original, key: "index-fixture-key-\{ordinal}", }
    let (slot, steps) = journal_decode_index_probe(index, row.key)
    assert_true(slot >= 0 && index[slot] is Some(_))
    probes += steps
    ignore(
      journal_decode_run_inspection(
        value,
        child,
        frame,
        row,
        before_construction=Some(observe),
      ).unwrap(),
    )
  }
  assert_true(probes >= 64 && probes <= 64 * 32)
  assert_eq(constructions.val, 96)
  println(
    "journal index probe control: 32 distinct, 32 repeats, \{probes} probes, 96 decode phases",
  )
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  assert_true(frame.index is None && frame.rows is None)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame index collision ceiling uses the complete decoder" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let index = frame.index.unwrap()
  let original = journal_decode_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, original).unwrap())
  let cell = frame.rows.unwrap()
  let row = { ..original, key: "collision-pressure-fixture", }
  let mask = journal_decode_index_slots - 1
  let start = Hash::hash(row.key) & mask
  // Deterministic probe pressure only. All borrowed aliases belong to the
  // same admitted index; the original cell remains in the cleanup list.
  for offset in 0..<32 {
    index[(start + offset) & mask] = Some(cell)
  }
  assert_eq(journal_decode_index_probe(index, row.key), (-1, 32))
  let constructions = Ref(0)
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      row,
      before_construction=Some(_ => {
        constructions.val += 1
        Ok(())
      }),
    ).unwrap(),
  )
  assert_eq(constructions.val, 3)
  assert_eq(frame.indexed_rows, 1)
  let unindexed = frame.rows.unwrap()
  assert_true(
    unindexed.next is Some(previous) && physical_equal(previous, cell),
  )
  let (retention, _) = journal_decode_row_capacity(row).unwrap()
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(
    value.root,
    available - retention + 1L,
    0L,
  ).unwrap()
  let limited = @resources.ledger_usage(value.root)
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      row,
      before_construction=Some(_ => {
        constructions.val += 1
        Ok(())
      }),
    ).unwrap(),
  )
  assert_eq(constructions.val, 3)
  assert_true(physical_equal(frame.rows.unwrap(), unindexed))
  assert_eq(@resources.ledger_usage(value.root), limited)
  @resources.settle_capacity(value.root, blocker).unwrap()
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  assert_true(frame.index is None && frame.rows is None)
  sdk_row_original_fixture_close(value, parent)
}
