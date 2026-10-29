///|
// Ordinary two-row execution supplies real request/input binding originals.
// The second observation is an authored current-version fixture, not evidence
// of a new installed provider/profile or a conversion of the first record.
fn mixed_capture_replay_fixture(
  nullable? : Bool = false,
  input_known? : Bool = false,
  output_known? : Bool = false,
  metadata_kind? : String = "nonempty",
  changed_field? : String? = None,
) -> (@publication.ModelCaptureBundleRead, Array[String], Ref[Int]) raise {
  let calls = Ref(0)
  let original = contract_capacity_start(calls, 2, 133072L)
  assert_true(fixture_finish(original) is Complete(_, ..))
  assert_eq(calls.val, 2)
  let retained = acquire_capture(original).unwrap()
  let exporter = @model.start_model_capture_export(
    retained,
    capture_export_limits(),
  ).unwrap()
  let wire = StringBuilder()
  let mut complete = false
  for _ in 0..<1000 {
    let (terminal, chunk, _) = @model.advance_model_capture_export(exporter, 1).unwrap()
    wire.write_string(chunk)
    if terminal {
      complete = true
      break
    }
  }
  assert_true(complete)
  assert_true(@model.cleanup_model_capture_export(exporter).unwrap())
  assert_true(@model.release_verified_model_capture(retained))
  assert_true(cleanup(original).unwrap())
  guard @json.parse(wire.to_string()) is Object(bundle) &&
    bundle["captures"] is Array(records) &&
    records.length() == 2 &&
    records[0] is Object(first) &&
    records[1] is Object(second) &&
    second["evidence"] is Object(current) else {
    abort("two original captured observations are required")
  }
  let historical_wire = fixture_canonical(first["evidence"])
  current.remove("model_invocation_evidence_cid") |> ignore
  current["version"] = Json::string("actql-model-invocation-evidence/0.2")
  current["provider_reported_revision"] = Json::null()
  current["gateway_request_id"] = Json::null()
  current["raw_response_artifact_cid"] = Json::null()
  current["response_profile_cid"] = Json::string("sha256:" + "8".repeat(64))
  current["response_complete"] = Json::boolean(true)
  current["provider_metadata"] = Json::object({
    "fixture": Json::object({ "original": Json::string("e\u0301\r\n") }),
  })
  if nullable {
    current["provider_reported_model_id"] = Json::null()
    current["provider_request_id"] = Json::null()
    current["finish_reason"] = Json::null()
    current["input_tokens"] = if input_known {
      Json::number(0)
    } else {
      Json::null()
    }
    current["output_tokens"] = if output_known {
      Json::number(0)
    } else {
      Json::null()
    }
    if metadata_kind == "null" {
      current["provider_metadata"] = Json::null()
    } else if metadata_kind == "empty" {
      current["provider_metadata"] = Json::object({})
    }
  }
  if changed_field is Some(field) {
    current[field] = Json::string("sha256:" + "9".repeat(64))
  }
  let current_evidence = @publication.seal_run_evidence_value(
    "model_invocation_evidence",
    fixture_canonical(Json::object(current)),
    16384,
    1024,
    20,
  ).unwrap()
  second["evidence"] = @json.parse(
    @publication.run_evidence_value_json(current_evidence),
  )
  assert_eq(fixture_canonical(first["evidence"]), historical_wire)
  bundle.remove("bundle_cid") |> ignore
  bundle["version"] = Json::string("actql-model-capture-bundle/0.2")
  let sealed_bundle = @publication.seal_run_evidence_value(
    "model_capture_bundle",
    fixture_canonical(Json::object(bundle)),
    100000,
    10000,
    100,
  ).unwrap()
  let read = @publication.read_model_capture_bundle(
    @publication.run_evidence_value_json(sealed_bundle),
    @publication.run_evidence_value_identity(sealed_bundle),
    100000,
    10000,
    100,
  ).unwrap()
  (
    read,
    [historical_wire, @publication.run_evidence_value_json(current_evidence)],
    calls,
  )
}

