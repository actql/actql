///|
let structured_raw_configuration : String =
  #|{"adapter_kind":"fixture-sdk","api_mode":"structured","endpoint":"https://fixture.invalid/v1/chat/completions","model_id":"actual-sdk-model","provider_id":"models/fixture","selector":"fixture-risk-model"}

///|
fn structured_raw_fixture_profile() -> @environment.ModelResponseProfile {
  async_response_profile(
    task_cid="sha256:96ac9b2a06dae7a547aba6db6011d92bf6649a8832f65b1b986068b9561c8b31",
    profile_cid="sha256:0475472264a9a557131a3d11b83d92af8a9e5e916fed38c2d19a148dd6c8d519",
  )
}

///|
fn structured_raw_fixture_binding() -> (
  @publication.RunEvidenceValue,
  String,
  String,
  String,
) {
  let binding = @publication_host.issue_client_model_provider_binding(
    "models/fixture", "{}", "{}", structured_raw_configuration,
  ).unwrap()
  let empty = "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
  (
    binding,
    empty,
    empty,
    "sha256:" + @sha.hex(@utf8.encode(structured_raw_configuration)),
  )
}

///|
fn start_structured_raw_fixture(limits : Limits) -> Execution {
  let environment = @publication_host.admit_client_check_environment(
    first_m1_current_environment,
    first_m1_current_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    first_m1_current_program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    2,
    @utf8.encode(first_m1_current_execution),
    first_m1_current_execution_cid,
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
    @model.install_async_model_provider("models/fixture").unwrap(),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    plan=Some(plan),
  ).unwrap()
}

