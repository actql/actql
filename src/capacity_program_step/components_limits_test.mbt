///|
test "component guard admission preserves owner and exact work boundaries" {
  let (p, apps) = component_fixture(authored=true)
  let sources = component_sources(apps, 0)
  let program = @capacity_program_step.check_applications(
    @host.source_claims(sources),
    apps,
    max_work=100,
  ).unwrap()
  let guards = bound_context(p, None)
  let check = fn(bound, work) {
    @capacity_program_step.check_components_limits(
      p,
      2,
      sources,
      program,
      join_policy(),
      0,
      1,
      guards=Some(bound),
      max_work=work,
    )
  }
  let selected = check(guards, 1000).unwrap()
  assert_eq(
    @capacity_program_step.components_limit_guard_value(selected),
    Some(1L),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.components_limit_guards(selected).unwrap(),
      guards,
    ),
  )
  let work = @capacity_program_step.components_limit_work(selected)
  assert_true(check(guards, work) is Ok(_))
  assert_true(check(guards, work - 1) is Err(_))
  let (foreign, _) = component_fixture(authored=true)
  assert_true(
    check(bound_context(foreign, None), 1000) is Err(ForeignGuardOwner),
  )
  let collection = @capacity_program_step.check_components_applications(
    p,
    sources,
    program,
    join_policy(),
    [selected],
    max_work=1000,
  ).unwrap()
  assert_true(
    @capacity_program_step.components_application_guard_bindings_match(
      collection, guards,
    ),
  )
  assert_false(
    @capacity_program_step.components_application_guard_bindings_match(
      collection,
      bound_context(foreign, None),
    ),
  )
}

///|
fn component_fixture(
  authored? : Bool = false,
) -> (@pipeline.CheckedPipeline, Array[@capacity_program_step.StepBound]) {
  let p = graph_measure_pipeline(
    "[" +
    graph_seed("n", 3) +
    ",{\"graph\":{\"nodes\":{\"from\":\"n\",\"id\":\"src\",\"fields\":[]},\"edges\":{\"from\":\"n\",\"source\":\"src\",\"target\":\"dst\",\"fields\":[]}},\"as\":\"g\"}," +
    (if authored {
      "{\"components\":{\"kind\":\"weak\",\"max_output_rows\":1}}"
    } else {
      "{\"components\":{\"kind\":\"strong\"}}"
    }) +
    "]",
  )
  let seed = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.values", 3L, "{\"op\":\"source\"}"),
  ).unwrap()
  let graph = @capacity_program_step.check_with_inputs(
    p,
    1,
    measure_proof(1, "actql.bound.graph-nodes", "nodes", 3L, seed),
    [seed],
  ).unwrap()
  let nodes = @capacity_program_step.check_with_inputs(
    p,
    2,
    measure_proof(2, "actql.bound.components-input-nodes", "nodes", 3L, graph),
    [graph],
  ).unwrap()
  let rows = @capacity_program_step.check_with_inputs(
    p,
    2,
    measure_proof(2, "actql.bound.components-nodes", "rows", 3L, graph),
    [graph],
  ).unwrap()
  (p, [seed, graph, nodes, rows])
}