///|
test "mixed old and current evidence replays original rows without new dispatch" {
  let (saved, originals, calls) = mixed_capture_replay_fixture()
  let original_bundle_cid = @publication.model_capture_bundle_identity(saved).unwrap()
  let source = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let prepared = fixture_prepared(source~)
  let replay = start_restored_replay(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared, attempts=2, wire_bytes=133072L),
  ).unwrap()
  assert_true(@publication.release_model_capture_bundle_read(saved))
  let completed = fixture_finish(replay)
  guard completed is Complete(output, ..) else {
    abort("original mixed saved observations must replay")
  }
  assert_eq(@relation.completed_row_count(output), 2)
  assert_eq(@relation.completed_column_count(output), 3)
  for (column, name) in [(0, "id"), (1, "outcome"), (2, "value")] {
    assert_eq(@relation.completed_column_name(output, column), Some(name))
  }
  for (row, key) in [(0, "a"), (1, "b")] {
    assert_true(
      @relation.completed_cell(output, row, 0) is Some(@relation.Text(actual)) &&
      actual == key,
    )
    assert_true(
      @relation.completed_cell(output, row, 1) is Some(@relation.Text("ok")),
    )
    guard @relation.completed_cell(output, row, 2)
      is Some(@relation.Captured(@admitted.Object(fields))) else {
      abort("missing original typed output")
    }
    assert_eq(@admitted.element_count(fields), 2)
    assert_true(
      @admitted.element_at(fields, 0) is Some(("reason", @admitted.Null)),
    )
    assert_true(
      @admitted.element_at(fields, 1) is Some(("risk", @admitted.Text("high"))),
    )
    assert_eq(
      @publication.run_evidence_value_json(
        invocation_evidence(replay, row).unwrap(),
      ),
      originals[row],
    )
  }
  assert_eq(calls.val, 2)
  let usage = @model.model_execution_resource_usage(replay.model.unwrap())
  assert_eq(usage.attempts, 0)
  assert_eq(usage.uncertain_transfer_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  let retained = acquire_capture(replay).unwrap()
  let exporter = @model.start_model_capture_export(
    retained,
    capture_export_limits(),
  ).unwrap()
  assert_true(!cleanup(replay).unwrap())
  let wire = StringBuilder()
  let mut finished = false
  for _ in 0..<1000 {
    let (terminal, chunk, _) = @model.advance_model_capture_export(exporter, 1).unwrap()
    wire.write_string(chunk)
    if terminal {
      finished = true
      break
    }
  }
  assert_true(finished)
  assert_eq(
    @model.model_capture_export_identity(exporter),
    Some(original_bundle_cid),
  )
  let exported = @publication.read_model_capture_bundle(
    wire.to_string(),
    original_bundle_cid,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(@publication.model_capture_bundle_count(exported), 2)
  for row in 0..<2 {
    assert_eq(
      @publication.run_evidence_value_json(
        @publication.model_capture_record_evidence(
          @publication.model_capture_bundle_record(exported, row).unwrap(),
        ),
      ),
      originals[row],
    )
  }
  assert_true(@publication.release_model_capture_bundle_read(exported))
  assert_true(@model.cleanup_model_capture_export(exporter).unwrap())
  assert_true(@model.release_verified_model_capture(retained))
  assert_true(cleanup(replay).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "mixed saved evidence refuses changed input without new dispatch" {
  let (saved, _, calls) = mixed_capture_replay_fixture()
  let source = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"changed\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let prepared = fixture_prepared(source~)
  let replay = start_restored_replay(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared, attempts=2, wire_bytes=133072L),
  ).unwrap()
  assert_true(@publication.release_model_capture_bundle_read(saved))
  assert_true(
    fixture_finish(replay) is Failed(Model(@model.OutputIdentity), ..),
  )
  assert_true(acquire_output(replay) is None)
  assert_true(acquire_capture(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "nullable current capture replays without fabricating metadata or usage" {
  for
    (input_known, output_known) in [
      (false, false),
      (true, false),
      (false, true),
    ] {
    let (saved, originals, calls) = mixed_capture_replay_fixture(
      nullable=true,
      input_known~,
      output_known~,
      metadata_kind=if input_known {
        "empty"
      } else if output_known {
        "nonempty"
      } else {
        "null"
      },
    )
    let expected_bundle_cid = @publication.model_capture_bundle_identity(saved)
    let source = infer_fixture_program.replace(
      old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
      new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
    )
    let prepared = fixture_prepared(source~)
    let replay = start_restored_replay(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      saved,
      standard_limits(),
      call_identity_plan(prepared, attempts=2, wire_bytes=133072L),
    ).unwrap()
    assert_true(@publication.release_model_capture_bundle_read(saved))
    guard fixture_finish(replay) is Complete(output, ..) else {
      abort("valid nullable observations must replay without a provider")
    }
    assert_eq(@relation.completed_row_count(output), 2)
    assert_true(
      @relation.completed_cell(output, 1, 0) is Some(@relation.Text("b")),
    )
    assert_true(
      @relation.completed_cell(output, 1, 1) is Some(@relation.Text("ok")),
    )
    for row in 0..<2 {
      assert_eq(
        @publication.run_evidence_value_json(
          invocation_evidence(replay, row).unwrap(),
        ),
        originals[row],
      )
    }
    assert_eq(calls.val, 2)
    let capture = capture(replay).unwrap().captures[1]
    assert_eq(capture.provider_model, None)
    assert_eq(capture.provider_request_id, None)
    assert_eq(capture.input_tokens, if input_known { Some(0L) } else { None })
    assert_eq(capture.output_tokens, if output_known { Some(0L) } else { None })
    let usage = @model.model_execution_resource_usage(replay.model.unwrap())
    assert_eq(usage.attempts, 0)
    assert_eq(usage.transferred_bytes, 0L)
    let retained = acquire_capture(replay).unwrap()
    let exporter = @model.start_model_capture_export(
      retained,
      capture_export_limits(),
    ).unwrap()
    let mut complete = false
    for _ in 0..<1000 {
      let (terminal, _, _) = @model.advance_model_capture_export(exporter, 1).unwrap()
      if terminal {
        complete = true
        break
      }
    }
    assert_true(complete)
    assert_eq(
      @model.model_capture_export_identity(exporter),
      expected_bundle_cid,
    )
    assert_true(!cleanup(replay).unwrap())
    assert_true(@model.cleanup_model_capture_export(exporter).unwrap())
    assert_true(@model.release_verified_model_capture(retained))
    assert_true(cleanup(replay).unwrap())
  }
}

///|
test "nullable replay cancellation keeps custody and publishes no partial output" {
  let (saved, _, calls) = mixed_capture_replay_fixture(nullable=true)
  let source = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let prepared = fixture_prepared(source~)
  let replay = start_restored_replay(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared, attempts=2, wire_bytes=133072L),
  ).unwrap()
  assert_true(@publication.release_model_capture_bundle_read(saved))
  let mut reached = false
  let mut sealing_intervals = 0
  let mut was_sealing = false
  for _ in 0..<2000 {
    let sealing = match replay.model {
      Some(model) => @model.model_execution_sealing_observation(model)
      None => false
    }
    if sealing && !was_sealing {
      sealing_intervals += 1
      if sealing_intervals == 2 {
        reached = true
        break
      }
    }
    was_sealing = sealing
    assert_true(advance(replay, 1).unwrap() is Continue(_))
  }
  assert_true(reached)
  assert_true(cancel(replay))
  assert_true(!cleanup(replay).unwrap())
  assert_true(advance(replay, 1).unwrap() is Stopped(_))
  assert_true(acquire_output(replay) is None)
  assert_true(acquire_capture(replay) is None)
  assert_true(cleanup(replay).unwrap())
  assert_true(cleanup(replay).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "nullable metadata replay has quantum independent result and logical work" {
  let (saved, originals, calls) = mixed_capture_replay_fixture(nullable=true)
  let source = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let mut expected_work : Int64? = None
  for quantum in [1, 7] {
    let prepared = fixture_prepared(source~)
    let replay = start_restored_replay(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      saved,
      standard_limits(),
      call_identity_plan(prepared, attempts=2, wire_bytes=133072L),
    ).unwrap()
    let mut complete = false
    for _ in 0..<2000 {
      match advance(replay, quantum).unwrap() {
        Continue(_) => ()
        Complete(output, work~) => {
          assert_eq(@relation.completed_row_count(output), 2)
          if expected_work is Some(expected) {
            assert_eq(work, expected)
          } else {
            expected_work = Some(work)
          }
          complete = true
          break
        }
        _ => abort("nullable replay must complete for either quantum")
      }
    }
    assert_true(complete)
    assert_eq(
      @publication.run_evidence_value_json(
        invocation_evidence(replay, 1).unwrap(),
      ),
      originals[1],
    )
    assert_true(cleanup(replay).unwrap())
  }
  assert_true(@publication.release_model_capture_bundle_read(saved))
  assert_eq(calls.val, 2)
}

///|
test "nullable saved capture still rejects either changed response hash" {
  for
    field in [
      "structured_response_artifact_cid", "validated_structured_output_cid",
    ] {
    let (saved, _, calls) = mixed_capture_replay_fixture(
      nullable=true,
      changed_field=Some(field),
    )
    let source = infer_fixture_program.replace(
      old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
      new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
    )
    let prepared = fixture_prepared(source~)
    let replay = start_restored_replay(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      saved,
      standard_limits(),
      call_identity_plan(prepared, attempts=2, wire_bytes=133072L),
    ).unwrap()
    assert_true(@publication.release_model_capture_bundle_read(saved))
    assert_true(
      fixture_finish(replay) is Failed(Model(@model.InvocationEvidence(_)), ..),
    )
    assert_true(acquire_output(replay) is None)
    assert_true(acquire_capture(replay) is None)
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 2)
  }
}
