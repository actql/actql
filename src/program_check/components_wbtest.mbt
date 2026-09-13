///|
// Input claims for the fixed source topology below, built without running check.
fn local_components_capacity_fixture(
  environment : @environment.WireEnvironment,
  rows : Int,
) -> @host.HostSources raise @encode.EncodeFailure {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let proofs : Array[@wire.ProgramProofClaim] = []
  for
    (step, law, unit, parent) in [
      (0, "actql.bound.values", "rows", None),
      (2, "actql.bound.graph-nodes", "nodes", Some(0)),
      (3, "actql.bound.components-input-nodes", "nodes", Some(1)),
      (3, "actql.bound.components-nodes", "rows", Some(1)),
    ] {
    proofs.push(
      sequence_fixture_proof(
        law,
        step,
        rows,
        match parent {
          None => []
          Some(i) => [@wire.cid(@wire.program_proof_witness(proofs[i]))]
        },
        "{\"op\":\"source\"}",
        unit~,
      ),
    )
  }
  let ceiling = @policy.ceiling(policy, "max_graph_output_rows").unwrap()
  let host = @host.create(ceiling, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let writer = @encode.writer(10000, 1000, 30)
  @host.emit(host, writer)
  let host_wire = @wire.admit(
    @utf8.encode(@encode.finish(writer)),
    @host.cid(host),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let wires = proofs.map(p => @wire.program_proof_witness(p))
  wires.push(host_wire)
  let limits : Array[(Bytes, String)] = []
  for
    (unit, suffix, candidates, maximum) in [
      ("nodes", ":nodes", [wires[2]], rows.to_int64()),
      (
        "rows",
        "",
        [wires[3], host_wire],
        @policy.ceiling_value(ceiling).min(rows.to_int64()),
      ),
    ] {
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
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"components:checked-step:3" +
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
test "formal components close their selected capacity through Result imports" {
  for kind in ["weak", "strong"] {
    for rows in [0, 3] {
      let identities : Array[String] = []
      for cap in [1, 1000] {
        let programs : Array[CheckedProgram] = []
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          sga=true,
          graph_output_limit=Some(cap),
          graph_construction_limit=Some(1000),
          components_capacity_rows=Some(rows),
          generated_rows=Some(
            if rows == 0 {
              "[]"
            } else {
              "[{\"id\":1},{\"id\":2},{\"id\":3}]"
            },
          ),
          producer_suffix=",{\"graph\":{\"nodes\":{\"from\":\"seed\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\",\"fields\":[]}},\"as\":\"g\"},{\"components\":{\"kind\":\"" +
            kind +
            "\"}},{\"select\":[{\"id\":\"node_id\"},{\"value\":\"component_size\"}],\"as\":\"projected\"}",
          producer_result_from="projected",
          extra_step_budget=3,
        )
        assert_eq(programs.length(), 1)
        let program = programs[0]
        identities.push(unit_definition_cid(program, 0).unwrap())
        assert_eq(unit_count(program), 2)
        let operations = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut found = 0
        for index in 0..<@context.operation_closure_count(operations) {
          if @context.operation_closure_at(operations, index)
            is Some(ExecutionCheck(ComponentsLimits(check))) {
            found += 1
            assert_eq(check.site.step, 3)
            assert_true(
              physical_equal(
                check.site.pipeline,
                unit_pipeline(program, 0).unwrap(),
              ),
            )
            assert_true(
              physical_equal(
                @step_bounds.components_limit_pipeline(check.limits),
                check.site.pipeline,
              ),
            )
            for scope in [@step_bounds.InputNodes, OutputRows] {
              let claim = @step_bounds.components_limit_claim(
                check.limits,
                scope,
              )
              assert_eq(
                @derivation.minimum_value(@wire.limit_minimum(claim)),
                (if scope == @step_bounds.InputNodes {
                  rows
                } else {
                  rows.min(cap)
                }).to_int64(),
              )
              assert_eq(@wire.limit_enforcement(claim), @wire.EngineAtomic)
            }
          }
        }
        assert_eq(found, 3)
      }
      assert_eq(identities[0], identities[1])
    }
  }
}
