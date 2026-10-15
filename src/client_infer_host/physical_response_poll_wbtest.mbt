///|
// Independently authored canonical profile; fixture build identities are not
// shipped SDK originals or proof that an installed public adapter is funded.
fn async_response_profile() -> @environment.ModelResponseProfile {
  let wire =
    #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1000,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:c5462911d6a06bf20e1cb2bc6467f4fbda535ae2ec557016e8c3a2ab315f0a5b","task":{"contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","kind":"structured_generate","output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3"},"version":"actql-model-response-profile/0.1"}
  @environment.read_model_response_profile(
    @utf8.encode(wire),
    "sha256:c5462911d6a06bf20e1cb2bc6467f4fbda535ae2ec557016e8c3a2ab315f0a5b",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
}

///|
fn async_response_installation() -> @environment.ModelResponseProfileInstallation {
  {
    builder_id: "fixture/http-builder",
    builder_revision: "1",
    codec_id: "fixture/chat-one",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    sdk: None,
    endpoint: "https://fixture.invalid/v1/chat/completions",
    http_method: "POST",
    streaming: false,
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "generation_finish",
  }
}

///|
fn async_response_observation(
  metadata : @canonical.CanonicalValue?,
) -> @model.ModelPhysicalResponse {
  {
    value: @admitted.object_value([
      ("reason", @admitted.null_value()),
      ("risk", @admitted.text_value("high", 100).unwrap()),
    ]).unwrap(),
    observation: {
      origin: @publication.Reported,
      provider_model: None,
      provider_revision: None,
      provider_request_id: None,
      gateway_request_id: None,
      provider_finish_reason: None,
      historical_finish_reason: None,
      input_tokens: None,
      output_tokens: None,
      observed_at: "2026-10-02T00:00:00.000Z",
      response_profile_cid: Some(
        @environment.model_response_profile_identity(async_response_profile()),
      ),
      response_complete: Some(true),
      raw_response_artifact_cid: None,
      provider_metadata: metadata,
    },
    transport_eof: true,
    endpoint_complete: true,
    answer_complete: true,
  }
}

///|
// All handles are issued by ordinary Program preparation; only the physical
// I/O, ACK and decoder observations are deterministic doubles in these tests.
fn async_response_fixture(
  calls : Ref[Int],
  polls : Ref[Int],
  cancels : Ref[Int],
  cleanup_calls : Array[Bool],
  ready : Ref[Bool],
  release : Ref[Bool],
  observed : @model.ModelPhysicalCallPoll,
  limits? : Limits = standard_limits(),
  current? : Ref[@authorization.AdmittedAccountConfiguration] = Ref(
    evidence_account(@authorization.Allow),
  ),
  now? : Ref[String] = Ref("2026-10-02T00:00:00.000Z"),
  observe_call? : (@model.ModelPhysicalCall) -> Unit = _ => (),
  observe_response? : (() -> @model.ModelPhysicalCallPoll)? = None,
  observe_response_call? : ((Int, @model.ModelPhysicalCall) -> @model.ModelPhysicalCallPoll)? = None,
  prepare_original? : ((Execution) -> Unit)? = None,
  slots? : Int = 2,
  start_original? : (() -> Execution)? = None,
  capacity? : @model.ModelQuantityCapacity = fixture_quantity_capacity(
    66L, 1000L,
  ),
) -> (Execution, Int64) raise {
  let egress = Ref(Some(egress_fixture_observation()))
  let holder : Ref[@model.ModelPreparedCallSet?] = Ref(None)
  let (active, prepared, admission, work) = entry_gate_fixture(
    calls,
    current,
    now,
    egress,
    limits~,
    asynchronous=true,
    slots~,
    start_original~,
    configure=active => {
      bind_quantity_capacity(active, capacity).unwrap()
      if prepare_original is Some(prepare) {
        prepare(active)
      }
      bind_physical_preflight(active, request => {
        Ok({
          advance: () => {
            @model.model_async_physical_request_plan(
              request,
              1000L,
              capacity.per_attempt,
              async_response_profile(),
              async_response_installation(),
              entry => {
                let owned : Ref[@model.ModelPhysicalCall?] = Ref(None)
                let call = @model.model_physical_call(
                  entry,
                  holder.val.unwrap(),
                  () => {
                    polls.val += 1
                    if ready.val {
                      if observe_response_call is Some(read) {
                        return read(request.slot, owned.val.unwrap())
                      }
                      match observe_response {
                        Some(read) => read()
                        None => observed
                      }
                    } else {
                      @model.PhysicalPending
                    }
                  },
                  () => cancels.val += 1,
                  acknowledged => {
                    cleanup_calls.push(acknowledged)
                    release.val
                  },
                )
                owned.val = call
                if call is Some(original) {
                  calls.val += 1
                  observe_call(original)
                }
                call
              },
            ).map(value => Some(value))
          },
          cleanup: () => true,
        })
      }).unwrap()
    },
  )
  holder.val = Some(prepared)
  bind_model_dispatch(active, prepared, admission, _ => true).unwrap()
  (active, work)
}

///|
fn async_settlement_wire(active : Execution) -> String raise {
  let exporter = @model.start_model_call_settlement_export(
    call_settlement(active).unwrap(),
    capture_export_limits(),
  ).unwrap()
  let wire = StringBuilder()
  let mut done = false
  for _ in 0..<1000 {
    let (terminal, chunk, _) = @model.advance_model_capture_export(exporter, 1).unwrap()
    wire.write_string(chunk)
    if terminal {
      done = true
      break
    }
  }
  assert_true(done)
  assert_true(@model.cleanup_model_capture_export(exporter).unwrap())
  wire.to_string()
}

///|
fn async_assert_wait(active : Execution, expected_work : Int64) -> Unit raise {
  guard advance(active, 1).unwrap() is AwaitIo(work=actual) else {
    abort("physical polling must await I/O")
  }
  assert_eq(actual, expected_work)
}

///|
fn async_finish_quantum(
  active : Execution,
  quantum : Int,
  work : Int64,
) -> Poll raise {
  let mut last = work
  for _ in 0..<2000 {
    let poll = advance(active, quantum).unwrap()
    let total = match poll {
      Continue(work~)
      | AwaitIo(work~)
      | Waiting(work~)
      | Settling(_, work~)
      | Complete(_, work~)
      | Failed(_, work~)
      | Stopped(work~) => work
    }
    assert_true(total >= last && total - last <= quantum.to_int64())
    last = total
    if !(poll is Continue(_)) {
      return poll
    }
  }
  abort("independent finite async poll ceiling")
}

///|
test "original async call polls without work and retains nullable response until settlement cleanup" {
  for metadata_kind in ["null", "empty", "nonempty"] {
    let metadata = match metadata_kind {
      "null" => None
      "empty" => Some(@canonical.from_json(Json::object({}), 100, 10, 1000))
      _ =>
        Some(
          @canonical.from_json(
            Json::object({ "original": Json::string("é\r\n") }),
            100,
            10,
            1000,
          ),
        )
    }
    let calls = Ref(0)
    let polls = Ref(0)
    let cancels = Ref(0)
    let cleaned : Array[Bool] = []
    let ready = Ref(false)
    let release = Ref(false)
    let (active, prefix) = async_response_fixture(
      calls,
      polls,
      cancels,
      cleaned,
      ready,
      release,
      @model.PhysicalResponse(async_response_observation(metadata)),
    )
    guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
      abort("pending original")
    }
    assert_eq(calls.val, 1)
    for _ in 0..<3 {
      async_assert_wait(active, work)
    }
    assert_eq(calls.val, 1)
    assert_eq(cleaned.length(), 0)
    ready.val = true
    guard fixture_finish(active, initial_work=work) is Settling(0, work=settled) else {
      abort("original response settlement")
    }
    let wire = async_settlement_wire(active)
    assert_true(
      wire.contains("\"version\":\"actql-model-invocation-evidence/0.2\""),
    )
    assert_true(wire.contains("\"provider_request_id\":null"))
    assert_true(wire.contains("\"input_tokens\":null"))
    assert_true(wire.contains("\"finish_reason\":null"))
    let expected_metadata = match metadata_kind {
      "null" => "null"
      "empty" => "{}"
      _ => "{\"original\":\"é\\r\\n\"}"
    }
    assert_true(wire.contains("\"provider_metadata\":" + expected_metadata))
    let terminal_polls = polls.val
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_eq(cleaned.length(), 0)
    async_assert_wait(active, settled)
    assert_eq(cleaned, [true])
    assert_eq(polls.val, terminal_polls)
    assert_eq(calls.val, 1)
    release.val = true
    ready.val = false
    guard fixture_finish(active, initial_work=settled) is AwaitIo(work=second) else {
      abort("second pending original")
    }
    assert_eq(calls.val, 2)
    ready.val = true
    guard fixture_finish(active, initial_work=second) is Settling(1, work=last) else {
      abort("second settlement")
    }
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_true(fixture_finish(active, initial_work=last) is Complete(_, ..))
    assert_eq(cancels.val, 0)
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 2)
  }
}

