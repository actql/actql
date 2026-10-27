///|
struct EffectSourceDispatchFixture {
  admission : ResidentRunAdmission
  limits : @host.ClientEffectComputationLimits
  delegation : @resident.ResidentSiteDelegation
  request : @remote.DispatchRequest
  wire : String
  binding : @remote.RemoteInputBinding
}

///|
fn effect_source_dispatch_fixture() -> EffectSourceDispatchFixture {
  let (admission, _, _, _, _) = resident_source_dispatch_fixture()
  let prepared = resident_effect_source_prepared()
  let limits : @host.ClientEffectComputationLimits = {
    program: @host.client_standard_program_preparation_limits(),
    max_members: 1,
    max_header_work: 1000,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    admission.expressions,
    admission.operations,
  ).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    admission.manifests,
    admission.limits.sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "resident-effect", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let caller = @host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-caller",
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  let request = @host.prepare_client_effect_source_dispatch(
    allowed,
    definition,
    caller,
    1,
    "original-effect-producer",
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
  let wire = @host.issue_client_effect_run_materials(
    allowed,
    definition,
    environment,
    resident_effect_source_environment,
    resident_effect_source_document,
    None,
    limits,
  ).unwrap()
  {
    admission,
    limits,
    request,
    wire,
    binding: @host.prepare_client_effect_source_input_binding(compilation).unwrap(),
    delegation: {
      coordinator_authority: "sha256:" + "c".repeat(64),
      site_key: "retained-native",
      runtime_bundle_cid: "sha256:" + "d".repeat(64),
      connector_registration: "local",
      connector_revision: "local/1",
      strategy_revision: "strategy/1",
      grant_cid: "sha256:" + "5".repeat(64),
      evidence_issuer_capability_cid: "sha256:" + "4".repeat(64),
      budget_cids: ["sha256:" + "3".repeat(64)],
    },
  }
}

///|
fn effect_source_dispatch_admit(
  fixture : EffectSourceDispatchFixture,
  generation? : Int = 1,
  now? : String = "2026-10-09T01:00:00.000Z",
) -> Result[@host.PreparedClientEffectRun, ResidentEffectSourceDispatchIssue] {
  admit_resident_effect_source_dispatch(
    fixture.admission,
    fixture.limits,
    fixture.delegation,
    generation,
    fixture.request,
    fixture.wire,
    fixture.binding,
    now,
    resident_effect_source_contracts(),
    resident_effect_source_values,
    resident_effect_source_fragment,
  )
}

///|
test "Effect Source dispatch reconstructs the original Effect Run before acquisition" {
  let fixture = effect_source_dispatch_fixture()
  let bound = effect_source_dispatch_admit(fixture).unwrap()
  let graph = resident_source_owner_graph(Effect(bound))
  assert_true(resident_source_owner_supported(Effect(bound)))
  assert_true(@strategy.graph_program_has_effects(graph))
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(
    @remote.remote_input_binding_body(fixture.binding),
    "{\"source_contract_cid\":\"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3\",\"source_ref\":\"connector://crm/main/r#v\"}",
  )
}

///|
test "Effect Source dispatch refuses revoked delegation before rebuilding materials" {
  let fixture = effect_source_dispatch_fixture()
  assert_true(
    effect_source_dispatch_admit({
      ..fixture,
      wire: "{}",
      delegation: {
        ..fixture.delegation,
        grant_cid: "sha256:" + "0".repeat(64),
      },
    })
    is Err(Refused(@resident.ForeignGrant)),
  )
}

///|
test "Effect Source dispatch refuses a changed Site generation" {
  assert_true(
    effect_source_dispatch_admit(effect_source_dispatch_fixture(), generation=2)
    is Err(Refused(@resident.StaleGeneration)),
  )
}

///|
test "Effect Source dispatch retains the original Run and authorization deadline" {
  assert_true(
    effect_source_dispatch_admit(
      effect_source_dispatch_fixture(),
      now="2026-10-10T00:00:00.000Z",
    )
    is Err(Refused(@resident.NotCurrent)),
  )
}

///|
test "Effect Source dispatch refuses changed original Run materials" {
  let fixture = effect_source_dispatch_fixture()
  assert_true(
    effect_source_dispatch_admit({
      ..fixture,
      wire: fixture.wire.replace(old="original-effect-run", new="another-run"),
    })
    is Err(Materials(@host.RunMismatch)),
  )
}

///|
test "Effect Source dispatch refuses substituted logical input" {
  let fixture = effect_source_dispatch_fixture()
  assert_true(
    effect_source_dispatch_admit({
      ..fixture,
      binding: @remote.prepare_remote_input_binding("{}", 8192).unwrap(),
    })
    is Err(Dispatch(@host.ForeignInput)),
  )
}

///|
test "Effect Source dispatch refuses a different trusted Source before acquisition" {
  let fixture = effect_source_dispatch_fixture()
  assert_true(
    effect_source_dispatch_admit({
      ..fixture,
      admission: {
        ..fixture.admission,
        source: Some(("connector://other/r#v", "sha256:" + "0".repeat(64))),
      },
    })
    is Err(Source(ForeignInput)),
  )
}

///|
test "Effect Source dispatch refuses another task of the same Run under producer materials" {
  let fixture = effect_source_dispatch_fixture()
  let consumer = @remote.prepare_dispatch_request(
    fixture.delegation.coordinator_authority,
    @remote.dispatch_request_task_scope(fixture.request).0,
    "task_1",
    1,
    "wrong-consumer",
    fixture.delegation.site_key,
    1,
    fixture.delegation.runtime_bundle_cid,
    fixture.delegation.connector_registration,
    fixture.delegation.connector_revision,
    fixture.delegation.strategy_revision,
    @remote.remote_input_binding_cid(fixture.binding),
    "sha256:" + "2".repeat(64),
    fixture.delegation.budget_cids[0],
    fixture.delegation.evidence_issuer_capability_cid,
    fixture.delegation.grant_cid,
  ).unwrap()
  assert_true(
    effect_source_dispatch_admit({ ..fixture, request: consumer, })
    is Err(Dispatch(@host.ForeignDispatch)),
  )
}

///|
fn effect_source_restored_materials(
  fixture : EffectSourceDispatchFixture,
) -> @host.ClientEffectRunMaterials {
  @host.admit_client_effect_run_materials(
    fixture.wire,
    @remote.dispatch_request_task_scope(fixture.request).0,
    fixture.admission.expressions,
    fixture.admission.operations,
    fixture.admission.manifests,
    fixture.admission.limits,
    fixture.limits,
  ).unwrap()
}

///|
test "Effect Source dispatch refuses a swapped opaque compilation" {
  let fixture = effect_source_dispatch_fixture()
  let original = effect_source_restored_materials(fixture)
  let separately_restored = effect_source_restored_materials(fixture)
  assert_true(
    @host.bind_client_effect_source_dispatch(
      { ..original, compilation: separately_restored.compilation, },
      fixture.request,
      fixture.binding,
    )
    is Err(@host.ForeignDispatch),
  )
}

///|
test "Effect Source dispatch refuses a caller with a different initial input intent" {
  let fixture = effect_source_dispatch_fixture()
  let materials = effect_source_restored_materials(fixture)
  let caller = @host.prepare_client_effect_request_identity(
    materials.prepared,
    fixture.delegation.coordinator_authority,
    "foreign-initial-input",
    "sha256:" + "9".repeat(64),
  ).unwrap()
  assert_true(
    @host.prepare_client_effect_source_dispatch(
      materials.allowed,
      materials.run_definition,
      caller,
      1,
      "foreign-dispatch",
      {
        site_key: fixture.delegation.site_key,
        site_generation: 1,
        runtime_bundle_cid: fixture.delegation.runtime_bundle_cid,
        connector_registration: fixture.delegation.connector_registration,
        connector_revision: fixture.delegation.connector_revision,
        strategy_revision: fixture.delegation.strategy_revision,
        obligations_cid: "sha256:" + "2".repeat(64),
        budget_cid: fixture.delegation.budget_cids[0],
        evidence_issuer_capability_cid: fixture.delegation.evidence_issuer_capability_cid,
        grant_cid: fixture.delegation.grant_cid,
      },
    )
    is Err(@host.ForeignRequest),
  )
}

///|
test "Effect checked task fragment retains original materials and rejects swapped compilation" {
  let fixture = effect_source_dispatch_fixture()
  let materials = effect_source_restored_materials(fixture)
  let producer = @host.issue_client_effect_task_fragment(materials, 0).unwrap()
  let consumer = @host.issue_client_effect_task_fragment(materials, 1).unwrap()
  assert_eq(
    @host.client_task_fragment_node_id(producer),
    @remote.dispatch_request_task_scope(fixture.request).1,
  )
  let edge = @host.prepare_client_effect_retained_input_edge(
    materials.allowed,
    materials.run_definition,
  ).unwrap()
  assert_eq(
    @host.client_task_fragment_node_id(consumer),
    @host.client_retained_input_edge_projection(edge)[5],
  )
  assert_true(
    @host.issue_client_effect_task_fragment(materials, 2)
    is Err(@host.UnsupportedGraph),
  )
  assert_true(
    @host.issue_client_effect_task_fragment(
      {
        ..materials,
        compilation: effect_source_restored_materials(fixture).compilation,
      },
      1,
    )
    is Err(@host.ForeignDispatch),
  )
}
