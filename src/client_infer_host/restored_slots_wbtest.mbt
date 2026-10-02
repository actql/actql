///|
// These component fixtures use symbolic external evidence roots. Store
// authentication and formal attempt/policy/usage adoption remain Host duties;
// a structural read cannot certify them or authorize public completion.
fn restored_slots_fixture(
  failure : @model.ModelProviderFailure,
  rows? : String = "[{\"id\":\"a\",\"text\":\"hello\"}]",
  mixed? : Bool = false,
  success_first? : Bool = false,
) -> (
  @publication.ModelCaptureBundleRead,
  Array[@publication.RunEvidenceValue],
  Ref[Int],
) raise {
  let calls = Ref(0)
  let original = failed_outcome_start(
    failure,
    calls,
    rows~,
    mixed~,
    success_first~,
  )
  assert_true(fixture_finish(original) is Complete(_, ..))
  let saved = acquire_capture(original).unwrap()
  let records : Array[@publication.RunEvidenceValue] = []
  for index in 0..<@model.verified_model_capture_call_count(saved).unwrap() {
    let record = match invocation_evidence(original, index) {
      Some(evidence) => slot_binding_seal(slot_binding_record(evidence))
      None => observation_failure_record(saved, index)
    }
    assert_true(
      @model.bind_verified_model_slot_capture(saved, index, record) is Ok(_),
    )
    // Re-admit saved bytes, rather than keeping the old record or execution.
    records.push(
      @publication.admit_run_evidence_value(
        "model_slot_capture",
        @publication.run_evidence_value_json(record),
        16384,
        1024,
        20,
      ).unwrap(),
    )
  }
  let stream = @model.start_model_capture_export(saved, capture_export_limits()).unwrap()
  let wire = StringBuilder()
  let mut done = false
  for _ in 0..<1000 {
    let (terminal, chunk, _) = @model.advance_model_capture_export(stream, 1).unwrap()
    wire.write_string(chunk)
    if terminal {
      done = true
      break
    }
  }
  assert_true(done)
  let identity = @model.model_capture_export_identity(stream).unwrap()
  let body = wire.to_string()
  assert_true(@model.cleanup_model_capture_export(stream).unwrap())
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(original).unwrap())
  let bundle = @publication.read_model_capture_bundle(
    body, identity, 100000, 10000, 100,
  ).unwrap()
  (bundle, records, calls)
}

///|
fn restored_slots_read(
  bundle : @publication.ModelCaptureBundleRead,
  records : Array[@publication.RunEvidenceValue],
) -> @model.ModelSlotReplayRead raise {
  @model.read_model_slot_replay(
    slot_observation(
      Some(records.map(@publication.run_evidence_value_identity)),
    ),
    records,
    bundle,
    2,
    16384,
  ).unwrap()
}

///|
fn restored_slots_start(
  read : @model.ModelSlotReplayRead,
  rows? : String = "[{\"id\":\"a\",\"text\":\"hello\"}]",
  limits? : Limits = standard_limits(),
) -> Execution {
  let source = infer_fixture_program.replace(
    old="[{\"id\":\"a\",\"text\":\"hello\"}]",
    new=rows,
  )
  let prepared = fixture_prepared(source~)
  start_restored_slot_replay(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    read,
    limits,
    call_identity_plan(prepared),
  ).unwrap()
}

///|
test "saved failed slots replay without an old execution or new attempts" {
  for
    (failure, expected) in [
      (@model.RateLimit, "failed:rate_limit"),
      (@model.Timeout, "failed:timeout"),
      (@model.ProviderError, "failed:provider_error"),
      (@model.Refusal, "failed:refusal"),
      (@model.SchemaInvalid, "failed:schema_invalid"),
      (@model.SafetyRejected, "failed:safety_rejected"),
      (@model.Truncated, "failed:truncated"),
    ] {
    let (bundle, records, calls) = restored_slots_fixture(failure)
    assert_eq(@publication.model_capture_bundle_count(bundle), 0)
    let read = restored_slots_read(bundle, records)
    assert_true(@publication.release_model_capture_bundle_read(bundle))
    let replay = restored_slots_start(read)
    assert_true(@model.release_model_slot_replay(read))
    assert_true(!@model.release_model_slot_replay(read))
    guard fixture_finish(replay) is Complete(completed, ..) else {
      abort("failed observation did not replay")
    }
    assert_eq(@relation.completed_row_count(completed), 1)
    assert_true(
      @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
    )
    guard @relation.completed_cell(completed, 0, 1)
      is Some(@relation.Text(actual)) else {
      abort("missing failure outcome")
    }
    assert_eq(actual, expected)
    assert_true(
      @relation.completed_cell(completed, 0, 2) is Some(@relation.Null),
    )
    assert_true(invocation_evidence(replay, 0) is None)
    let usage = @model.model_execution_resource_usage(replay.model.unwrap())
    assert_eq(usage.attempts, 0)
    assert_eq(usage.transferred_bytes, 0L)
    assert_eq(usage.uncertain_transfer_bytes, 0L)
    let held = acquire_output(replay).unwrap()
    assert_true(!cleanup(replay).unwrap())
    assert_true(release_output(held))
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 1)
    assert_eq(records.length(), 1)
  }
}

