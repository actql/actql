// Admission fixtures exercise the real saved Run materials boundary. They
// perform no physical acquisition; Native execution is tested separately.

///|
let resident_source_dispatch_document : String =
  #|{"id":"source-compute","results":{"answer":{"from":{"result":"r","stage":"compute"}}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"id":"compute","inputs":{"x":{"result":{"result":"r","stage":"acquire"}}},"results":{"r":{"fields":["id"],"from":"out"}},"steps":[{"filter":"id > 2"},{"as":"out","select":["id"]}]}],"version":"actql/0.1"}

///|
fn resident_source_dispatch_fixture(
  document? : String = resident_source_dispatch_document,
) -> (
  ResidentRunAdmission,
  @remote.DispatchRequest,
  String,
  @remote.RemoteInputBinding,
  @host.PreparedClientProgram,
) {
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_compiled_run_definition(
    allowed, "resident-source", "original-run", "2026-10-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let caller = @host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-caller",
  ).unwrap()
  let request = @host.prepare_client_task_dispatch(
    prepared,
    compilation,
    @host.client_compiled_run_admission(allowed),
    definition,
    caller,
    0,
    1,
    "original-producer",
    {
      site_key: "retained-native",
      site_generation: 1,
      runtime_bundle_cid: "sha256:" + "d".repeat(64),
      connector_registration: "local",
      connector_revision: "local/1",
      strategy_revision: "strategy/1",
      obligations_cid: "sha256:" + "2".repeat(64),
      budget_cid: "sha256:" + "3".repeat(64),
      evidence_issuer_capability_cid: "sha256:" + "4".repeat(64),
      grant_cid: "sha256:" + "5".repeat(64),
    },
  ).unwrap()
  let materials = @host.issue_client_task_run_materials(
    prepared,
    compilation,
    @host.client_compiled_run_admission(allowed),
    definition,
    environment,
    resident_effect_source_environment,
    document,
    None,
  ).unwrap()
  let admission : ResidentRunAdmission = {
    source: Some(
      (
        "connector://crm/main/r#v", "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
      ),
    ),
    expressions: { text_time: false, veca: false, },
    operations: {
      rela: true,
      sga: false,
      tea: false,
      calendar: false,
      text_rank: false,
    },
    manifests,
    limits: {
      preparation: @host.client_standard_program_preparation_limits(),
      sequence: @host.client_standard_values_sequence_limits(),
      max_sequence_steps: 1000,
      max_sequence_work: 1000,
      max_evidence_bytes: 1000000,
      max_evidence_nodes: 100000,
      max_evidence_depth: 100,
    },
  }
  (
    admission,
    request,
    materials,
    @host.prepare_client_task_input_binding(prepared, 0).unwrap(),
    prepared,
  )
}

///|
test "resident admission accepts only the original checked internal Source producer" {
  let (admission, request, wire, binding, _) = resident_source_dispatch_fixture()
  let materials = admit_materials(
    admission, request, wire, binding, "2026-10-05T00:00:00.000Z",
  ).unwrap()
  assert_true(
    resident_source_dispatch_role(materials, request)
    is Ok(InternalSourceProducer),
  )
  assert_eq(
    @strategy.graph_task_count(@host.prepared_client_graph(materials.prepared)),
    2,
  )
}

///|
test "resident admission refuses foreign configured Source before physical selection" {
  let (admission, request, wire, binding, _) = resident_source_dispatch_fixture()
  assert_true(
    admit_materials(
      {
        ..admission,
        source: Some(("connector://other/source#v", "sha256:" + "0".repeat(64))),
      },
      request,
      wire,
      binding,
      "2026-10-05T00:00:00.000Z",
    )
    is Err(@resident.ForeignSource),
  )
}

///|
test "resident admission does not admit a consumer under its producer input binding" {
  let (admission, request, wire, binding, prepared) = resident_source_dispatch_fixture()
  let task = @host.issue_prepared_client_task_fragment(
    prepared,
    1,
    @host.client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let consumer = @remote.prepare_dispatch_request(
    "sha256:" + "c".repeat(64),
    @remote.dispatch_request_task_scope(request).0,
    @host.client_task_fragment_node_id(task),
    1,
    "consumer-with-producer-input",
    "retained-native",
    1,
    "sha256:" + "d".repeat(64),
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_input_binding_cid(binding),
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
  ).unwrap()
  assert_true(
    admit_materials(
      admission, consumer, wire, binding, "2026-10-05T00:00:00.000Z",
    )
    is Err(@resident.UnsupportedTask),
  )
}

///|
test "resident internal producer retains the original Run lifetime refusal" {
  let (admission, request, wire, binding, _) = resident_source_dispatch_fixture()
  assert_true(
    admit_materials(
      admission, request, wire, binding, "2100-01-01T00:00:00.000Z",
    )
    is Err(_),
  )
}

///|
test "resident admission retains the one-task public Source Result role" {
  let document =
    #|{"id":"source","results":{"answer":{"from":{"result":"r","stage":"acquire"}}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]}],"version":"actql/0.1"}
  let (admission, request, wire, binding, _) = resident_source_dispatch_fixture(
    document~,
  )
  let materials = admit_materials(
    admission, request, wire, binding, "2026-10-05T00:00:00.000Z",
  ).unwrap()
  assert_true(
    resident_source_dispatch_role(materials, request) is Ok(PublicSourceResult),
  )
}
