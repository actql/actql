///|
fn join_policy() -> @policy.Policy {
  let fields = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  let body = "{" +
    fields.map(name => "\"" + name + "\":1").join(",") +
    ",\"version\":\"actql-capacity-host-policy/0.1\"}"
  // Independent policy identity shared with the fixed Host/Graph fixtures.
  @policy.admit(
    @utf8.encode(body),
    "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
fn wire_text(wire : @wire.WireWitness) -> String raise {
  let writer = @encode.writer(20000, 1000, 30)
  @wire.emit(wire, writer)
  @encode.finish(writer)
}

///|
// Integrity-valid application claims, including intentionally inapplicable lists.
// This does not use product output as the expected consumer acceptance result.
fn join_limit_sources(
  apps : Array[@capacity_program_step.StepBound],
  mode : Int,
  limit_steps? : Array[Int] = [0],
) -> @host.HostSources raise {
  let policy = join_policy()
  let host = @host.create(
    @policy.ceiling(
      policy,
      if mode == 3 {
        "max_temporal_output_rows"
      } else {
        "max_relation_output_rows"
      },
    ).unwrap(),
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let writer = @encode.writer(4096, 100, 10)
  @host.emit(host, writer)
  let host_wire = @wire.admit(
    @utf8.encode(@encode.finish(writer)),
    @host.cid(host),
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let proofs = apps.map(app => @capacity_program_step.checked_proof(app))
  let wires = proofs.map(proof => @wire.program_proof_witness(proof))
  wires.push(host_wire)
  let candidates = if mode == 1 {
    [host_wire]
  } else if mode == 2 {
    [wires[2]]
  } else if mode == 4 {
    [host_wire, wires[0]]
  } else {
    [host_wire, wires[2]]
  }
  candidates.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
  let texts : Array[String] = []
  let mut maximum = 9007199254740991L
  for candidate in candidates {
    texts.push(wire_text(candidate))
    if @wire.value(candidate) < maximum {
      maximum = @wire.value(candidate)
    }
  }
  let prefix = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    texts.join(",") +
    "],\"effective_max\":" +
    maximum.to_string() +
    ",\"enforcement\":\"" +
    (if mode == 5 { "unit_preflight" } else { "engine_atomic" }) +
    "\""
  let artifacts : Array[(Bytes, String)] = []
  for step in limit_steps {
    let suffix = ",\"subject_ref\":\"" +
      (if mode == 6 {
        "join:checked-step:1:output"
      } else {
        "join:checked-step:" + step.to_string() + ":output"
      }) +
      "\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}"
    let id = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
    let bytes = @utf8.encode(
      prefix + ",\"resolved_limit_cid\":\"" + id + "\"" + suffix,
    )
    artifacts.push((bytes, id))
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
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
}

///|
test "join output consumers require applicable Host and all available Program candidates" {
  for family in ["join", "cross_join", "interval_join"] {
    let (left, lb) = join_operand(2)
    let (right, rb) = join_operand(3)
    let p = join_pipeline(left, right, family, "inner")
    let host_only = join_limit_sources([lb, rb], 1)
    let parent_applications = @capacity_program_step.check_applications(
      @host.source_claims(host_only),
      [lb, rb],
      max_work=100,
    ).unwrap()
    assert_true(
      @capacity_program_step.check_join_limit(
        p,
        0,
        host_only,
        parent_applications,
        join_policy(),
        0,
        max_work=4,
      )
      is Ok(_),
    )
    let claim = proof("actql.bound.join-output", 6, "{\"op\":\"source\"}", inputs=[
      bound_id(lb),
      bound_id(rb),
    ])
    let app = @capacity_program_step.check_with_inputs(
      p,
      0,
      claim,
      [lb, rb],
      max_input_work=2,
    ).unwrap()
    let apps = [lb, rb, app]
    for mode in 0..<7 {
      let source = join_limit_sources(apps, mode)
      let program = @capacity_program_step.check_applications(
        @host.source_claims(source),
        apps,
        max_work=100,
      ).unwrap()
      let result = @capacity_program_step.check_join_limit(
        p,
        0,
        source,
        program,
        join_policy(),
        0,
        max_work=6,
      )
      match mode {
        0 => {
          let checked = result.unwrap()
          assert_eq(
            @arithmetic.minimum_value(
              @wire.limit_minimum(
                @capacity_program_step.join_limit_claim(checked),
              ),
            ),
            1L,
          )
          assert_eq(@capacity_program_step.join_limit_work(checked), 6)
          assert_true(
            physical_equal(
              @capacity_program_step.join_limit_pipeline(checked),
              p,
            ),
          )
          assert_true(
            physical_equal(
              @capacity_program_step.join_limit_program(checked),
              program,
            ),
          )
          assert_true(
            physical_equal(
              @capacity_program_step.join_limit_sources(checked),
              source,
            ),
          )
          assert_true(
            @capacity_program_step.check_join_limit(
              p,
              0,
              source,
              program,
              join_policy(),
              0,
              max_work=5,
            )
            is Err(WorkLimit),
          )
          assert_true(
            @capacity_program_step.check_join_limit(
              p,
              0,
              join_limit_sources(apps, 0),
              program,
              join_policy(),
              0,
              max_work=6,
            )
            is Err(ForeignClaims),
          )
          assert_true(
            @capacity_program_step.check_join_limit(
              p,
              0,
              source,
              program,
              join_policy(),
              1,
              max_work=6,
            )
            is Err(MissingLimit),
          )
          assert_true(
            @capacity_program_step.check_join_limit(
              p,
              -1,
              source,
              program,
              join_policy(),
              0,
              max_work=6,
            )
            is Err(InvalidStep),
          )
          assert_true(
            @capacity_program_step.check_join_limit(
              p,
              0,
              source,
              program,
              join_policy(),
              0,
              max_work=-1,
            )
            is Err(InvalidLimits),
          )
          assert_true(
            @capacity_program_step.check_join_limit(
              left,
              0,
              source,
              program,
              join_policy(),
              0,
              max_work=6,
            )
            is Err(WrongOperation),
          )
          let body = match family {
            "cross_join" => "\"with\":\"rows\""
            "interval_join" =>
              "\"with\":\"rows\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}"
            _ => "\"with\":\"rows\",\"kind\":\"inner\",\"on\":\"id\""
          }
          for guard_value in [1, 100] {
            let guarded = pipeline(
              "[{\"" +
              family +
              "\":{" +
              body +
              ",\"max_output_rows\":" +
              guard_value.to_string() +
              "}}]",
            )
            assert_true(
              @capacity_program_step.check_join_limit(
                guarded,
                0,
                source,
                program,
                join_policy(),
                0,
                max_work=6,
              )
              is Err(UnresolvedAuthorSource),
            )
          }
        }
        1 => assert_true(result is Err(MissingProgramCandidate(_)))
        2 => assert_true(result is Err(MissingHostCandidate))
        3 | 4 => assert_true(result is Err(CandidateScopeMismatch(_)))
        5 => assert_true(result is Err(WrongEnforcement))
        6 => assert_true(result is Err(SubjectMismatch))
        _ => fail("unexpected mode")
      }
    }
  }
}
