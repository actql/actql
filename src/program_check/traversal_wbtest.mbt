///|
fn local_traversal_capacity_fixture(
  environment : @environment.WireEnvironment,
  operation_name? : String = "traverse",
  proofs? : Array[@wire.ProgramProofClaim] = [],
) -> @host.HostSources raise @encode.EncodeFailure {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let wires = proofs.map(p => @wire.program_proof_witness(p))
  let limits : Array[(Bytes, String)] = []
  for
    (field, unit, suffix) in [
      ("max_graph_paths", "paths", ":paths"),
      ("max_graph_output_rows", "rows", ""),
    ] {
    let ceiling = @policy.ceiling(policy, field).unwrap()
    let host = @host.create(ceiling, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let out = @encode.writer(10000, 1000, 30)
    @host.emit(host, out)
    let text = @encode.finish(out)
    wires.push(
      @wire.admit(@utf8.encode(text), @host.cid(host), {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 30,
      }).unwrap(),
    )
    let candidates = [wires[wires.length() - 1]]
    let mut maximum = @policy.ceiling_value(ceiling)
    if unit == "rows" && !proofs.is_empty() {
      let candidate = @wire.program_proof_witness(proofs[proofs.length() - 1])
      candidates.push(candidate)
      maximum = maximum.min(@wire.value(candidate))
    }
    candidates.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
    let texts : Array[String] = []
    for candidate in candidates {
      let writer = @encode.writer(20000, 1000, 30)
      @wire.emit(candidate, writer)
      texts.push(@encode.finish(writer))
    }
    let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      texts.join(",") +
      "],\"effective_max\":" +
      maximum.to_string() +
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"" +
      operation_name +
      ":checked-step:3" +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    limits.push(
      (
        @utf8.encode(
          body.replace(
            old="\"subject_ref\":",
            new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
          ),
        ),
        cid,
      ),
    )
  }
  let mixed = @wire.check_mixed_claims(wires, limits, {
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
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
}

///|
test "formal traversal retains producer Unit limits through imported Results" {
  for emission in ["nodes", "paths"] {
    for patterned in [false, true] {
      for empty in [false, true] {
        let programs : Array[CheckedProgram] = []
        let mode = if patterned {
          "\"hops\":[{\"direction\":\"both\"},{\"direction\":\"out\",\"edge_where\":{\"literal\":false}}]"
        } else {
          "\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2"
        }
        let suffix = ",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"traverse\":{\"start\":" +
          (if empty {
            "{\"where\":{\"literal\":false}}"
          } else {
            "{\"from\":\"seed\",\"id\":\"id\"}"
          }) +
          "," +
          mode +
          ",\"emit\":\"" +
          emission +
          "\"}},{\"select\":[{\"id\":\"start_id\"},{\"value\":\"" +
          (if emission == "nodes" { "depth" } else { "hop_count" }) +
          "\"}],\"as\":\"projected\"}"
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          sga=true,
          graph_construction_limit=Some(1000),
          traversal_capacity=true,
          generated_rows=Some(
            if empty {
              "[]"
            } else {
              "[{\"id\":1},{\"id\":2}]"
            },
          ),
          producer_expression="id",
          producer_suffix=suffix,
          producer_result_from="projected",
          extra_step_budget=3,
        )
        let program = programs[0]
        assert_eq(unit_count(program), 2)
        assert_eq(unit_traversal_limit_count(program, 0), Some(1))
        assert_eq(unit_traversal_limit_count(program, 1), Some(0))
        assert_eq(unit_traversal_limit_count(program, -1), None)
        assert_true(unit_traversal_limit_at(program, 0, -1) is None)
        assert_true(unit_traversal_limit_at(program, 0, 1) is None)
        let retained = unit_traversal_limit_at(program, 0, 0).unwrap()
        let prefix = "unit:" +
          unit_definition_cid(program, 0).unwrap() +
          "#/steps/3/traverse/"
        for
          (scope, suffix) in [
            (@step_bounds.SearchPaths, "paths"),
            (@step_bounds.TraversalScope::OutputRows, "output"),
          ] {
          let claim = traversal_limit_claim(retained, scope)
          assert_eq(@wire.limit_subject(claim), prefix + suffix)
          let original = @step_bounds.traversal_limit_claim(
            traversal_limit_selection(retained).limits,
            scope,
          )
          assert_true(@wire.limit_cid(claim) != @wire.limit_cid(original))
          assert_eq(
            @derivation.minimum_value(@wire.limit_minimum(claim)),
            @derivation.minimum_value(@wire.limit_minimum(original)),
          )
          assert_eq(
            @wire.cid(@wire.claim_at(@wire.limit_claims(claim), 0).unwrap()),
            @wire.cid(
              @wire.claim_at(
                @wire.limit_claims(original),
                @derivation.minimum_candidate_at(
                  @wire.limit_minimum(original),
                  0,
                ).unwrap().node,
              ).unwrap(),
            ),
          )
        }
        assert_eq(traversal_limit_proof_count(retained), 0)
        let closure = @context.stage_requirement_operations(
          program.requirements,
        )
        let mut bindings = 0
        let mut semantic = 0
        for i in 0..<@context.operation_closure_count(closure) {
          match @context.operation_closure_at(closure, i) {
            Some(ExecutionCheck(TraversalLimits(check))) => {
              bindings += 1
              assert_true(
                physical_equal(check.site.pipeline, program.units[0].pipeline),
              )
            }
            Some(ExecutionCheck(TraversalExecution(_))) => semantic += 1
            _ => ()
          }
        }
        assert_eq(bindings, 3)
        assert_eq(semantic, 3 * (if emission == "nodes" { 5 } else { 6 }))
      }
    }
  }
}

///|
test "formal traversal cannot omit capacity or return success after consumer failure" {
  for capacity in [false, true] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        traversal_capacity=capacity,
        generated_rows=Some("[]"),
        producer_expression="id",
        producer_suffix=",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"traverse\":{\"start\":{\"where\":{\"literal\":false}},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":1,\"emit\":\"nodes\"}},{\"select\":[{\"id\":\"start_id\"},{\"value\":\"depth\"}],\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=3,
        second_steps=if capacity {
          "[{\"select\":[\"missing\"]}]"
        } else {
          "[]"
        },
      )
    catch {
      LocalConstructionFailure::Source(_) => ()
      _ => fail("source-driven admission must reject the incomplete Program")
    } noraise {
      _ => fail("empty traversal is not a capacity exemption")
    }
    assert_eq(programs.length(), 0)
  }
}
