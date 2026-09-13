///|
// This exercises private construction from real source, not a CheckedProgram
// success contract. Final semantic dependency coverage is still required.
fn local_construction_fixture(
  budget : IdentityBudget,
  second_stage? : Bool = false,
  unrelated_stage? : Bool = false,
  parameters? : Bool = false,
  supplied? : @decode.Cursor? = None,
  through_catalog? : Bool = false,
  through_check? : Bool = false,
  numeric_profile? : @numeric.Profile? = None,
  checked_results? : Array[CheckedProgram] = [],
  host_limit? : Int = 1000,
  string_limit? : Int? = None,
  analytic_limit? : Int? = None,
  producer_expression? : String = "id + 1",
  producer_suffix? : String = "",
  producer_result_from? : String = "derived",
  second_steps? : String = "[]",
  second_result_from? : String = "rows",
  extra_step_budget? : Int = 0,
  second_join_capacity? : Bool = false,
  second_join_step? : Int = 0,
  second_sequence_capacity? : Bool = false,
  sequence_output_proof? : Bool = false,
  second_sequence_step? : Int = 0,
  sequence_capacity_stage? : Int = 1,
  root_extra? : String = "",
  last_effects? : String? = None,
  registry_entries? : String = "[]",
  catalog_entries? : String = "[]",
  snapshot_entries? : String = "[]",
  generated_rows? : String? = None,
  local_schema? : String? = None,
  local_primary_key? : Bool = true,
  generated_schema? : String = "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
  nested_bytes? : Int? = None,
  nested_depth? : Int? = None,
  text_time? : Bool = false,
  tea? : Bool = false,
  calendar? : Bool = false,
  calendar_material? : Bool = true,
  text_policy? : Bool = false,
  generated_proofs? : Array[@wire.ProgramProofClaim] = [],
  generated_proof_stage? : Int = 1,
) -> (
  @context.ProgramSourceIdentity,
  @context.StageRequirementClosure,
  @context.ProgramIncomingGates,
  @context.CoreContractInventory,
  Array[BuiltUnit],
) raise LocalConstructionFailure {
  let second_stage = second_stage || unrelated_stage
  let stage_count = if unrelated_stage {
    3
  } else if second_stage {
    2
  } else {
    1
  }
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"local","stages":[{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + 1"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}}],"results":{"out":{"from":{"stage":"first","result":"out"}}}}
    )
    .replace(
      old="\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":[",
      new=match generated_rows {
        None =>
          "\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":["
        Some(rows) =>
          "\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
          generated_schema +
          ",\"rows\":" +
          rows +
          "},\"as\":\"seed\"},"
      },
    )
    .replace(
      old="\"id\":\"local\",",
      new=if parameters {
        "\"id\":\"local\",\"params\":{\"n\":{\"type\":\"number\",\"default\":1}},"
      } else {
        "\"id\":\"local\","
      },
    )
    .replace(
      old="\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]",
      new="\"schema\":" +
        local_schema.unwrap_or(
          "{\"id\":{\"type\":\"number\",\"nullable\":false}}",
        ) +
        ",\"primary_key\":[\"id\"]",
    )
    .replace(
      old=",\"primary_key\":[\"id\"]",
      new=if local_primary_key { ",\"primary_key\":[\"id\"]" } else { "" },
    )
    .replace(
      old="id + 1",
      new=if parameters { "id + $n" } else { producer_expression },
    )
    .replace(
      old="\"as\":\"derived\"}],\"results\":{\"out\":{\"from\":\"derived\"",
      new="\"as\":\"derived\"}" +
        producer_suffix +
        "],\"results\":{\"out\":{\"from\":\"" +
        producer_result_from +
        "\"",
    )
    .replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"first\",\"result\":\"out\"}}}}",
      new=if second_stage {
        "},{\"id\":\"second\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"first\",\"result\":\"out\"}},\"again\":{\"result\":{\"stage\":\"first\",\"result\":\"out\"}}},\"from\":\"rows\",\"steps\":" +
        second_steps +
        ",\"results\":{\"out\":{\"from\":\"" +
        second_result_from +
        "\",\"fields\":[\"id\",\"value\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"second\",\"result\":\"out\"}}}}"
      } else {
        "}],\"results\":{\"out\":{\"from\":{\"stage\":\"first\",\"result\":\"out\"}}}}"
      },
    )
    .replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"second\",\"result\":\"out\"}}}}",
      new=if unrelated_stage {
        "},{\"id\":\"unrelated\",\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"z\":{\"type\":\"boolean\",\"nullable\":false}},\"primary_key\":[\"z\"]}},\"steps\":[],\"results\":{\"out\":{\"from\":\"rows\",\"fields\":[\"z\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"second\",\"result\":\"out\"}}}}"
      } else {
        "}],\"results\":{\"out\":{\"from\":{\"stage\":\"second\",\"result\":\"out\"}}}}"
      },
    )
    .replace(old="\"id\":\"local\",", new="\"id\":\"local\"," + root_extra)
    .replace(
      old=if second_stage { "\"id\":\"second\"," } else { "\"id\":\"first\"," },
      new=(if second_stage {
          "\"id\":\"second\","
        } else {
          "\"id\":\"first\","
        }) +
        (match last_effects {
          Some(text) => "\"effects\":" + text + ","
          None => ""
        }),
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: stage_count,
    },
    format=Json,
  ).unwrap()
  let names = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  if analytic_limit is Some(_) {
    for
      name in [
        "max_analytic_partition_wire_bytes", "max_analytic_output_wire_bytes", "max_analytic_input_wire_bytes",
        "max_analytic_frame_memberships",
      ] {
      names.insert(1, name)
    }
  }
  if string_limit is Some(_) {
    names.insert(1, "max_aggregate_string_bytes")
  }
  let profile = "{\"capacity\":{" +
    names
    .map(n => {
      let value = if n == "max_aggregate_string_bytes" {
        string_limit.unwrap()
      } else if n.contains("max_analytic_") {
        analytic_limit.unwrap()
      } else if n == "max_nested_value_bytes" {
        nested_bytes.unwrap_or(host_limit)
      } else if n == "max_nested_value_depth" {
        nested_depth.unwrap_or(host_limit)
      } else {
        host_limit
      }
      "\"" + n + "\":" + value.to_string()
    })
    .join(",") +
    ",\"version\":\"actql-capacity-host-policy/0.1\"}" +
    (if text_policy {
      ",\"text_time_evaluation\":{\"max_input_codepoints\":1000,\"max_input_utf8_bytes\":1000,\"max_output_bytes\":1000,\"max_pattern_bytes\":1000,\"max_replacements\":1000,\"version\":\"actql-text-time-host-policy/0.1\"}"
    } else {
      ""
    }) +
    "}"
  let profile = if calendar {
    profile.replace(
      old="\"capacity\":",
      new="\"calendar\":{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"table_bytes_cid\":\"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca\",\"tzdb_version\":\"test-fixture\",\"version\":\"actql-calendar-selection/0.1\"},\"capacity\":",
    )
  } else {
    profile
  }
  let body = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"host_policy_profile\":" +
    profile +
    ",\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  // Hashing constructs admitted fixture input, never an expected identity.
  let body = body.replace(
    old="\"contract_registry\":[]",
    new="\"contract_registry\":" + registry_entries,
  )
  let body = body.replace(
    old="\"connector_catalogs\":[]",
    new="\"connector_catalogs\":" + catalog_entries,
  )
  let body = body.replace(
    old="\"schema_snapshots\":[]",
    new="\"schema_snapshots\":" + snapshot_entries,
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
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let selected_calendar = if calendar && calendar_material {
    Some(
      @environment.admit_calendar_profile(
        @environment.read_calendar_selection(environment, 1000).unwrap(),
        @utf8.encode(
          "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
        ),
        {
          max_bytes: 1000,
          max_nodes: 100,
          max_depth: 8,
          max_zones: 1,
          max_transitions: 0,
        },
      ).unwrap(),
    )
  } else {
    None
  }
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let generated_mixed = @wire.check_mixed_claims(
    generated_proofs.map(proof => @wire.program_proof_witness(proof)),
    [],
    {
      max_entities: 100,
      max_references: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let generated_claims = @wire.check_mixed_program_claims(
    generated_mixed,
    generated_proofs,
    { max_witnesses: 100, max_references: 100, },
  ).unwrap()
  let generated_sources = @host.bind_claim_sources(generated_claims, [], {
    max_entries: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let join_sources = if second_join_capacity {
    Some(
      local_join_capacity_fixture(
        environment,
        host_limit,
        second_join_step,
        proofs=if generated_proof_stage == 1 { generated_proofs } else { [] },
      ) catch {
        _ => abort("invalid join test material")
      },
    )
  } else {
    None
  }
  // No capacity claims are needed by this scalar derive. This is fixture
  // material, not an empty-evidence fallback for arbitrary Programs.
  let sequence_sources = if second_sequence_capacity {
    Some(
      local_sequence_capacity_fixture(
        environment,
        host_limit,
        second_sequence_step,
        output_proof=sequence_output_proof,
      ) catch {
        _ => abort("invalid sequence test material")
      },
    )
  } else {
    None
  }
  let materials = Array::makei(stage_count, stage => {
    // Known fixture topology: first has one visit; second imports first twice
    // plus its own pipeline. Do not pre-check the Program to construct inputs
    // to the entry being tested, which would hide its rejection behavior.
    Array::makei(if stage == 1 { 3 } else { 1 }, visit => {
      if (
          (stage == sequence_capacity_stage && visit == 0) ||
          (stage == 1 && visit > 0 && sequence_capacity_stage == 0)
        ) &&
        sequence_sources is Some(sequence_sources) {
        @context.CapacityMaterial::{
          sources: sequence_sources,
          consumers: [
            @capacity.Sequence(step=second_sequence_step, matches=0, output=1),
          ],
        }
      } else if stage == 1 && visit == 0 && join_sources is Some(join_sources) {
        @context.CapacityMaterial::{
          sources: join_sources,
          consumers: [@capacity.Join(step=second_join_step, output=0)],
        }
      } else {
        @context.CapacityMaterial::{
          sources: if (
              (stage == generated_proof_stage && visit == 0) ||
              (stage == 1 && visit > 0 && generated_proof_stage == 0)
            ) &&
            !generated_proofs.is_empty() {
            generated_sources
          } else {
            sources
          },
          consumers: [],
        }
      }
    })
  })
  if through_check {
    let value = check(
      program,
      environment,
      supplied,
      materials,
      { text_time, veca: false, },
      { rela: true, sga: false, tea, calendar, text_rank: false, },
      source_limits_fixture(
        stage_count +
        extra_step_budget +
        (if generated_rows is Some(_) { 1 } else { 0 }),
      ),
      max_work=budget.work,
      max_bytes=budget.bytes,
      max_nodes=budget.nodes,
      max_depth=budget.depth,
      numeric_profile~,
      calendar=selected_calendar,
    )
    checked_results.push(value)
    return (
      value.identity,
      value.requirements,
      value.gates,
      value.contracts,
      value.units,
    )
  }
  construct_local(
    program,
    supplied,
    if through_catalog {
      {
        wire: environment,
        locations: Some(Array::makei(stage_count, _ => [])),
      }
    } else {
      { wire: environment, locations: None, }
    },
    materials,
    { text_time, veca: false, },
    { rela: true, sga: false, tea, calendar, text_rank: false, },
    source_limits_fixture(
      stage_count + (if generated_rows is Some(_) { 1 } else { 0 }),
    ),
    budget,
    calendar=selected_calendar,
  )
}

///|
fn supplied_fixture(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
test "effective Parameters do not replace the Unit definition identity" {
  let default_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (default_identity, _, _, _, defaults) = local_construction_fixture(
    default_budget,
    parameters=true,
  )
  for (text, same) in [("{\"n\":1}", true), ("{\"n\":2}", false)] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (identity, _, _, _, units) = local_construction_fixture(
      budget,
      parameters=true,
      supplied=Some(supplied_fixture(text)),
    )
    assert_eq(units[0].definition_cid, defaults[0].definition_cid)
    assert_eq(units[0].contracts_cid, defaults[0].contracts_cid)
    assert_eq(
      @context.program_identity_definition_cid(identity),
      @context.program_identity_definition_cid(default_identity),
    )
    assert_eq(
      @context.program_identity_parameter_values_cid(identity) ==
      @context.program_identity_parameter_values_cid(default_identity),
      same,
    )
  }
  for text in ["{\"n\":null}", "{\"n\":\"1\"}", "{\"unknown\":1}"] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    try
      local_construction_fixture(
        budget,
        parameters=true,
        supplied=Some(supplied_fixture(text)),
      )
    catch {
      LocalConstructionFailure::Source(_) => ()
      _ => fail("binding failure must be reported at source preparation")
    } noraise {
      _ => fail("invalid supplied values cannot produce Units")
    }
    assert_eq(
      (budget.work, budget.bytes, budget.nodes),
      (10000000, 1000000, 100000),
    )
  }
}

///|
fn local_identity_fixture(
  second_stage? : Bool = false,
) -> @context.ProgramSourceIdentity raise LocalConstructionFailure {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  local_construction_fixture(budget, second_stage~).0
}

///|
test "source to Unit construction shares total hash limits and fails atomically" {
  for second_stage in [false, true] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (_, _, _, _, units) = local_construction_fixture(budget, second_stage~)
    assert_eq(units.length(), if second_stage { 2 } else { 1 })
    let work = 10000000 - budget.work
    let bytes = 1000000 - budget.bytes
    let nodes = 100000 - budget.nodes
    let exact = IdentityBudget::{ work, bytes, nodes, depth: 100, }
    let (_, _, _, _, repeated) = local_construction_fixture(
      exact,
      second_stage~,
    )
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    assert_eq(repeated[0].definition_cid, units[0].definition_cid)
    for
      short in [
        IdentityBudget::{ work: work - 1, bytes, nodes, depth: 100, },
        IdentityBudget::{ work, bytes: bytes - 1, nodes, depth: 100, },
        IdentityBudget::{ work, bytes, nodes: nodes - 1, depth: 100, },
      ] {
      let before = (short.work, short.bytes, short.nodes)
      try local_construction_fixture(short, second_stage~) catch {
        _ => ()
      } noraise {
        _ => fail("aggregate shortage must reject the entire construction")
      }
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
  }
}

///|
test "two Stage construction binds Result aliases to the earlier Unit" {
  let identity = local_identity_fixture(second_stage=true)
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (requirements, gates, contracts) = prepare_owned_closure(identity, budget)
  let before = (budget.work, budget.bytes, budget.nodes)
  let units = build_units(contracts, requirements, gates, budget)
  assert_eq(units.length(), 2)
  assert_eq(units[0].imports.length(), 0)
  assert_eq(units[1].imports.length(), 2)
  assert_eq(units[1].gates.length(), 1)
  assert_true(units[1].imports[0] != units[1].imports[1])
  let owner = @context.stage_requirement_owner(requirements)
  let incoming = @context.incoming_links_requirements(owner)
  let expected : Map[String, String] = Map([])
  for i in 0..<@context.program_incoming_count(incoming) {
    match @context.program_incoming_at(incoming, i).unwrap().requirement {
      @context.Result(name, producer, _) => {
        assert_true(physical_equal(producer, units[0].source))
        let row = @context.identify_result_import_type(
            owner, i, 10000, 1000, 100,
          )
          .unwrap()
          .unwrap()
        let writer = @encode.hashing_writer(10000, 1000, 100)
        emit_result_interface(
          name,
          "local",
          "first",
          units[0].definition_cid,
          "out",
          @context.result_import_type_cid(row),
          writer,
        )
        expected[name] = "sha256:" + @encode.finish_hash(writer)
      }
      _ => ()
    }
  }
  // Authored rows precedes again; canonical interface order follows input name.
  assert_eq(units[1].imports[0], expected["again"])
  assert_eq(units[1].imports[1], expected["rows"])
  let used = before.0 - budget.work
  let short = IdentityBudget::{
    work: used - 1,
    bytes: before.1,
    nodes: before.2,
    depth: 100,
  }
  try build_units(contracts, requirements, gates, short) catch {
    _ => ()
  } noraise {
    _ => fail("a late Unit failure must not expose a partial Unit array")
  }
}

///|
test "owned construction shares its prefix and retains exact Local owners" {
  let identity = local_identity_fixture()
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (requirements, gates, contracts) = prepare_owned_closure(identity, budget)
  assert_true(
    physical_equal(@context.core_contract_identity(contracts), identity),
  )
  assert_true(
    physical_equal(
      @context.program_incoming_gates_owner(gates),
      @context.stage_requirement_owner(requirements),
    ),
  )
  let consumed = 10000000 - budget.work
  let exact = IdentityBudget::{
    work: consumed,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let _ = prepare_owned_closure(identity, exact)
  assert_eq(exact.work, 0)
  let short = IdentityBudget::{
    work: consumed - 1,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let rejected = try {
    let _ = prepare_owned_closure(identity, short)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(short.work, consumed - 1)
  let bytes = 1000000 - budget.bytes
  let nodes = 100000 - budget.nodes
  let exact_hash = IdentityBudget::{ work: consumed, bytes, nodes, depth: 100, }
  let _ = prepare_owned_closure(identity, exact_hash)
  assert_eq((exact_hash.work, exact_hash.bytes, exact_hash.nodes), (0, 0, 0))
  for
    limited in [
      IdentityBudget::{ work: consumed, bytes: bytes - 1, nodes, depth: 100, },
      IdentityBudget::{ work: consumed, bytes, nodes: nodes - 1, depth: 100, },
    ] {
    let before = (limited.work, limited.bytes, limited.nodes)
    let rejected = try {
      let _ = prepare_owned_closure(identity, limited)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_eq((limited.work, limited.bytes, limited.nodes), before)
  }
  let units = build_units(contracts, requirements, gates, budget)
  assert_eq(units.length(), 1)
  assert_true(
    physical_equal(
      units[0].source,
      @context.program_identity_stage_at(identity, 0).unwrap(),
    ),
  )
  assert_eq(units[0].imports.length(), 0)
  assert_eq(units[0].gates.length(), 0)
  assert_true(units[0].contracts_cid != units[0].definition_cid)
  let other_identity = local_identity_fixture()
  let other_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, other_gates, other_contracts) = prepare_owned_closure(
    other_identity, other_budget,
  )
  for
    (candidate_contracts, candidate_gates) in [
      (other_contracts, gates),
      (contracts, other_gates),
    ] {
    let before = (budget.work, budget.bytes, budget.nodes)
    let rejected = try {
      let _ = build_units(
        candidate_contracts, requirements, candidate_gates, budget,
      )
      false
    } catch {
      UnitBuildFailure::ForeignOwner => true
      _ => false
    }
    assert_true(rejected)
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
  }
}

///|
test "equal Program identity does not permit substituting profile resolution owners" {
  let identity = local_identity_fixture()
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (requirements, gates, _) = prepare_owned_closure(identity, budget)
  let second_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, second_contracts) = prepare_owned_closure(identity, second_budget)
  let unselected = @context.collect_core_contracts(identity, {
    max_work: 10000000,
    max_roots: 10000,
    max_bodies: 10000,
    max_edges: 10000,
  }).unwrap()
  for contracts in [second_contracts, unselected] {
    assert_true(
      physical_equal(@context.core_contract_identity(contracts), identity),
    )
    let before = (budget.work, budget.bytes, budget.nodes)
    try build_units(contracts, requirements, gates, budget) catch {
      UnitBuildFailure::ForeignOwner => ()
      _ => fail("expected an owner mismatch")
    } noraise {
      _ => fail("independent profile resolutions cannot be substituted")
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
  }
}