///|
test "mixed saved slots keep logical and successful response positions distinct" {
  let rows = "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
  for success_first in [true, false] {
    let (bundle, records, calls) = restored_slots_fixture(
      @model.Timeout,
      rows~,
      mixed=true,
      success_first~,
    )
    assert_eq(@publication.model_capture_bundle_count(bundle), 1)
    let read = restored_slots_read(bundle, records)
    assert_true(@publication.release_model_capture_bundle_read(bundle))
    let replay = restored_slots_start(read, rows~)
    assert_true(@model.release_model_slot_replay(read))
    guard fixture_finish(replay) is Complete(completed, ..) else {
      abort("mixed observation did not replay")
    }
    assert_eq(@relation.completed_row_count(completed), 2)
    for (index, key) in [(0, "a"), (1, "b")] {
      guard @relation.completed_cell(completed, index, 0)
        is Some(@relation.Text(actual_key)) else {
        abort("missing replay key")
      }
      assert_eq(actual_key, key)
      let expected = if index == (if success_first { 0 } else { 1 }) {
        "ok"
      } else {
        "failed:timeout"
      }
      guard @relation.completed_cell(completed, index, 1)
        is Some(@relation.Text(actual)) else {
        abort("missing replay outcome")
      }
      assert_eq(actual, expected)
      if expected == "ok" {
        assert_true(invocation_evidence(replay, index) is Some(_))
        guard @relation.completed_cell(completed, index, 2)
          is Some(@relation.Captured(@admitted.Object(fields))) else {
          abort("missing replay value")
        }
        assert_eq(@admitted.element_count(fields), 2)
        assert_true(
          @admitted.element_at(fields, 0) is Some(("reason", @admitted.Null)),
        )
        assert_true(
          @admitted.element_at(fields, 1)
          is Some(("risk", @admitted.Text("high"))),
        )
      } else {
        assert_true(invocation_evidence(replay, index) is None)
        assert_true(
          @relation.completed_cell(completed, index, 2) is Some(@relation.Null),
        )
      }
    }
    let usage = @model.model_execution_resource_usage(replay.model.unwrap())
    assert_eq(usage.attempts, 0)
    assert_eq(usage.transferred_bytes, 0L)
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 2)
  }
}