///|
// All variants have valid wire integrity; errors are about applicability,
// not hashes. Candidate values deliberately include a redundant bound of 3
// alongside the selected Host ceiling of 1.
fn component_sources(
  apps : Array[@capacity_program_step.StepBound],
  mode : Int,
) -> @host.HostSources raise {
  let policy = join_policy()
  let host = @host.create(
    @policy.ceiling(
      policy,
      if mode == 3 {
        "max_relation_output_rows"
      } else {
        "max_graph_output_rows"
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
  let wires = proofs.map(p => @wire.program_proof_witness(p))
  wires.push(host_wire)
  let node_candidates = if mode == 4 { [wires[1]] } else { [wires[2]] }
  let row_candidates = match mode {
    1 => [host_wire]
    2 => [wires[3]]
    5 => [host_wire, wires[0]]
    _ => [host_wire, wires[3]]
  }
  let artifacts : Array[(Bytes, String)] = []
  for
    (candidates, unit, suffix) in [
      (node_candidates, "nodes", ":nodes"),
      (row_candidates, "rows", ""),
    ] {
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
      (if mode == 6 { "unit_preflight" } else { "engine_atomic" }) +
      "\""
    let tail = ",\"subject_ref\":\"components:checked-step:" +
      (if mode == 7 { "1" } else { "2" }) +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let id = "sha256:" + @sha.hex(@utf8.encode(prefix + tail))
    artifacts.push(
      (
        @utf8.encode(prefix + ",\"resolved_limit_cid\":\"" + id + "\"" + tail),
        id,
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
  @host.bind_claim_sources(claims, [policy], {
    max_entries: 30,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
}

///|
test "components limits bind both measures and reject inapplicable or omitted candidates" {
  let (p, apps) = component_fixture()
  for mode in 0..<8 {
    let sources = component_sources(apps, mode)
    let program = @capacity_program_step.check_applications(
      @host.source_claims(sources),
      apps,
      max_work=100,
    ).unwrap()
    let result = @capacity_program_step.check_components_limits(
      p,
      2,
      sources,
      program,
      join_policy(),
      0,
      1,
      max_work=100,
    )
    match mode {
      0 => {
        let v = result.unwrap()
        let work = @capacity_program_step.components_limit_work(v)
        assert_true(
          physical_equal(
            @capacity_program_step.components_limit_program(v),
            program,
          ),
        )
        assert_true(
          physical_equal(
            @capacity_program_step.components_limit_sources(v),
            sources,
          ),
        )
        assert_true(
          physical_equal(@capacity_program_step.components_limit_pipeline(v), p),
        )
        assert_eq(
          @capacity_program_step.components_limit_index(v, InputNodes),
          0,
        )
        assert_eq(
          @capacity_program_step.components_limit_index(v, OutputRows),
          1,
        )
        assert_true(
          @capacity_program_step.check_components_limits(
            p,
            2,
            sources,
            program,
            join_policy(),
            0,
            1,
            max_work=work,
          )
          is Ok(_),
        )
        assert_true(
          @capacity_program_step.check_components_limits(
            p,
            2,
            sources,
            program,
            join_policy(),
            0,
            1,
            max_work=work - 1,
          )
          is Err(Candidates(OutputRows, WorkLimit)),
        )
        assert_true(
          @capacity_program_step.check_components_limits(
            p,
            2,
            sources,
            program,
            join_policy(),
            1,
            0,
            max_work=100,
          )
          is Err(SubjectMismatch(InputNodes)),
        )
        assert_true(
          @capacity_program_step.check_components_limits(
            p,
            1,
            sources,
            program,
            join_policy(),
            0,
            1,
            max_work=100,
          )
          is Err(WrongOperation),
        )
      }
      1 =>
        assert_true(
          result is Err(Candidates(OutputRows, MissingProgramCandidate(_))),
        )
      2 =>
        assert_true(result is Err(Candidates(OutputRows, MissingHostCandidate)))
      3 | 5 =>
        assert_true(
          result is Err(Candidates(OutputRows, CandidateScopeMismatch(_))),
        )
      4 =>
        assert_true(
          result is Err(Candidates(InputNodes, CandidateScopeMismatch(_))),
        )
      6 => assert_true(result is Err(WrongEnforcement(InputNodes)))
      7 => assert_true(result is Err(SubjectMismatch(InputNodes)))
      _ => fail("unlisted mode")
    }
  }
  let (authored, authored_apps) = component_fixture(authored=true)
  let sources = component_sources(authored_apps, 0)
  let program = @capacity_program_step.check_applications(
    @host.source_claims(sources),
    authored_apps,
    max_work=100,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_components_limits(
      authored,
      2,
      sources,
      program,
      join_policy(),
      0,
      1,
      max_work=100,
    )
    is Err(UnresolvedAuthorSource),
  )
}