///|
test "async unknown keeps partial usage and original cleanup retry without another call" {
  let calls = Ref(0)
  let polls = Ref(0)
  let cancels = Ref(0)
  let cleaned : Array[Bool] = []
  let ready = Ref(false)
  let release = Ref(false)
  let (active, prefix) = async_response_fixture(
    calls,
    polls,
    cancels,
    cleaned,
    ready,
    release,
    @model.PhysicalUnknown({ input_tokens: Some(7L), output_tokens: None, }),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("pending original")
  }
  assert_true(cancel(active))
  async_assert_wait(active, work)
  assert_eq(cancels.val, 1)
  ready.val = true
  assert_true(
    fixture_finish(active, initial_work=work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  let model = active.model.unwrap()
  assert_eq(@model.stopped_model_attempt_count(model), Some(1))
  let before = @model.model_execution_resource_usage(model)
  let evidence = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let accounting = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(evidence),
  )
  assert_true(accounting.contains("\"input_tokens\":7"))
  assert_true(accounting.contains("\"output_tokens\":null"))
  assert_true(before.reserved_retention_bytes > 0L)
  assert_true(!cleanup(active).unwrap())
  assert_eq(cleaned, [false])
  assert_true(acquire_output(active) is None)
  assert_true(acquire_capture(active) is None)
  release.val = true
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
  assert_eq(cancels.val, 1)
  assert_eq(cleaned, [false, false])
  assert_eq(
    @model.model_execution_resource_usage(model).reserved_retention_bytes,
    0L,
  )
}

///|
test "async cancellation retains a late response for original settlement without public output" {
  let calls = Ref(0)
  let ready = Ref(false)
  let release = Ref(false)
  let cancels = Ref(0)
  let cleaned : Array[Bool] = []
  let physical = async_response_observation(None)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    cancels,
    cleaned,
    ready,
    release,
    @model.PhysicalResponse({
      ..physical,
      observation: {
        ..physical.observation,
        input_tokens: Some(3L),
        output_tokens: Some(2L),
      },
    }),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("pending original")
  }
  assert_true(cancel(active))
  async_assert_wait(active, work)
  ready.val = true
  guard fixture_finish(active, initial_work=work) is Settling(0, work=settled) else {
    abort("late response must be saved before reclamation")
  }
  assert_eq(cancels.val, 1)
  let wire = async_settlement_wire(active)
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_true(acquire_output(active) is None)
  assert_true(acquire_capture(active) is None)
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  async_assert_wait(active, settled)
  release.val = true
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(_))
  assert_eq(calls.val, 1)
  let model = active.model.unwrap()
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(cancels.val, 1)
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
}