///|
test "saved inventory rejects omission reorder mutation and changed input" {
  let rows = "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
  let (bundle, records, calls) = restored_slots_fixture(
    @model.Timeout,
    rows~,
    mixed=true,
  )
  let observation = slot_observation(
    Some(records.map(@publication.run_evidence_value_identity)),
  )
  for supplied in [[], [records[1]], [records[0], records[1], records[0]]] {
    assert_true(
      @model.read_model_slot_replay(observation, supplied, bundle, 3, 16384)
      is Err(@model.OutputIdentity),
    )
  }
  let read = @model.read_model_slot_replay(
    observation,
    [records[1], records[0]],
    bundle,
    2,
    16384,
  ).unwrap()
  let replay = restored_slots_start(read, rows~)
  assert_true(
    fixture_finish(replay)
    is Failed(
      Model(
        @model.InvocationEvidence(
          @publication.RunEvidenceReferenceMismatch("model_slot_capture_cids")
        )
      ),
      ..
    ),
  )
  assert_true(acquire_output(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_true(@model.release_model_slot_replay(read))
  let read = restored_slots_read(bundle, records)
  let changed = restored_slots_start(
    read,
    rows=rows.replace(old="first", new="changed"),
  )
  assert_true(
    fixture_finish(changed)
    is Failed(
      Model(
        @model.InvocationEvidence(
          @publication.RunEvidenceReferenceMismatch(
            "model_slot_capture.slot_cid"
          )
        )
      ),
      ..
    ),
  )
  assert_true(acquire_output(changed) is None)
  assert_true(cleanup(changed).unwrap())
  assert_true(@model.release_model_slot_replay(read))
  let supplied = records.copy()
  let read = restored_slots_read(bundle, supplied)
  let replay = restored_slots_start(read, rows~)
  supplied.pop() |> ignore
  assert_true(
    fixture_finish(replay) is Failed(Model(@model.OutputIdentity), ..),
  )
  assert_true(acquire_output(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_true(@model.release_model_slot_replay(read))
  assert_true(@publication.release_model_capture_bundle_read(bundle))
  assert_eq(calls.val, 2)
}

///|
test "saved failure replay work is exact and cancellation retains custody until stop" {
  let (bundle, records, calls) = restored_slots_fixture(@model.Timeout)
  // One replay-start transition, eight request-preparation transitions and
  // one matched saved failure. No bound is inferred from a runtime meter.
  for work in [10, 9] {
    let read = restored_slots_read(bundle, records)
    let limits = standard_limits()
    let replay = restored_slots_start(read, limits={
      ..limits,
      model: { ..limits.model, max_work: work, },
    })
    assert_true(@model.release_model_slot_replay(read))
    let terminal = fixture_finish(replay)
    if work == 10 {
      assert_true(terminal is Complete(_, ..))
    } else {
      assert_true(terminal is Failed(Model(@model.WorkLimit), ..))
      assert_true(acquire_output(replay) is None)
    }
    assert_true(cleanup(replay).unwrap())
  }
  let read = restored_slots_read(bundle, records)
  let replay = restored_slots_start(read)
  assert_true(@model.release_model_slot_replay(read))
  for _ in 0..<2000 {
    if request_preflight_pending(replay) {
      break
    }
    assert_true(advance(replay, 1).unwrap() is Continue(_))
  }
  assert_true(request_preflight_pending(replay))
  assert_true(cancel(replay))
  assert_true(!execution_stopped(replay))
  assert_true(!cleanup(replay).unwrap())
  assert_true(advance(replay, 1).unwrap() is Stopped(_))
  assert_true(acquire_output(replay) is None)
  assert_true(cleanup(replay).unwrap())
  let limited = @model.read_model_slot_replay(
    slot_observation(
      Some(records.map(@publication.run_evidence_value_identity)),
    ),
    records,
    bundle,
    1,
    1,
  ).unwrap()
  let replay = restored_slots_start(limited)
  assert_true(fixture_finish(replay) is Failed(Model(@model.RequestLimit), ..))
  assert_true(acquire_output(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_true(@model.release_model_slot_replay(limited))
  assert_true(@publication.release_model_capture_bundle_read(bundle))
  assert_eq(calls.val, 1)
}

///|
test "zero-key saved replay requires explicit inventory and no response records" {
  let (bundle, records, calls) = restored_slots_fixture(
    @model.Timeout,
    rows="[]",
  )
  assert_eq(records.length(), 0)
  assert_eq(calls.val, 0)
  assert_true(
    @model.read_model_slot_replay(
      slot_observation(None),
      records,
      bundle,
      0,
      16384,
    )
    is Err(@model.OutputIdentity),
  )
  let read = restored_slots_read(bundle, records)
  let replay = restored_slots_start(read, rows="[]")
  assert_true(@model.release_model_slot_replay(read))
  guard fixture_finish(replay) is Complete(completed, ..) else {
    abort("zero-key saved replay failed")
  }
  assert_eq(@relation.completed_row_count(completed), 0)
  assert_true(cleanup(replay).unwrap())
  assert_true(@publication.release_model_capture_bundle_read(bundle))
}

///|
test "saved slot replay refuses missing and extra successful response records" {
  let rows = "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
  let (mixed_bundle, mixed_records, mixed_calls) = restored_slots_fixture(
    @model.Timeout,
    rows~,
    mixed=true,
  )
  let (empty_bundle, failed_records, failed_calls) = restored_slots_fixture(
    @model.Timeout,
    rows~,
  )
  // Both owners ran the same Program and inputs. Only the adopted outcomes
  // differ, so unrelated response records cannot hide behind another call CID.
  let missing = restored_slots_read(empty_bundle, mixed_records)
  let replay = restored_slots_start(missing, rows~)
  assert_true(
    fixture_finish(replay)
    is Failed(
      Model(@model.InvocationEvidence(@publication.RunEvidenceInvalidShape)),
      ..
    ),
  )
  assert_true(acquire_output(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_true(@model.release_model_slot_replay(missing))
  let extra = restored_slots_read(mixed_bundle, failed_records)
  let replay = restored_slots_start(extra, rows~)
  assert_true(
    fixture_finish(replay) is Failed(Model(@model.OutputIdentity), ..),
  )
  assert_true(acquire_output(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_true(@model.release_model_slot_replay(extra))
  assert_true(@publication.release_model_capture_bundle_read(mixed_bundle))
  assert_true(@publication.release_model_capture_bundle_read(empty_bundle))
  assert_eq(mixed_calls.val, 2)
  assert_eq(failed_calls.val, 2)
}