///|
fn structured_raw_fixture_plan(
  active : Execution,
  request : @model.ModelRequest,
  binding : @publication.RunEvidenceValue,
  profile : @environment.ModelResponseProfile,
  start : (@model.ModelCallEntry) -> @model.ModelPhysicalCall?,
  foreign_decoder_profile : Bool,
) -> Result[@model.ModelPhysicalRequestPlan, @model.ModelExecutionIssue] {
  let execution = @publication_host.client_infer_plan_graph_execution_contract(
    active.plan.unwrap(),
  )
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(@utf8.encode(first_m1_current_prompt)),
    Some(@utf8.encode(first_m1_current_retry)),
    Some(@utf8.encode(first_m1_current_backoff)),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  let installation = async_response_installation()
  let selected : @model.ResolvedStructuredModel = {
    selector: "fixture-risk-model",
    model_id: "actual-sdk-model",
    adapter_kind: "fixture-sdk",
    api_mode: "structured",
    endpoint: installation.endpoint,
  }
  guard active.source is Physical(original) else { abort("fixture Provider") }
  let capability = @model.register_structured_model_capability(
    original, binding, structured_raw_configuration, selected, profile, true, true,
  ).unwrap()
  let admitted = @model.admit_structured_model_provider(
    capability,
    selected,
    execution,
    dependencies,
    installation,
    (_, _) => true,
  ).unwrap()
  @model.structured_model_async_request_plan(
    admitted,
    capability,
    binding,
    selected,
    request,
    1000L,
    { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    profile,
    installation,
    start,
    (_, _, bytes) => {
      decode_structured_fixture(
        if foreign_decoder_profile {
          async_response_profile()
        } else {
          profile
        },
        bytes,
      )
    },
  )
}

///|
let structured_raw_wire : String =
  #|{"answer":{"reason":null,"risk":"high"},"input_tokens":3,"output_tokens":0}

///|
// The original Call, raw binding and receipt are actual Common values. The
// adapter's decoded observations and the trusted Store ACK are deterministic
// doubles. The raw body deliberately does not match the Chat envelope.
fn observe_structured_fixture_raw(
  fixture : RawSaveFixture,
  eof? : Bool = true,
) -> @model.ModelRawCaptureSave {
  let bytes = @utf8.encode(structured_raw_wire)
  @model.observe_model_raw_capture(
    fixture.call,
    fixture.registration,
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
    200,
    eof,
    "2026-10-03T00:00:00.000Z",
  ).unwrap()
}

///|
fn decode_structured_fixture(
  profile : @environment.ModelResponseProfile,
  bytes : Bytes,
) -> @model.ModelPhysicalEncodedResponse? {
  let parsed = @json.parse(@utf8.decode(bytes[:])) catch { _ => return None }
  guard parsed is Object(raw) &&
    raw.get("answer") is Some(answer) &&
    raw.get("input_tokens") is Some(Number(input, ..)) &&
    raw.get("output_tokens") is Some(Number(output, ..)) else {
    return None
  }
  Some({
    body: answer.stringify(),
    observation: {
      ..async_response_observation(None).observation,
      response_profile_cid: Some(
        @environment.model_response_profile_identity(profile),
      ),
      raw_response_artifact_cid: Some("sha256:" + "f".repeat(64)),
      input_tokens: Some(input.to_int64()),
      output_tokens: Some(output.to_int64()),
    },
    transport_eof: true,
    endpoint_complete: true,
    answer_complete: true,
  })
}

///|
test "structured answer adoption requires the original saved raw receipt" {
  let active = raw_save_fixture(structured=true)
  let foreign = raw_save_fixture(structured=true)
  let save = observe_structured_fixture_raw(active)
  let foreign_save = observe_structured_fixture_raw(foreign)
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  let foreign_receipt = @model.acknowledge_saved_model_raw_capture(foreign_save).unwrap()
  let bytes = @utf8.encode(structured_raw_wire)
  assert_true(
    @model.model_physical_saved_structured_response(
      active.call,
      foreign_receipt,
      bytes,
    )
    is Err(@model.RequestIdentity),
  )
  let replaced = @utf8.encode(
    structured_raw_wire.replace(old="high", new="fake"),
  )
  assert_eq(replaced.length(), bytes.length())
  assert_true(
    @model.model_physical_saved_structured_response(
      active.call,
      receipt,
      replaced,
    )
    is Err(@model.RequestIdentity),
  )
  let terminal = @model.model_physical_saved_structured_response(
    active.call,
    receipt,
    bytes,
  ).unwrap()
  foreign.response.val = terminal
  foreign.ready.val = true
  assert_true(
    fixture_finish(foreign.active, initial_work=foreign.work)
    is Failed(Model(@model.RequestIdentity), ..),
  )
  assert_true(acquire_output(foreign.active) is None)
  assert_eq(
    @model.model_execution_quantity_usage(foreign.active.model.unwrap()).consumed.tokens,
    0L,
  )
  assert_true(cleanup(foreign.active).unwrap())

  active.response.val = terminal
  active.ready.val = true
  guard fixture_finish(active.active, initial_work=active.work)
    is Settling(0, work~) else {
    abort("the same saved receipt must reach typed settlement")
  }
  let wire = async_settlement_wire(active.active)
  let raw = @publication.model_raw_response_value(
    @model.model_raw_capture_save_binding(save),
  )
  assert_true(
    wire.contains(
      "\"raw_response_artifact_cid\":\"" +
      @publication.run_evidence_value_identity(raw) +
      "\"",
    ),
  )
  assert_true(wire.contains("\"observed_at\":\"2026-10-03T00:00:00.000Z\""))
  assert_true(wire.contains("\"output_tokens\":0"))
  assert_true(wire.contains("\"risk\":\"high\""))
  assert_eq(
    @model.model_execution_quantity_usage(active.active.model.unwrap()).consumed.tokens,
    3L,
  )
  assert_true(
    @model.acknowledge_model_call_settlement(
      call_settlement(active.active).unwrap(),
    ),
  )
  assert_true(
    fixture_finish(active.active, initial_work=work) is Complete(_, ..),
  )
  assert_true(release_output(acquire_output(active.active).unwrap()))
  assert_true(cleanup(active.active).unwrap())
  assert_eq(active.calls.val, 1)
  assert_eq(foreign.calls.val, 1)
}

///|
test "structured execution rejects a substituted encoded answer without the checked decoder" {
  let fixture = raw_save_fixture(structured=true)
  fixture.response.val = @model.PhysicalEncodedResponse(
    decode_structured_fixture(
      structured_raw_fixture_profile(),
      @utf8.encode(structured_raw_wire.replace(old="high", new="fake")),
    ).unwrap(),
  )
  fixture.ready.val = true
  assert_true(
    fixture_finish(fixture.active, initial_work=fixture.work)
    is Failed(Model(@model.OutputIdentity), ..),
  )
  assert_true(acquire_output(fixture.active) is None)
  assert_eq(
    @model.model_execution_quantity_usage(fixture.active.model.unwrap()).consumed.tokens,
    0L,
  )
  assert_true(cleanup(fixture.active).unwrap())
  assert_eq(fixture.calls.val, 1)
}

///|
test "structured decoding cannot replace the original incomplete transport observation" {
  let fixture = raw_save_fixture(structured=true)
  let save = observe_structured_fixture_raw(fixture, eof=false)
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  assert_true(
    @model.model_physical_saved_structured_response(
      fixture.call,
      receipt,
      @utf8.encode(structured_raw_wire),
    )
    is Err(@model.OutputIdentity),
  )
  structured_fixture_finish_unknown(fixture)
}

///|
test "structured output from a different decoder profile cannot replace the original" {
  let fixture = raw_save_fixture(structured=true, foreign_decoder_profile=true)
  let save = observe_structured_fixture_raw(fixture)
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  assert_true(
    @model.model_physical_saved_structured_response(
      fixture.call,
      receipt,
      @utf8.encode(structured_raw_wire),
    )
    is Err(@model.OutputIdentity),
  )
  structured_fixture_finish_unknown(fixture)
}

///|
fn structured_fixture_finish_unknown(fixture : RawSaveFixture) -> Unit raise {
  fixture.ready.val = true
  assert_true(
    fixture_finish(fixture.active, initial_work=fixture.work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(acquire_output(fixture.active) is None)
  assert_true(cleanup(fixture.active).unwrap())
  assert_eq(fixture.calls.val, 1)
}
