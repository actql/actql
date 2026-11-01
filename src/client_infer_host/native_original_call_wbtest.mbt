///|
// Actual checked Program, Model, Entry and nominal raw receipt. Transport,
// persisted ACK/clock/Store availability and installation are explicit doubles;
// this is not normal numerical funding or a public/live native Provider.
struct NativeOriginalCallFixture {
  active : Execution
  prepared : @model.ModelPreparedCallSet
  registration : @publication_host.ClientModelRawCaptureRegistration
  provider : @model.AdmittedModelProvider
  views : Map[Int, @model.NativeDecisionRequest]
  calls : Map[Int, @model.ModelPhysicalCall]
  responses : Map[Int, @model.ModelPhysicalCallPoll]
  current : Ref[@authorization.AdmittedAccountConfiguration]
  now : Ref[String]
  release : Ref[Bool]
  sent : Ref[Int]
  work : Int64
}

///|
fn native_original_finish(
  active : Execution,
  initial_work : Int64,
) -> Poll raise {
  let mut last = initial_work
  // A separate finite native fixture selection, still below the original
  // Model max_work=10000. No production or prior fixture limit is changed.
  for _ in 0..<10000 {
    let poll = advance(active, 1).unwrap()
    let work = match poll {
      Continue(work~)
      | AwaitIo(work~)
      | Waiting(work~)
      | Settling(_, work~)
      | Complete(_, work~)
      | Failed(_, work~)
      | Stopped(work~) => work
    }
    assert_true(work >= last && work - last <= 1L)
    last = work
    if !(poll is Continue(_)) {
      return poll
    }
  }
  abort("native fixture did not reach original bounded terminal")
}

