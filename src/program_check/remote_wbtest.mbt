// Fixture inputs reused from the fixed SourceView and capacity corpus.
// These hashes are input admissions, not expected compiler output.

///|
fn keyed_sourceview_environment() -> @environment.WireEnvironment {
  @environment.read(
    @utf8.encode(
      "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:9a7ee4daaf749f3a196d0e7ca49efc2dc70fe8b0590ae55488a767b10ef885a4\",\"commands\":[],\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contracts\":[{\"body\":{\"additional_properties\":false,\"fields\":{\"extra\":{\"nullable\":false,\"type\":\"number\"},\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"lookup_capacity\":{\"completeness\":\"complete_per_requested_key\",\"max_pages_per_request\":3,\"max_response_bytes_per_page\":4096,\"max_rows_per_key\":2,\"version\":\"actql-lookup-capacity/0.1\"}},\"cid\":\"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tenant\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"correlation\":{\"cardinality\":\"zero_or_many\",\"identity\":[\"id\"],\"request_fields\":[\"id\"],\"response_fields\":[\"id\"]},\"default_mode\":\"snapshot\",\"kind\":\"fetch\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:1a03e9c57e04b3fe35e6c43e7ebe8814c346757d42c0d72c830ffab5cbaef2f9\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}]}],\"contract_registry\":[{\"body\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tenant\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"lookup_capacity\":{\"completeness\":\"complete_per_requested_key\",\"max_pages_per_request\":3,\"max_response_bytes_per_page\":4096,\"max_rows_per_key\":2,\"version\":\"actql-lookup-capacity/0.1\"}},\"cid\":\"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6\",\"id\":\"fixture-3\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"additional_properties\":false,\"fields\":{\"extra\":{\"nullable\":false,\"type\":\"number\"},\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742\",\"id\":\"fixture-1\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{},\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://crm/main/r#v\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}],\"evidence_bundle_cid\":\"sha256:b30a6865027ed2707049e1d48867d9409b460ef35775e750e818d92e26f4caf6\",\"host_policy_profile\":{\"lookup_execution\":{\"max_network_attempts_per_request\":3,\"max_request_bytes_per_attempt\":1024,\"max_total_decoded_response_bytes\":65536,\"max_total_duration_ms\":30000,\"max_total_request_bytes\":1,\"max_total_response_bytes\":1,\"version\":\"actql-lookup-execution-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[{\"acquisition\":{\"authority\":\"read_metadata\",\"correlation\":{\"cardinality\":\"zero_or_many\",\"identity\":[\"id\"],\"request_fields\":[\"id\"],\"response_fields\":[\"id\"]},\"default_mode\":\"snapshot\",\"kind\":\"fetch\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf\",\"id\":\"fixture-0\",\"version\":\"fixture\"}},\"connector_id\":\"crm/main\",\"connector_version\":\"fixture\",\"contract_cid\":\"sha256:1a03e9c57e04b3fe35e6c43e7ebe8814c346757d42c0d72c830ffab5cbaef2f9\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"id\":\"fixture-2\",\"version\":\"fixture\"},\"facts\":{\"cid\":\"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6\",\"id\":\"fixture-3\",\"version\":\"fixture\"},\"schema\":{\"cid\":\"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742\",\"id\":\"fixture-1\",\"version\":\"fixture\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24\",\"id\":\"fixture-4\",\"version\":\"fixture\"},\"operations\":[]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"record\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"v\",\"view_version\":\"fixture\"}],\"version\":\"actql-check-environment/0.1\"}",
    ),
    "sha256:b30a6865027ed2707049e1d48867d9409b460ef35775e750e818d92e26f4caf6",
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
}

///|
fn keyed_sourceview_claim() -> @wire.ProgramProofClaim {
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(
      "{\"dependencies\":[\"sha256:02fa1dd5e32fc11c42454c3e573531ad747e164ee12d88921206650b45014033\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.values\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:02fa1dd5e32fc11c42454c3e573531ad747e164ee12d88921206650b45014033\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d\"}",
    ),
    "sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d",
    limits,
  ).unwrap()
  @wire.bind_program_proof(
    @utf8.encode(
      "{\"inputs\":[],\"law_id\":\"actql.bound.values\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    witness,
    limits,
  ).unwrap()
}

///|
fn capacity_profile(changed : Bool, analytic? : Bool = false) -> String {
  let names = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  if analytic {
    for
      name in [
        "max_analytic_partition_wire_bytes", "max_analytic_output_wire_bytes", "max_analytic_input_wire_bytes",
        "max_analytic_frame_memberships",
      ] {
      names.push(name)
    }
    names.sort_by((a, b) => @canonical.compare_utf16(a, b))
  }
  "{\"capacity\":{" +
  names
  .map(name => {
    "\"" +
    name +
    "\":" +
    (if changed && name == "max_artifact_bytes" { "2" } else { "1" })
  })
  .join(",") +
  ",\"version\":\"actql-capacity-host-policy/0.1\"}}"
}

///|

///|
fn remote_environment_fixture(
  analytic? : Bool = false,
) -> @environment.WireEnvironment raise {
  let original = keyed_sourceview_environment()
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(original, writer)
  let profile = capacity_profile(false, analytic~)
  let body = @encode.finish(writer)
    .replace(
      old="\"evidence_bundle_cid\":\"" + @environment.cid(original) + "\",",
      new="",
    )
    .replace(
      old="\"host_policy_profile\":{",
      new="\"host_policy_profile\":{" +
        profile[1:profile.length() - 1].to_owned() +
        ",",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let environment = @environment.read(
    @utf8.encode(
      body.replace(
        old="\"host_policy_profile\":",
        new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
      ),
    ),
    cid,
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
  environment
}

///|
fn remote_construction_fixture(
  budget : IdentityBudget,
) -> (
  @context.ProgramSourceIdentity,
  @context.StageRequirementClosure,
  @context.ProgramIncomingGates,
  @context.CoreContractInventory,
  Array[BuiltUnit],
) raise {
  let environment = remote_environment_fixture()
  let text =
    #|{"version":"actql/0.1","id":"keyed","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"tenant":null}}},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"join":{"left":"seed","with":"remote","on":"id","kind":"left","select":{"id":"left.id"}}}],"results":{"out":{"from":"seed","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let (views, locals) = @context.prepare_source_registrations(
    source,
    catalog_fixture(environment),
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_text_bytes: 1000000,
    },
    max_inputs=10,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let base = source_limits_fixture(1)
  let caps : SourceLimits = {
    ..base,
    topology: { ..base.topology, max_steps: 2, },
  }
  let limits = caps.topology
  let (wiring, _) = @context.prepare_sourceview_program(views, locals, limits).unwrap()
  let prepared = @results.bind_prepared_program(wiring, None, limits).unwrap()
  let proof = keyed_sourceview_claim()
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
  )
  let host = @host.create(
    @policy.ceiling(policy, "max_relation_output_rows").unwrap(),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 30)
  @host.emit(host, writer)
  let host_text = @encode.finish(writer)
  let host_wire = @wire.admit(@utf8.encode(host_text), @host.cid(host), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  // Fixture input, not an expected lowerer result. Join output is enforced
  // atomically; the one-row proof belongs only to its left Values producer.
  let limit_body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    host_text +
    "],\"effective_max\":1,\"enforcement\":\"engine_atomic\",\"subject_ref\":\"join:checked-step:1:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}"
  let limit_cid = "sha256:" + @sha.hex(@utf8.encode(limit_body))
  let limit_text = limit_body.replace(
    old="\"subject_ref\":",
    new="\"resolved_limit_cid\":\"" + limit_cid + "\",\"subject_ref\":",
  )
  let arithmetic = @wire.check_mixed_claims(
    [@wire.program_proof_witness(proof), host_wire],
    [(@utf8.encode(limit_text), limit_cid)],
    {
      max_entities: 100,
      max_references: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(arithmetic, [proof], {
    max_witnesses: 10,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let ports = @results.stage_port_publications(
    @results.wiring_stage_at(@results.local_source_wiring(prepared), 0).unwrap(),
  )
  let visits = @pipeline.contextual_closure_count(
    @publication.checked_producer_orders(@publication.ports_orders(ports)),
  )
  let materials = [
    Array::makei(visits, _ => @context.CapacityMaterial::{
      sources,
      consumers: [],
    }),
  ]
  for i in 0..<materials[0].length() {
    materials[0][i] = {
      sources,
      consumers: [@capacity.Join(step=1, output=0)],
    }
  }
  construct_local(
    program,
    None,
    { wire: environment, locations: Some([[(0, 0)]]), },
    materials,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    caps,
    budget,
  )
}

///|
test "keyed SourceView construction retains capacity and incoming ownership" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (identity, requirements, gates, contracts, units) = remote_construction_fixture(
    budget,
  ) catch {
    LocalConstructionFailure::Closure(
      ConstructionFailure::UnresolvedOperation(site)
    ) => {
      match site.requirement {
        @pipeline.ValuesRequirement(v) => @debug.debug(v)
        @pipeline.JoinRequirement(v) => @debug.debug(v)
        _ => ()
      }
      fail("unresolved owned operation")
    }
    LocalConstructionFailure::Closure(ConstructionFailure::Operations(_)) =>
      fail("operation resolution")
    LocalConstructionFailure::Closure(
      ConstructionFailure::Requirements(
        @context.StageRequirementIssue::Operations(
          @context.OperationClosureIssue::IncompleteResolution(index)
        )
      )
    ) => fail("unresolved operation requirement " + index.to_string())
    LocalConstructionFailure::Closure(
      ConstructionFailure::Requirements(
        @context.StageRequirementIssue::LocalInputs(_)
      )
    ) => fail("Local input closure")
    LocalConstructionFailure::Closure(
      ConstructionFailure::Requirements(
        @context.StageRequirementIssue::Incoming(_)
      )
    ) => fail("incoming closure")
    LocalConstructionFailure::Closure(
      ConstructionFailure::Requirements(
        @context.StageRequirementIssue::Publications(_)
      )
    ) => fail("publication closure")
    LocalConstructionFailure::Closure(ConstructionFailure::Contracts(_)) =>
      fail("contract collection")
    LocalConstructionFailure::Closure(ConstructionFailure::Gates(_)) =>
      fail("incoming gate")
    e => raise e
  }
  assert_eq(units.length(), 1)
  assert_true(
    physical_equal(@context.core_contract_identity(contracts), identity),
  )
  assert_true(
    physical_equal(
      @context.program_incoming_gates_owner(gates),
      @context.stage_requirement_owner(requirements),
    ),
  )
  assert_eq(units[0].imports.length(), 0)
}
