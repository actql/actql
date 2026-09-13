///|
fn prepared_keyed_source_context(
  changes? : Bool = false,
  artifact_rows? : Int = 1,
) -> SelectedPolicyContext raise {
  let original = keyed_sourceview_environment(changes~)
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(original, writer)
  let profile = capacity_profile(false).replace(
    old="\"max_artifact_rows\":1",
    new="\"max_artifact_rows\":" + artifact_rows.to_string(),
  )
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
  let (views, locals) = prepare_source_registrations(
    source,
    sourceview_catalog(environment),
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
  let limits = local_program_context_source_limits()
  let (wiring, _) = prepare_sourceview_program(views, locals, limits).unwrap()
  let prepared = @stage_results.bind_prepared_program(wiring, None, limits).unwrap()
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
  let materials = capacity_materials_fixture(prepared).0
  for i in 0..<materials[0].length() {
    materials[0][i] = {
      sources,
      consumers: [@capacity.Join(step=1, output=0)],
    }
  }
  prepare_sourceview_context(
    views,
    locals,
    None,
    materials,
    limits,
    local_context_limits(),
  ).unwrap()
}

///|
test "prepared keyed acquisition retains its actual producer bound" {
  let selected = prepared_keyed_source_context()
  let closure = checked_capacity(
    parameter_context(
      stage_context_at(
        wired_stage_contexts(reconciled_wiring(policy_context(selected))),
        0,
      ).unwrap(),
    ),
  )
  let coverage = @capacity.application_closure_at(closure, 0).unwrap()
  let applications = @capacity.source_coverage_program(
    @capacity.application_coverage_sources(coverage),
  )
  let bound = @program.application_at(applications, 0).unwrap()
  let pipeline = @program.checked_pipeline(bound)
  let rows = @program.check_target_rows(pipeline, @pipeline.Step(0), bound, 100).unwrap()
  let caps : @sourceviews.RequestLimits = {
    max_work: 10000000,
    max_pairs: 1000,
    values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
  }
  let result = prepare_program_sources(
    selected,
    [[rows]],
    [[(0, 0)]],
    caps,
    max_bindings=100,
    max_slots=1000,
  ).unwrap()
  let constructed = prepare_program_source_acquisitions(
    selected,
    [[(0, 0)]],
    caps,
    max_bindings=100,
    max_slots=1000,
  ).unwrap()
  let constructed_rows = @capacity.target_membership_rows(
    source_producer_at(constructed, 0, 0).unwrap(),
  )
  assert_true(
    physical_equal(@program.target_rows_bound(constructed_rows), bound),
  )
  assert_true(
    physical_equal(@program.target_rows_pipeline(constructed_rows), pipeline),
  )
  assert_eq(@program.target_rows_target(constructed_rows), @pipeline.Step(0))
  assert_eq(@program.target_rows_value(constructed_rows), 1L)
  // Construction adds one candidate selection visit; target traversal is not
  // charged again merely because it is assembled inside the boundary.
  assert_eq(source_producer_work(constructed), source_producer_work(result) + 1)
  let constructed_caps = {
    ..caps,
    max_work: source_producer_work(constructed),
  }
  assert_true(
    prepare_program_source_acquisitions(
      selected,
      [[(0, 0)]],
      constructed_caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Ok(_),
  )
  for short in [-1, 0, 1, constructed_caps.max_work - 1] {
    assert_true(
      prepare_program_source_acquisitions(
        selected,
        [[(0, 0)]],
        { ..caps, max_work: short, },
        max_bindings=100,
        max_slots=1000,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_program_source_acquisitions(
      selected,
      [],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(StageCountMismatch)),
  )
  assert_true(
    prepare_program_source_acquisitions(
      selected,
      [[]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(Stage(0, CountMismatch))),
  )
  assert_true(
    prepare_program_source_acquisitions(
      selected,
      [[(10, 0)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(InvalidVisit(0, 0))),
  )
  assert_true(
    prepare_program_source_acquisitions(
      selected,
      [[(0, 1)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(InvalidClaim(0, 0))),
  )
  let membership = source_producer_at(result, 0, 0).unwrap()
  assert_true(
    physical_equal(@capacity.target_membership_rows(membership), rows),
  )
  assert_true(
    physical_equal(@capacity.target_membership_closure(membership), closure),
  )
  assert_eq(@capacity.target_membership_coordinates(membership), (0, 0, 0))
  let limits = { ..caps, max_work: source_producer_work(result), }
  assert_true(
    prepare_program_sources(
      selected,
      [[rows]],
      [[(0, 0)]],
      limits,
      max_bindings=100,
      max_slots=1000,
    )
    is Ok(_),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [[rows]],
      [[(0, 0)]],
      { ..limits, max_work: limits.max_work - 1, },
      max_bindings=100,
      max_slots=1000,
    )
    is Err(_),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [[]],
      [[]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(_)),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [[rows]],
      [[(0, 1)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Producers(Membership(0, 0, InvalidClaim))),
  )
  assert_true(
    prepare_program_sources(
      selected,
      [[rows]],
      [[(10, 0)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Producers(Membership(0, 0, InvalidVisit))),
  )
  // Identical bytes and numeric bounds are not interchangeable Program owners.
  let other = prepared_keyed_source_context()
  assert_true(
    prepare_program_sources(
      other,
      [[rows]],
      [[(0, 0)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(_)),
  )
  let separately_checked = @program.check(pipeline, 0, keyed_sourceview_claim()).unwrap()
  let foreign_rows = @program.check_target_rows(
    pipeline,
    @pipeline.Step(0),
    separately_checked,
    100,
  ).unwrap()
  assert_true(
    prepare_program_sources(
      selected,
      [[foreign_rows]],
      [[(0, 0)]],
      caps,
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Producers(Membership(0, 0, ForeignBound))),
  )
  let checks = prepare_program_checks(
    constructed,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    preparation_limits(),
    max_policy_depth=validation_limits().max_policy_depth,
    max_requirements=validation_limits().max_requirements,
    max_regex_depth=pattern_limits().max_regex_depth,
  ).unwrap()
  let identity = prepare_program_source_identity(
    checks,
    source_preparation_limits(),
  ).unwrap()
  assert_eq(program_identity_stage_count(identity), 1)
  let contracts = collect_core_contracts(identity, {
    max_work: 1000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 100,
  }).unwrap()
  let mut join_roots = 0
  for i in 0..<core_contract_root_count(contracts) {
    let root = core_contract_root_at(contracts, i).unwrap()
    if root.site is OperationJoinCountRules(stage, visit, step) {
      assert_eq(stage, 0)
      assert_eq(step, 1)
      assert_true(
        @pipeline.step_at(
          program_identity_producer_at(identity, stage, visit).unwrap(),
          step,
        ).unwrap().operation
        is @pipeline.Join(..),
      )
      assert_eq(root.body, JoinCountRules)
      join_roots += 1
    }
  }
  assert_true(join_roots > 0)
  assert_true(stage_has_contract(contracts, 0, JoinCountRules))
}