///|
test "async response requires original completion output contract and finite opaque metadata" {
  for
    variant in [
      "eof", "envelope", "answer", "profile", "origin", "shape", "metadata",
    ] {
    let original = async_response_observation(None)
    let physical = match variant {
      "eof" => { ..original, transport_eof: false, }
      "envelope" => { ..original, endpoint_complete: false, }
      "answer" => { ..original, answer_complete: false, }
      "profile" =>
        {
          ..original,
          observation: {
            ..original.observation,
            response_profile_cid: Some("sha256:" + "9".repeat(64)),
          },
        }
      "origin" =>
        {
          ..original,
          observation: {
            ..original.observation,
            origin: @publication.HistoricalAdmitted,
          },
        }
      "shape" =>
        {
          ..original,
          value: @admitted.text_value("not an output object", 100).unwrap(),
        }
      _ =>
        {
          ..original,
          observation: {
            ..original.observation,
            provider_metadata: Some(
              @canonical.from_json(
                Json::object({ "opaque": Json::string("x".repeat(129)) }),
                100,
                10,
                1000,
              ),
            ),
          },
        }
    }
    let calls = Ref(0)
    let cleaned : Array[Bool] = []
    let (active, prefix) = async_response_fixture(
      calls,
      Ref(0),
      Ref(0),
      cleaned,
      Ref(true),
      Ref(true),
      @model.PhysicalResponse(physical),
    )
    let result = fixture_finish(active, initial_work=prefix)
    if variant == "shape" {
      assert_true(result is Failed(Model(@model.OutputValue), ..))
    } else {
      assert_true(result is Failed(Model(@model.OutputIdentity), ..))
    }
    assert_eq(calls.val, 1)
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(cleaned, [false])
  }
}

