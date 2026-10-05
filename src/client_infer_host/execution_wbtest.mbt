///|
fn fixture_prepared(
  source? : String = infer_fixture_program,
  host_items? : Int = 1000,
  environment_wire? : String = infer_fixture_environment,
) -> @publication_host.PreparedClientProgram {
  let unsigned = environment_wire
    .replace(
      old="\"evidence_bundle_cid\":\"" + infer_fixture_environment_cid + "\",",
      new="",
    )
    .replace(
      old="\"max_infer_items\":1000",
      new="\"max_infer_items\":" + host_items.to_string(),
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let wire = unsigned.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    source,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "actual Host and author item ceilings reject dispatch without losing custody" {
  let two = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  for
    prepared in [
      fixture_prepared(source=two, host_items=1),
      fixture_prepared(
        source=two.replace(
          old="\"key\":\"id\",\"input\":",
          new="\"key\":\"id\",\"max_items\":1,\"input\":",
        ),
      ),
    ] {
    let calls = Ref(0)
    let active = fixture_start(prepared, () => calls.val += 1)
    assert_true(fixture_finish(active) is Failed(Model(@model.ItemLimit), ..))
    assert_true(acquire_output(active) is None)
    assert_eq(calls.val, 0)
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
  }
  // Independently chosen exact boundary: two admitted keys, two item slots.
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(source=two, host_items=2), () => {
    calls.val += 1
  })
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
}

///|
fn fixture_start(
  prepared : @publication_host.PreparedClientProgram,
  on_invoke : () -> Unit,
  limits? : Limits = standard_limits(),
) -> Execution {
  let provider = @model.install_model_provider("models/fixture", _request => {
    on_invoke()
    let value = @admitted.object_value([
      ("reason", @admitted.null_value()),
      ("risk", @admitted.text_value("high", 100).unwrap()),
    ]).unwrap()
    Ok({
      value,
      provider_model: "fixture-risk-model",
      provider_request_id: "request-1",
      input_tokens: 1L,
      output_tokens: 2L,
      observed_at: "2026-10-01T00:00:00.000Z",
    })
  }).unwrap()
  start(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    "sha256:" + "1".repeat(64),
    limits,
  ).unwrap()
}

///|
fn fixture_finish(active : Execution, initial_work? : Int64 = 0L) -> Poll raise {
  let mut last = initial_work
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    let work = match poll {
      Waiting(work~)
      | Settling(_, work~)
      | Continue(work~)
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
  abort("bounded fixture exceeded its independent finite poll ceiling")
}

///|
test "normal Program input dispatch and output share one bounded owner" {
  let calls = Ref(0)
  let prepared = fixture_prepared()
  let active = fixture_start(prepared, () => calls.val += 1)
  assert_eq(calls.val, 0)
  assert_true(matches(active, prepared))
  assert_true(!matches(active, fixture_prepared()))
  assert_true(!cleanup(active).unwrap())
  let poll = fixture_finish(active)
  guard poll is Complete(completed, ..) else { abort("successful fixture") }
  assert_eq(calls.val, 1)
  assert_eq(@relation.completed_row_count(completed), 1)
  assert_eq(@relation.completed_column_count(completed), 3)
  assert_eq(@relation.completed_column_name(completed, 0), Some("id"))
  assert_eq(@relation.completed_column_name(completed, 1), Some("outcome"))
  assert_eq(@relation.completed_column_name(completed, 2), Some("value"))
  assert_true(
    @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(completed, 0, 1) is Some(@relation.Text("ok")),
  )
  let a = acquire_output(active).unwrap()
  let b = acquire_output(active).unwrap()
  assert_true(!cleanup(active).unwrap())
  assert_true(release_output(a))
  assert_true(!release_output(a))
  assert_true(output(a) is None)
  assert_true(output(b) is Some(_))
  assert_true(!cleanup(active).unwrap())
  assert_true(release_output(b))
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "Infer cancellation at the last yield cannot hand out completed output" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  for _ in 0..<2000 {
    if handoff_pending(active) {
      break
    }
    assert_true(advance(active, 1).unwrap() is Continue(_))
  }
  assert_true(handoff_pending(active))
  assert_true(!cleanup(active).unwrap())
  assert_true(!execution_stopped(active))
  assert_true(cancel(active))
  assert_true(!execution_stopped(active))
  let stopped = advance(active, 1).unwrap()
  assert_eq(poll_kind(stopped), "stopped")
  assert_true(poll_issue(stopped) is None)
  assert_true(execution_stopped(active))
  assert_true(acquire_output(active) is None)
  assert_true(capture(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "prefix cancellation makes no model call and retains cleanup custody" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  assert_true(advance(active, 1).unwrap() is Continue(_))
  assert_true(cancel(active))
  assert_true(!cleanup(active).unwrap())
  assert_true(fixture_finish(active) is Stopped(_))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}

///|
test "model response admission charges exact steps and retains provider observations" {
  // One reservation, eight request transitions, one dispatch, and eight
  // response transitions: root, child selections/checks, one TextUnits
  // poll for "high", and cursor ends. Total physical work is 18.
  let limits = standard_limits()
  let exact = { ..limits, model: { ..limits.model, max_work: 18, }, }
  let calls = Ref(0)
  let active = fixture_start(
    fixture_prepared(),
    () => calls.val += 1,
    limits=exact,
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  let captured = capture(active).unwrap().captures[0]
  assert_eq(captured.provider_model, "fixture-risk-model")
  assert_eq(captured.input_tokens, 1L)
  assert_eq(captured.output_tokens, 2L)
  assert_eq(captured.observed_at, "2026-10-01T00:00:00.000Z")
  assert_eq(calls.val, 1)
  assert_true(cleanup(active).unwrap())
  let short_calls = Ref(0)
  let short = fixture_start(fixture_prepared(), () => short_calls.val += 1, limits={
    ..exact,
    model: { ..exact.model, max_work: 17, },
  })
  assert_true(fixture_finish(short) is Failed(Model(@model.WorkLimit), ..))
  assert_true(capture(short) is None)
  assert_true(acquire_output(short) is None)
  assert_true(cleanup(short).unwrap())
  assert_true(cleanup(short).unwrap())
  assert_eq(short_calls.val, 1)
}

///|
fn fixture_canonical(value : Json) -> String raise {
  @canonical.stringify_value(
    @canonical.from_json(value, 10000, 64, 100000),
    100000,
    10000,
    64,
  )
}

///|
fn fixture_array_prepared() -> @publication_host.PreparedClientProgram raise {
  let wire = @json.parse(infer_fixture_environment)
  guard wire is Object(environment) &&
    environment["model_task_contracts"] is Array([task]) &&
    task is Object(fields) &&
    fields["output_contract"] is Object(contract) &&
    contract["fields"] is Object(output_fields) else {
    abort("ordinary ModelTask admission fixture")
  }
  let risk =
    #|{"items":{"nullable":false,"type":"number"},"max_items":4096,"nullable":false,"type":"array"}
  output_fields["risk"] = @json.parse(risk)
  fields["output_schema_cid"] = Json::string(
    "sha256:" +
    @sha.hex(@utf8.encode(fixture_canonical(fields["output_contract"]))),
  )
  fields.remove("contract_cid") |> ignore
  fields["contract_cid"] = Json::string(
    "sha256:" + @sha.hex(@utf8.encode(fixture_canonical(task))),
  )
  environment.remove("evidence_bundle_cid") |> ignore
  fixture_prepared(environment_wire=fixture_canonical(wire))
}

///|
fn fixture_array_start(
  count : Int,
  calls : Ref[Int],
  limits : Limits,
) -> Execution raise {
  let value = @admitted.object_value([
    ("reason", @admitted.null_value()),
    (
      "risk",
      @admitted.array_value(
        Array::makei(count, index => {
          @admitted.number_value(index.to_double()).unwrap()
        }),
      ),
    ),
  ]).unwrap()
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Ok({
      value,
      provider_model: "fixture-array-model",
      provider_request_id: "array-response-1",
      input_tokens: 1L,
      output_tokens: count.to_int64(),
      observed_at: "2026-10-01T00:00:00.000Z",
    })
  }).unwrap()
  start(
    fixture_array_prepared(),
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    "sha256:" + "1".repeat(64),
    limits,
  ).unwrap()
}

///|
test "large model response can stop between child values without a second dispatch" {
  let calls = Ref(0)
  let active = fixture_array_start(4096, calls, standard_limits())
  for _ in 0..<2000 {
    assert_true(advance(active, 1).unwrap() is Continue(_))
    if calls.val == 1 {
      break
    }
  }
  assert_eq(calls.val, 1)
  // The provider has returned; the following polls must validate children,
  // not declare the entire 4096-element response accepted in one step.
  for _ in 0..<64 {
    assert_true(advance(active, 1).unwrap() is Continue(_))
    assert_true(active.capture is None)
  }
  assert_true(!cleanup(active).unwrap())
  assert_true(!@input.cleanup_client_infer_input(active.input).unwrap())
  assert_true(cancel(active))
  assert_true(advance(active, 1).unwrap() is Stopped(_))
  let model = active.model.unwrap()
  let before = @model.model_execution_resource_usage(model)
  assert_eq(before.attempts, 1)
  // The actual Host caps the request at 1000 bytes; the response at 65536.
  assert_eq(before.reserved_retention_bytes, 66536L)
  assert_true(acquire_output(active) is None)
  assert_true(capture(active) is None)
  assert_true(!@input.cleanup_client_infer_input(active.input).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  let after = @model.model_execution_resource_usage(model)
  assert_eq(after.reserved_transfer_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.attempts, 1)
  assert_eq(calls.val, 1)
}

///|
test "model response has independent exact and one-short node boundaries" {
  let n = 16
  let base = standard_limits()
  // Object, NULL, array and n number occurrences; two container cursors
  // and their child selections plus request preflight determine 2*n + 18.
  let exact = {
    ..base,
    model: {
      ..base.model,
      max_work: 2 * n + 18,
      value_limits: { max_nodes: n + 3, max_depth: 8, max_text_bytes: 10, },
    },
  }
  let calls = Ref(0)
  let active = fixture_array_start(n, calls, exact)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(
    capture(active).unwrap().captures[0].provider_model,
    "fixture-array-model",
  )
  assert_true(cleanup(active).unwrap())
  let short_calls = Ref(0)
  let short = fixture_array_start(n, short_calls, {
    ..exact,
    model: {
      ..exact.model,
      value_limits: { ..exact.model.value_limits, max_nodes: n + 2, },
    },
  })
  assert_true(fixture_finish(short) is Failed(Model(@model.OutputValue), ..))
  assert_true(acquire_output(short) is None)
  assert_true(capture(short) is None)
  assert_true(cleanup(short).unwrap())
  assert_eq(calls.val, 1)
  assert_eq(short_calls.val, 1)
}

///|
test "partial model reservations fail before calls and stay owned until cleanup" {
  let two = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let base = standard_limits()
  let limits = {
    ..base,
    model: { ..base.model, ledger: { ..base.model.ledger, attempts: 1, }, },
  }
  let calls = Ref(0)
  let active = fixture_start(
    fixture_prepared(source=two),
    () => calls.val += 1,
    limits~,
  )
  assert_true(
    fixture_finish(active)
    is Failed(Model(@model.Ledger(@resources.AttemptLimit)), ..),
  )
  let model = active.model.unwrap()
  let usage = @model.model_execution_resource_usage(model)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.reserved_transfer_bytes, 66536L)
  assert_eq(usage.reserved_retention_bytes, 66536L)
  assert_eq(calls.val, 0)
  assert_true(acquire_output(active) is None)
  assert_true(capture(active) is None)
  assert_true(!@input.cleanup_client_infer_input(active.input).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  let settled = @model.model_execution_resource_usage(model)
  assert_eq(settled.reserved_transfer_bytes, 0L)
  assert_eq(settled.reserved_retention_bytes, 0L)
  assert_eq(settled.reserved_execution_bytes, 0L)
  assert_eq(settled.attempts, 1)
  assert_eq(calls.val, 0)
}

///|
test "mapped request byte limits preflight every row before the first call" {
  // Canonical {"text":"hello"} has sixteen bytes, independently of the
  // execution counters or provider output. Fifteen cannot admit this request.
  let base = standard_limits()
  let exact = { ..base, model: { ..base.model, max_request_bytes: 16L, }, }
  let exact_calls = Ref(0)
  let exact_run = fixture_start(
    fixture_prepared(),
    () => exact_calls.val += 1,
    limits=exact,
  )
  assert_true(fixture_finish(exact_run) is Complete(_, ..))
  assert_eq(exact_calls.val, 1)
  assert_eq(
    @model.model_execution_prepared_request_bytes(exact_run.model.unwrap(), 0),
    Some(16L),
  )
  assert_true(cleanup(exact_run).unwrap())
  let short_calls = Ref(0)
  let short = fixture_start(fixture_prepared(), () => short_calls.val += 1, limits={
    ..exact,
    model: { ..exact.model, max_request_bytes: 15L, },
  })
  assert_true(fixture_finish(short) is Failed(Model(@model.RequestLimit), ..))
  assert_eq(short_calls.val, 0)
  assert_true(capture(short) is None)
  assert_true(acquire_output(short) is None)
  assert_true(cleanup(short).unwrap())
  let two = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"longer\"}]",
  )
  let late_calls = Ref(0)
  let late = fixture_start(
    fixture_prepared(source=two),
    () => late_calls.val += 1,
    limits=exact,
  )
  assert_true(fixture_finish(late) is Failed(Model(@model.RequestLimit), ..))
  let model = late.model.unwrap()
  assert_eq(@model.model_execution_prepared_request_bytes(model, 0), Some(16L))
  assert_eq(@model.model_execution_prepared_request_bytes(model, 1), None)
  assert_eq(late_calls.val, 0)
  assert_true(acquire_output(late) is None)
  let before = @model.model_execution_resource_usage(model)
  assert_eq(before.attempts, 2)
  assert_eq(before.reserved_retention_bytes, 2L * (16L + 65536L))
  assert_true(cleanup(late).unwrap())
  assert_true(cleanup(late).unwrap())
  let after = @model.model_execution_resource_usage(model)
  assert_eq(after.reserved_transfer_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.attempts, 2)
  assert_eq(late_calls.val, 0)
}

///|
test "all mapped requests remain prepared and pinned across model dispatch" {
  let two = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  let current : Ref[Execution?] = Ref(None)
  let calls = Ref(0)
  let ready = Ref(true)
  let active = fixture_start(fixture_prepared(source=two), () => {
    let owner = current.val.unwrap()
    let model = owner.model.unwrap()
    ready.val = ready.val &&
      !@model.model_execution_preflighting(model) &&
      @model.model_execution_prepared_request_bytes(model, 0) == Some(16L) &&
      @model.model_execution_prepared_request_bytes(model, 1) == Some(16L) &&
      !@input.cleanup_client_infer_input(owner.input).unwrap()
    calls.val += 1
  })
  current.val = Some(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  assert_true(ready.val)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
}

///|
fn fixture_input_array_prepared(
  count : Int,
) -> @publication_host.PreparedClientProgram raise {
  let wire = @json.parse(infer_fixture_environment)
  let source = @json.parse(infer_fixture_program)
  guard wire is Object(environment) &&
    environment["model_task_contracts"] is Array([task]) &&
    task is Object(fields) &&
    fields["input_contract"] is Object(contract) &&
    contract["fields"] is Object(input_fields) &&
    environment["host_policy_profile"] is Object(policy) &&
    policy["capacity"] is Object(capacity) &&
    source is Object(program) &&
    program["stages"] is Array([Object(stage)]) &&
    stage["steps"] is Array([Object(first), ..]) &&
    first["values"] is Object(values) &&
    values["schema"] is Object(schema) &&
    values["rows"] is Array([Object(row)]) else {
    abort("ordinary input-array Program fixture")
  }
  let input_wire =
    #|{"items":{"nullable":false,"type":"number"},"max_items":1024,"nullable":true,"type":"array"}
  let input_type = @json.parse(input_wire)
  schema["text"] = input_type
  input_fields["text"] = input_type
  row["text"] = Json::array(
    Array::makei(count, index => Json::number(index.to_double())),
  )
  capacity["max_model_request_bytes_per_item"] = Json::number(65536)
  capacity["max_nested_value_bytes"] = Json::number(10000)
  fields["input_schema_cid"] = Json::string(
    "sha256:" +
    @sha.hex(@utf8.encode(fixture_canonical(fields["input_contract"]))),
  )
  fields.remove("contract_cid") |> ignore
  fields["contract_cid"] = Json::string(
    "sha256:" + @sha.hex(@utf8.encode(fixture_canonical(task))),
  )
  environment.remove("evidence_bundle_cid") |> ignore
  fixture_prepared(
    source=fixture_canonical(source),
    environment_wire=fixture_canonical(wire),
  )
}

///|
test "nested mapped input stops during request encoding with zero model calls" {
  let calls = Ref(0)
  let active = fixture_start(fixture_input_array_prepared(1024), () => {
    calls.val += 1
  })
  let mut reached = false
  for _ in 0..<50000 {
    assert_true(advance(active, 1).unwrap() is Continue(_))
    if request_preflight_pending(active) {
      reached = true
      break
    }
  }
  assert_true(reached)
  // Key/read setup costs fewer than 64 steps. The 1024-element array itself
  // needs 2050 emitted frames, so these polls are inside the request encoder.
  for _ in 0..<64 {
    assert_true(advance(active, 1).unwrap() is Continue(_))
    assert_true(request_preflight_pending(active))
  }
  let model = active.model.unwrap()
  assert_eq(@model.model_execution_prepared_request_bytes(model, 0), None)
  assert_eq(calls.val, 0)
  assert_false(cleanup(active).unwrap())
  assert_false(@input.cleanup_client_infer_input(active.input).unwrap())
  assert_true(cancel(active))
  assert_true(advance(active, 1).unwrap() is Stopped(_))
  assert_true(capture(active) is None)
  assert_true(acquire_output(active) is None)
  let before = @model.model_execution_resource_usage(model)
  assert_eq(before.attempts, 1)
  assert_eq(before.reserved_retention_bytes, 131072L)
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  let after = @model.model_execution_resource_usage(model)
  assert_eq(after.reserved_transfer_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.attempts, 1)
  assert_eq(calls.val, 0)
}

///|
test "nested mapped request has independent byte and charged-work boundaries" {
  // {"text":[0,...,15]}: eleven structural/name bytes, twenty-two digit
  // bytes and fifteen commas. Its array emits 34 frames, replacing a scalar
  // frame in the 18-transition model path: 18 - 1 + 34 = 51 transitions.
  let base = standard_limits()
  let exact = {
    ..base,
    model: { ..base.model, max_request_bytes: 48L, max_work: 51, },
  }
  let calls = Ref(0)
  let active = fixture_start(
    fixture_input_array_prepared(16),
    () => calls.val += 1,
    limits=exact,
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(
    @model.model_execution_prepared_request_bytes(active.model.unwrap(), 0),
    Some(48L),
  )
  assert_eq(calls.val, 1)
  assert_true(cleanup(active).unwrap())
  let short_calls = Ref(0)
  let short = fixture_start(
    fixture_input_array_prepared(16),
    () => short_calls.val += 1,
    limits={ ..exact, model: { ..exact.model, max_request_bytes: 47L, }, },
  )
  assert_true(fixture_finish(short) is Failed(Model(@model.RequestLimit), ..))
  assert_eq(short_calls.val, 0)
  assert_true(capture(short) is None)
  assert_true(cleanup(short).unwrap())
  let work_calls = Ref(0)
  let work_short = fixture_start(
    fixture_input_array_prepared(16),
    () => work_calls.val += 1,
    limits={ ..exact, model: { ..exact.model, max_work: 50, }, },
  )
  assert_true(fixture_finish(work_short) is Failed(Model(@model.WorkLimit), ..))
  assert_eq(work_calls.val, 1)
  assert_true(capture(work_short) is None)
  assert_true(acquire_output(work_short) is None)
  assert_true(cleanup(work_short).unwrap())
}
