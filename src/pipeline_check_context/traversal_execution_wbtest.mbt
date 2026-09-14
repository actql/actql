///|
fn traversal_checked_fixture(
  emission : String,
) -> (@pipeline.CheckedPipeline, @step_bounds.TraversalLimits) raise {
  let pipeline = @pipeline.check_carriers(
    asof_test_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"dst\":2}]},\"as\":\"seed\"},{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"seed\",\"source\":\"id\",\"target\":\"dst\",\"fields\":[]}},\"as\":\"g\"},{\"traverse\":{\"start\":{\"ids\":[1]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":3,\"emit\":\"" +
      emission +
      "\"}}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 3,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let policy = sequence_limit_policy(false)
  let wires : Array[@wire.WireWitness] = []
  let artifacts : Array[(Bytes, String)] = []
  for
    (field, unit, suffix) in [
      ("max_graph_paths", "paths", ":paths"),
      ("max_graph_output_rows", "rows", ""),
    ] {
    let host = @host.create(@policy.ceiling(policy, field).unwrap(), {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap()
    let out = @encode.writer(4096, 100, 10)
    @host.emit(host, out)
    let text = @encode.finish(out)
    wires.push(
      @wire.admit(@wire_utf8.encode(text), @host.cid(host), {
        max_bytes: 4096,
        max_nodes: 100,
        max_depth: 10,
      }).unwrap(),
    )
    // Independently specified Host-only limit: the seven-row ceiling is not a
    // claim that seven rows were produced, nor a graph-input size restriction.
    let prefix = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      text +
      "],\"effective_max\":7,\"enforcement\":\"engine_atomic\""
    let tail = ",\"subject_ref\":\"traverse:checked-step:2" +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @fixture_sha.hex(@wire_utf8.encode(prefix + tail))
    artifacts.push(
      (
        @wire_utf8.encode(
          prefix + ",\"resolved_limit_cid\":\"" + cid + "\"" + tail,
        ),
        cid,
      ),
    )
  }
  let mixed = @wire.check_mixed_claims(wires, artifacts, {
    max_entities: 20,
    max_references: 100,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 20,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let applications = @step_bounds.prepare_derived_applications(
    pipeline,
    claims,
    { max_work: 10000, max_input_work: 10000, max_operand_work: 10000, },
  ).unwrap()
  let limits = @step_bounds.check_traversal_limits(
    pipeline,
    2,
    sources,
    applications,
    policy,
    0,
    1,
    max_work=1000,
  ).unwrap()
  (pipeline, limits)
}

///|
test "traversal execution retains separate path and output limits with exact owners" {
  for emission in ["nodes", "paths"] {
    let (pipeline, limits) = traversal_checked_fixture(emission)
    let (foreign, foreign_limits) = traversal_checked_fixture(emission)
    let policy = @step_bounds.traversal_limit_policy(limits)
    let step = @pipeline.step_at(pipeline, 2).unwrap()
    let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let mut found = 0
    for index in 0..<@pipeline.operation_obligations_count(group) {
      let requirement = @pipeline.operation_obligations_at(group, index).unwrap()
      guard requirement
        is @pipeline.TraverseRequirement(ResolveTraversalResources) else {
        continue
      }
      found += 1
      let site : OperationRequirementSite = {
        stage: 1,
        producer_visit: 2,
        step: 2,
        group: 0,
        index,
        pipeline,
        obligations: group,
        requirement,
      }
      guard traversal_limits_check(site, limits, policy)
        is Ok(TraversalLimits(check)) else {
        fail("retained traversal limits")
      }
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.step, step))
      assert_true(physical_equal(check.limits, limits))
      for
        (scope, unit, suffix) in [
          (@step_bounds.SearchPaths, @derivation.Paths, ":paths"),
          (@step_bounds.TraversalScope::OutputRows, @derivation.Rows, ""),
        ] {
        let claim = @step_bounds.traversal_limit_claim(check.limits, scope)
        assert_eq(
          @wire.limit_subject(claim),
          "traverse:checked-step:2" + suffix,
        )
        assert_eq(@derivation.minimum_unit(@wire.limit_minimum(claim)), unit)
        assert_eq(@derivation.minimum_value(@wire.limit_minimum(claim)), 7L)
        assert_eq(@wire.limit_enforcement(claim), @wire.EngineAtomic)
        assert_true(
          physical_equal(
            claim,
            @step_bounds.traversal_limit_claim(limits, scope),
          ),
        )
      }
      assert_eq(
        operation_execution_phase(TraversalLimits(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(TraversalLimits(check)),
        RejectOperationOutput,
      )
      for
        changed in [
          { ..site, pipeline: foreign, },
          { ..site, step: 1, },
          { ..site, group: 1, },
          { ..site, index: -1, },
          {
            ..site,
            requirement: @pipeline.TraverseRequirement(AdmitTraversalGraph),
          },
        ] {
        assert_true(
          traversal_limits_check(changed, limits, policy)
          is Err(ForeignOccurrence(_)),
        )
      }
      assert_true(
        traversal_limits_check(site, foreign_limits, policy)
        is Err(ForeignOccurrence(_)),
      )
      // Even equal policy content is not the retained policy owner.
      assert_eq(@policy.cid(policy), @policy.cid(sequence_limit_policy(false)))
      assert_true(
        traversal_limits_check(site, limits, sequence_limit_policy(false))
        is Err(ForeignOccurrence(_)),
      )
    }
    assert_eq(found, 1)
  }
}