///|
fn native_call_profile() -> @environment.ModelResponseProfile {
  @environment.read_model_response_profile(
    @utf8.encode(native_call_profile_wire),
    native_call_profile_cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
}

///|
fn native_original_call_start() -> Execution {
  native_original_call_start_with(
    @model.install_async_model_provider("models/fixture").unwrap(),
  )
}

///|
fn native_original_call_start_with(
  provider : @model.ModelProvider,
) -> Execution {
  let env = @publication_host.admit_client_check_environment(
    native_call_environment,
    native_call_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    native_call_program,
    Json,
    env,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    2,
    @utf8.encode(native_call_execution),
    native_call_execution_cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  let plan = @publication_host.issue_prepared_client_infer_plan_graph(
    prepared,
    2,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  start(
    prepared,
    2,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(plan),
    standard_limits(),
    plan=Some(plan),
  ).unwrap()
}

///|
fn native_original_call_fixture() -> NativeOriginalCallFixture raise {
  let sent = Ref(0)
  let current = Ref(
    evidence_account(@authorization.Allow, operations=[
      "infer", "model_raw_capture",
    ]),
  )
  let now = Ref("2026-10-02T00:00:00.000Z")
  let holder : Ref[@model.ModelPreparedCallSet?] = Ref(None)
  let admitted : Ref[@model.AdmittedModelProvider?] = Ref(None)
  let views : Map[Int, @model.NativeDecisionRequest] = Map([])
  let calls : Map[Int, @model.ModelPhysicalCall] = Map([])
  let responses : Map[Int, @model.ModelPhysicalCallPoll] = Map([])
  let release = Ref(false)
  let (active, prepared, admission, work) = entry_gate_fixture(
    sent,
    current,
    now,
    Ref(Some({ ..egress_fixture_observation(), region: "fixture", })),
    start_original=Some(native_original_call_start),
    configure=active => {
      let execution = @publication_host.client_infer_plan_graph_execution_contract(
        active.plan.unwrap(),
      )
      let deps = @environment.read_single_attempt_model_dependencies(
        execution,
        Some(@utf8.encode(native_call_prompt)),
        Some(@utf8.encode(native_call_retry)),
        Some(@utf8.encode(native_call_backoff)),
        {
          max_bytes: 100000,
          max_nodes: 10000,
          max_depth: 100,
          max_members: 10,
        },
        1000000,
      ).unwrap()
      guard active.source is Physical(installed) else {
        abort("original async provider")
      }
      let provider = @model.admit_model_provider(installed, execution, deps, (
        _,
        _,
      ) => true).unwrap()
      admitted.val = Some(provider)
      bind_quantity_capacity(active, {
        limits: { tokens: 256L, cost_units: 0L, duration_ms: 1000L, },
        per_attempt: { tokens: 128L, cost_units: 0L, duration_ms: 500L, },
      }).unwrap()
      bind_physical_preflight(active, request => {
        let projection = @model.start_native_decision_projection(
          provider, request, 10000, 1000, 40, 100, 10000,
        ).unwrap()
        let original = Ref(None)
        Ok({
          advance: () => {
            if original.val is None {
              match @model.advance_native_decision_projection(projection) {
                Ok(None) => return Ok(None)
                Ok(Some(view)) => {
                  original.val = Some(view)
                  views[request.slot] = view
                  @model.retire_native_decision_projection(projection)
                }
                Err(_) => return Err(@model.InvalidProvider)
              }
            }
            @model.model_async_native_decision_request_plan(
              request,
              original.val.unwrap(),
              provider,
              1000L,
              { tokens: 128L, cost_units: 0L, duration_ms: 500L, },
              native_call_profile(),
              native_call_installation(),
              @environment.initial_jev_decision_profile(),
              entry => {
                let call = @model.model_physical_call(
                  entry,
                  holder.val.unwrap(),
                  () => {
                    responses
                    .get(request.slot)
                    .unwrap_or(@model.PhysicalPending)
                  },
                  () => (),
                  _ => release.val,
                )
                if call is Some(value) {
                  calls[request.slot] = value
                  sent.val += 1
                }
                call
              },
            ).map(plan => Some(plan))
          },
          cleanup: () => {
            @model.retire_native_decision_projection(projection)
            if original.val is Some(view) {
              @model.retire_native_decision_request(view)
            }
            original.val = None
            true
          },
        })
      }).unwrap()
    },
  )
  holder.val = Some(prepared)
  let provider = admitted.val.unwrap()
  let registration = @publication_host.register_client_model_raw_capture(
    admission,
    @model.prepared_model_scope(prepared).unwrap(),
    raw_registration_policy(
      active,
      prepared,
      response_profile=native_call_profile(),
    ),
    native_call_profile(),
    native_call_installation(),
    Some(@environment.initial_jev_decision_profile()),
    current.val,
    now.val,
    "sha256:" + "e".repeat(64),
    () => true,
    () => Ok((current.val, now.val)),
  ).unwrap()
  bind_model_dispatch(active, prepared, admission, _ => true).unwrap()
  let work = match fixture_finish(active, initial_work=work) {
    AwaitIo(work~) => work
    _ => abort("native original must await its actual entered call")
  }
  assert_eq(sent.val, 1)
  assert_eq(views.length(), 2)
  {
    active,
    prepared,
    registration,
    provider,
    views,
    calls,
    responses,
    current,
    now,
    release,
    sent,
    work,
  }
}

///|
fn native_original_saved_response(
  fixture : NativeOriginalCallFixture,
  slot : Int,
  body : String,
  eof? : Bool = true,
) -> @model.ModelPhysicalChatResponse {
  let bytes = @utf8.encode(body)
  let save = @model.observe_model_raw_capture(
    fixture.calls.get(slot).unwrap(),
    fixture.registration,
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
    200,
    eof,
    fixture.now.val,
  ).unwrap()
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  @model.model_saved_raw_chat_response(receipt, body, None).unwrap()
}

///|
fn native_original_answer() -> String {
  // Independent aliases/values with 0.99 rounding, an actual tie and a
  // fractional score. Unknown data is not part of the typed answer.
  "{\"usage\":{\"input_tokens\":3,\"output_tokens\":2},\"answers\":{\"q0000000000\":{\"type\":\"choice\",\"choice\":\"o0000000001\",\"probabilities\":{\"o0000000000\":0.33,\"o0000000001\":0.33,\"o0000000002\":0.33}},\"q0000000001\":{\"type\":\"score\",\"score\":1.5,\"probabilities\":{\"0\":0,\"1\":0.5,\"2\":0.5}},\"q0000000002\":{\"type\":\"noul\",\"noul\":0.25}},\"opaque\":{\"text\":\"é\\r\\n\"}}"
}

///|
test "native original Entry and saved raw advance existing Model to typed result without another send" {
  let f = native_original_call_fixture()
  let mut work = f.work
  for slot in 0..<2 {
    let raw = native_original_saved_response(f, slot, native_original_answer())
    f.responses[slot] = @model.model_physical_saved_native_response(
      raw,
      f.views.get(slot).unwrap(),
      f.provider,
      @environment.initial_jev_decision_profile(),
    ).unwrap()
    guard native_original_finish(f.active, work) is Settling(actual, work=next) else {
      abort("native answer must reach original settlement")
    }
    assert_eq(actual, slot)
    assert_true(
      @model.acknowledge_model_call_settlement(
        call_settlement(f.active).unwrap(),
      ),
    )
    assert_true(native_original_finish(f.active, next) is AwaitIo(..))
    f.release.val = true
    let poll = native_original_finish(f.active, next)
    if slot == 0 {
      guard poll is AwaitIo(work=awaited) else {
        abort("second original slot must await")
      }
      work = awaited
      f.release.val = false
    } else {
      assert_true(poll is Complete(_, ..))
    }
  }
  assert_eq(f.sent.val, 2)
  assert_eq(
    @model.model_execution_quantity_usage(f.active.model.unwrap()).consumed.tokens,
    10L,
  )
  let output = acquire_output(f.active).unwrap()
  let result = output.output
  assert_eq(@relation.completed_row_count(result), 2)
  assert_eq(@relation.completed_column_count(result), 3)
  // Normative INFER canonical key order, not authored Values arrival order.
  for (row, key) in [(0, "a"), (1, "b")] {
    assert_true(
      @relation.completed_cell(result, row, 0) is Some(@relation.Text(actual)) &&
      actual == key,
    )
    assert_true(
      @relation.completed_cell(result, row, 1) is Some(@relation.Text("ok")),
    )
    let wire = @relation.completed_output_row_wire(result, row, 4096, 256, 20).unwrap()
    assert_true(wire.contains("\"choice\":\"__proto__\""))
    assert_true(wire.contains("\"score\":1.5"))
    assert_true(wire.contains("\"probability\":0.25"))
  }
  let capture_wire = @model.model_capture_bundle_json(
    capture(f.active).unwrap(),
    16384,
    1000,
    40,
  ).unwrap()
  assert_true(capture_wire.contains("\"provider_model\":null"))
  assert_true(capture_wire.contains("\"provider_request_id\":null"))
  assert_true(capture_wire.contains("\"input_tokens\":3"))
  assert_true(capture_wire.contains("\"output_tokens\":2"))
  assert_eq(@model.prepared_model_call_count(f.prepared), Some(2))
  assert_true(!cleanup(f.active).unwrap())
  assert_true(release_output(output))
  // Each cleanup call retires at most one of the two original preflight
  // cursors. A terminal Result is not immediate retirement of both borrows.
  assert_true(!cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_eq(f.sent.val, 2)
}

///|
test "native original synchronous fixture rejects and async missing prerequisites remain pre-Entry" {
  let sent = Ref(0)
  let sync = native_original_call_start_with(
    @model.install_model_provider("models/fixture", _ => {
      sent.val += 1
      Err(@model.Timeout)
    }).unwrap(),
  )
  invocation_fixture_compiled(sync) |> ignore
  assert_true(fixture_finish(sync) is Failed(Model(@model.InvalidProvider), ..))
  assert_true(sync.model is None)
  assert_true(cleanup(sync).unwrap())
  for missing in 0..<3 {
    let active = native_original_call_start()
    invocation_fixture_compiled(active) |> ignore
    if missing != 0 {
      require_model_call_entry(active).unwrap()
    }
    if missing != 1 {
      bind_physical_preflight(active, _ => {
        sent.val += 1
        Err(@model.InvalidProvider)
      }).unwrap()
    }
    if missing != 2 {
      bind_quantity_capacity(active, {
        limits: { tokens: 256L, cost_units: 0L, duration_ms: 1000L, },
        per_attempt: { tokens: 128L, cost_units: 0L, duration_ms: 500L, },
      }).unwrap()
    }
    let terminal = fixture_finish(active)
    if missing == 2 {
      assert_true(terminal is Failed(Model(@model.InvalidLimits), ..))
    } else {
      assert_true(terminal is Failed(Model(@model.InvalidProvider), ..))
    }
    assert_true(active.model is None)
    assert_true(acquire_output(active) is None)
    assert_true(cleanup(active).unwrap())
  }
  assert_eq(sent.val, 0)
}

///|
test "native original nominal raw refuses foreign scope provider slot and retired request" {
  let f = native_original_call_fixture()
  let g = native_original_call_fixture()
  let raw = native_original_saved_response(f, 0, native_original_answer())
  for
    (view, provider) in [
      (g.views.get(0).unwrap(), f.provider),
      (f.views.get(0).unwrap(), g.provider),
      (f.views.get(1).unwrap(), f.provider),
    ] {
    assert_true(
      @model.model_physical_saved_native_response(
        raw,
        view,
        provider,
        @environment.initial_jev_decision_profile(),
      )
      is Err(@model.RequestIdentity),
    )
  }
  @model.retire_native_decision_request(f.views.get(0).unwrap())
  assert_true(
    @model.model_physical_saved_native_response(
      raw,
      f.views.get(0).unwrap(),
      f.provider,
      @environment.initial_jev_decision_profile(),
    )
    is Err(@model.RequestIdentity),
  )
  for fixture in [f, g] {
    assert_true(cancel(fixture.active))
    fixture.responses[0] = @model.PhysicalUnknown({
      input_tokens: None,
      output_tokens: None,
    })
    let terminal = native_original_finish(fixture.active, fixture.work)
    // An entered response-loss observation stays Unknown even when cancelled;
    // the factory's retired-view refusal is not evidence of an unsent attempt.
    assert_true(terminal is Failed(Model(@model.UnknownCalls), ..))
    assert_true(!cleanup(fixture.active).unwrap())
    fixture.release.val = true
    assert_true(!cleanup(fixture.active).unwrap())
    assert_true(cleanup(fixture.active).unwrap())
    assert_eq(fixture.sent.val, 1)
  }
}

///|
test "native original cancellation and authority loss preserve entered cleanup without second send" {
  for cancelled in [false, true] {
    let f = native_original_call_fixture()
    if cancelled {
      assert_true(cancel(f.active))
    } else {
      f.current.val = evidence_account(@authorization.Deny)
    }
    f.responses[0] = @model.PhysicalUnknown({
      input_tokens: None,
      output_tokens: None,
    })
    let terminal = native_original_finish(f.active, f.work)
    assert_true(terminal is Failed(Model(@model.UnknownCalls), ..))
    assert_true(acquire_output(f.active) is None)
    assert_true(!cleanup(f.active).unwrap())
    f.release.val = true
    assert_true(!cleanup(f.active).unwrap())
    assert_true(cleanup(f.active).unwrap())
    assert_eq(f.sent.val, 1)
    assert_true(cleanup(f.active).unwrap())
  }
}

///|
test "native original incomplete raw usage retires before immutable Unknown attempt proof" {
  let f = native_original_call_fixture()
  let raw = native_original_saved_response(
    f,
    0,
    native_original_answer(),
    eof=false,
  )
  let call = f.calls.get(0).unwrap()
  f.responses[0] = @model.model_physical_saved_native_response(
    raw,
    f.views.get(0).unwrap(),
    f.provider,
    @environment.initial_jev_decision_profile(),
  ).unwrap()
  assert_true(
    native_original_finish(f.active, f.work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(attempt_evidence(f.active, 0) is Err(@model.OutputIdentity))
  let model = f.active.model.unwrap()
  let mut last = 0L
  let mut completed = false
  for _ in 0..<10000 {
    let (done, work) = @model.advance_model_reconciled_raw_usage(call, raw, 1).unwrap()
    assert_true(work >= last && work - last <= 1L)
    last = work
    if done {
      completed = true
      break
    }
  }
  assert_true(completed)
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  assert_eq(f.sent.val, 1)
  assert_true(acquire_output(f.active) is None)
  // Reader retirement enables the original failure/Unknown proof, not a
  // response success, a new immutable attempt or permission to resend.
  let proof = attempt_evidence(f.active, 0).unwrap()
  let accounting = @model.model_attempt_accounting(proof)
  let wire = @publication.run_evidence_value_json(accounting)
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_true(
    @publication.run_evidence_value_json(@model.model_attempt_outcome(proof)).contains(
      "\"category\":\"result_unknown\"",
    ),
  )
  assert_eq(
    @model.advance_model_reconciled_raw_usage(call, raw, 1).unwrap(),
    (true, last),
  )
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  assert_eq(
    @publication.run_evidence_value_identity(
      @model.model_attempt_accounting(attempt_evidence(f.active, 0).unwrap()),
    ),
    @publication.run_evidence_value_identity(accounting),
  )
  assert_true(!cleanup(f.active).unwrap())
  f.release.val = true
  assert_true(!cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_eq(f.sent.val, 1)
}

///|
test "native original incomplete nullable usage retains reservation and immutable Unknown proof" {
  let f = native_original_call_fixture()
  let body = native_original_answer().replace(
    old="\"input_tokens\":3,\"output_tokens\":2",
    new="\"input_tokens\":3",
  )
  let raw = native_original_saved_response(f, 0, body, eof=false)
  let call = f.calls.get(0).unwrap()
  f.responses[0] = @model.model_physical_saved_native_response(
    raw,
    f.views.get(0).unwrap(),
    f.provider,
    @environment.initial_jev_decision_profile(),
  ).unwrap()
  assert_true(
    native_original_finish(f.active, f.work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  let model = f.active.model.unwrap()
  let before = @model.model_execution_quantity_usage(model)
  let mut done = false
  let mut last = 0L
  for _ in 0..<10000 {
    let (completed, work) = @model.advance_model_reconciled_raw_usage(
      call, raw, 1,
    ).unwrap()
    assert_true(work >= last && work - last <= 1L)
    last = work
    if completed {
      done = true
      break
    }
  }
  assert_true(done)
  let usage = @model.model_execution_quantity_usage(model)
  // This is the Ledger's settled counter, not a report of zero output usage.
  assert_eq(usage.consumed.tokens, before.consumed.tokens)
  assert_eq(usage.reserved.tokens, before.reserved.tokens)
  let proof = attempt_evidence(f.active, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(proof),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":null"))
  assert_true(
    @publication.run_evidence_value_json(@model.model_attempt_outcome(proof)).contains(
      "\"category\":\"result_unknown\"",
    ),
  )
  assert_eq(
    @model.advance_model_reconciled_raw_usage(call, raw, 7).unwrap(),
    (true, last),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      @model.model_attempt_accounting(attempt_evidence(f.active, 0).unwrap()),
    ),
    wire,
  )
  assert_true(acquire_output(f.active) is None)
  assert_true(!cleanup(f.active).unwrap())
  f.release.val = true
  assert_true(!cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_eq(f.sent.val, 1)
}
