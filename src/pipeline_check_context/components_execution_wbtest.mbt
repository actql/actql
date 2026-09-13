///|
fn components_checked_fixture() -> (
  @pipeline.CheckedPipeline,
  @step_bounds.ComponentsLimits,
) raise {
  let pipeline = @pipeline.check_carriers(
    asof_test_cursor(
      (
        #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"id":1,"dst":2},{"id":2,"dst":3},{"id":3,"dst":1}]},"as":"seed"},{"graph":{"nodes":{"from":"seed","id":"id","fields":[]},"edges":{"from":"seed","source":"id","target":"dst","fields":[]}},"as":"g"},{"components":{"kind":"strong"}}]
      ),
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
  let proofs : Array[@wire.ProgramProofClaim] = []
  for
    (step, law, unit, parent) in [
      (0, "actql.bound.values", "rows", None),
      (1, "actql.bound.graph-nodes", "nodes", Some(0)),
      (2, "actql.bound.components-input-nodes", "nodes", Some(1)),
      (2, "actql.bound.components-nodes", "rows", Some(1)),
    ] {
    proofs.push(
      components_fixture_proof(
        law,
        3L,
        "{\"op\":\"source\"}",
        reference="checked-step:" + step.to_string(),
        unit~,
        inputs=match parent {
          None => []
          Some(i) => [@wire.cid(@wire.program_proof_witness(proofs[i]))]
        },
      ),
    )
  }
  let policy = sequence_limit_policy(false)
  let host = @host.create(
    @policy.ceiling(policy, "max_graph_output_rows").unwrap(),
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let writer = @encode.writer(4096, 100, 10)
  @host.emit(host, writer)
  let host_wire = @wire.admit(
    @wire_utf8.encode(@encode.finish(writer)),
    @host.cid(host),
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let wires = proofs.map(p => @wire.program_proof_witness(p))
  wires.push(host_wire)
  let artifacts : Array[(Bytes, String)] = []
  for
    (unit, suffix, candidates) in [
      ("nodes", ":nodes", [wires[2]]),
      ("rows", "", [wires[3], host_wire]),
    ] {
    candidates.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
    let texts : Array[String] = []
    for candidate in candidates {
      let writer = @encode.writer(20000, 1000, 30)
      @wire.emit(candidate, writer)
      texts.push(@encode.finish(writer))
    }
    let prefix = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      texts.join(",") +
      "],\"effective_max\":3,\"enforcement\":\"engine_atomic\""
    let tail = ",\"subject_ref\":\"components:checked-step:2" +
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
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
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
  let limits = @step_bounds.check_components_limits(
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
test "components execution retains node and row limits and rejects foreign owners" {
  let (pipeline, limits) = components_checked_fixture()
  let (foreign, _) = components_checked_fixture()
  let step = @pipeline.step_at(pipeline, 2).unwrap()
  let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  let mut found = false
  for index in 0..<@pipeline.operation_obligations_count(group) {
    let requirement = @pipeline.operation_obligations_at(group, index).unwrap()
    if requirement is @pipeline.GraphRequirement(ResolveGraphResources) {
      found = true
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
      guard components_limits_check(site, limits, sequence_limit_policy(false))
        is Ok(ComponentsLimits(check)) else {
        fail("limits binding")
      }
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.step, step))
      assert_true(physical_equal(check.limits, limits))
      for
        (scope, suffix) in [
          (@step_bounds.InputNodes, ":nodes"),
          (OutputRows, ""),
        ] {
        let claim = @step_bounds.components_limit_claim(check.limits, scope)
        assert_eq(
          @wire.limit_subject(claim),
          "components:checked-step:2" + suffix,
        )
        assert_eq(@derivation.minimum_value(@wire.limit_minimum(claim)), 3L)
        assert_eq(@wire.limit_enforcement(claim), @wire.EngineAtomic)
        assert_true(
          physical_equal(
            claim,
            @step_bounds.components_limit_claim(limits, scope),
          ),
        )
      }
      assert_eq(
        operation_execution_phase(ComponentsLimits(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(ComponentsLimits(check)),
        RejectOperationOutput,
      )
      for
        changed in [
          { ..site, pipeline: foreign, },
          { ..site, step: 1, },
          { ..site, index: 99, },
          {
            ..site,
            requirement: @pipeline.GraphRequirement(ValidateGraphData),
          },
        ] {
        assert_true(
          components_limits_check(changed, limits, sequence_limit_policy(false))
          is Err(ForeignOccurrence(_)),
        )
      }
      assert_true(
        components_limits_check(site, limits, sequence_limit_policy(true))
        is Err(ForeignOccurrence(2)),
      )
    }
  }
  assert_true(found)
}