///|
test "async metadata cursor has quantum independent response and logical work" {
  let totals : Array[Int64] = []
  for quantum in [1, 7] {
    let metadata = @canonical.from_json(
      Json::object({ "original": Json::string("é\r\n") }),
      100,
      10,
      1000,
    )
    let calls = Ref(0)
    let (active, prefix) = async_response_fixture(
      calls,
      Ref(0),
      Ref(0),
      [],
      Ref(true),
      Ref(true),
      @model.PhysicalResponse(async_response_observation(Some(metadata))),
    )
    let mut work = prefix
    for slot in 0..<2 {
      guard async_finish_quantum(active, quantum, work)
        is Settling(actual, work=total) else {
        abort("same original settlement")
      }
      assert_eq(actual, slot)
      work = total
      let wire = async_settlement_wire(active)
      assert_true(
        wire.contains(
          "\"structured_response\":{\"reason\":null,\"risk\":\"high\"}",
        ),
      )
      assert_true(
        @model.acknowledge_model_call_settlement(
          call_settlement(active).unwrap(),
        ),
      )
    }
    guard async_finish_quantum(active, quantum, work)
      is Complete(output, work=total) else {
      abort("same completed output")
    }
    assert_eq(@relation.completed_row_count(output), 2)
    assert_true(
      @relation.completed_cell(output, 0, 0) is Some(@relation.Text("a")),
    )
    assert_true(
      @relation.completed_cell(output, 1, 0) is Some(@relation.Text("b")),
    )
    totals.push(total)
    assert_eq(calls.val, 2)
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
  }
  assert_eq(totals[0], totals[1])
}

///|
test "async final diagnostic cancellation dispatches no physical request" {
  let calls = Ref(0)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    [],
    Ref(true),
    Ref(true),
    @model.PhysicalResponse(async_response_observation(None)),
  )
  let prepared = prepared_call_set(active).unwrap()
  let events : Array[String] = []
  assert_true(
    @model.bind_prepared_model_observation(prepared, observation => {
      let (_, _, event, _) = @model.model_physical_observation_facts(
        observation,
      )
      events.push(event)
      if event == "before_invoke" {
        cancel(active) |> ignore
      }
    }),
  )
  assert_true(fixture_finish(active, initial_work=prefix) is Stopped(_))
  assert_eq(calls.val, 0)
  assert_eq(events, ["before_invoke"])
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "stopped async kernel cannot freeze accounting before original physical usage arrives" {
  let calls = Ref(0)
  let ready = Ref(false)
  let release = Ref(false)
  let response = async_response_observation(None)
  let physical = @model.PhysicalResponse({
    ..response,
    observation: {
      ..response.observation,
      input_tokens: Some(3L),
      output_tokens: Some(2L),
    },
  })
  let (reference, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    [],
    ready,
    Ref(true),
    physical,
  )
  guard fixture_finish(reference, initial_work=prefix) is AwaitIo(work=waiting) else {
    abort("reference original pending")
  }
  // Calibrate only the existing kernel stop location, not expected accounting
  // or a public capacity formula. Both attempts use ordinary preparation.
  guard @model.advance_model_execution(reference.model.unwrap(), 1).unwrap()
    is @model.AwaitIo(_, model_work) else {
    abort("original pending work")
  }
  assert_true(cancel(reference))
  ready.val = true
  guard fixture_finish(reference, initial_work=waiting) is Settling(_, work~) else {
    abort("drain reference")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(
      call_settlement(reference).unwrap(),
    ),
  )
  assert_true(fixture_finish(reference, initial_work=work) is Stopped(_))
  assert_true(!cleanup(reference).unwrap())
  assert_true(cleanup(reference).unwrap())
  let base = standard_limits()
  let limits = {
    ..base,
    model: { ..base.model, max_work: model_work.to_int(), },
  }
  let limited_calls = Ref(0)
  ready.val = false
  let (active, start) = async_response_fixture(
    limited_calls,
    Ref(0),
    Ref(0),
    [],
    ready,
    release,
    physical,
    limits~,
  )
  guard fixture_finish(active, initial_work=start) is AwaitIo(work=waiting) else {
    abort("limited original pending")
  }
  ready.val = true
  assert_true(
    fixture_finish(active, initial_work=waiting)
    is Failed(Model(@model.WorkLimit), ..),
  )
  let model = active.model.unwrap()
  assert_true(
    @model.model_execution_attempt_evidence(model, 0)
    is Err(@model.OutputIdentity),
  )
  assert_true(!cleanup(active).unwrap())
  let evidence = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(evidence),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  release.val = true
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
  assert_eq(limited_calls.val, 1)
}
