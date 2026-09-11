///|
fn component_limit_artifact(
  candidates : Array[@wire.WireWitness],
  unit : String,
  suffix : String,
) -> (Bytes, String) raise {
  let sorted = candidates.copy()
  sorted.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
  let texts : Array[String] = []
  for wire in sorted {
    let writer = @encode.writer(20000, 1000, 30)
    @wire.emit(wire, writer)
    texts.push(@encode.finish(writer))
  }
  let prefix = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    texts.join(",") +
    "],\"effective_max\":1,\"enforcement\":\"engine_atomic\""
  let tail = ",\"subject_ref\":\"components:checked-step:0" +
    suffix +
    "\",\"unit\":\"" +
    unit +
    "\",\"version\":\"actql-resolved-limit/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(prefix + tail))
  (@utf8.encode(prefix + ",\"resolved_limit_cid\":\"" + id + "\"" + tail), id)
}

///|
test "components ledger covers every step and integrates both limits with Graph preflight" {
  // Components is deliberately not the final current branch.
  let p = input_bound_pipeline(
    "[{\"components\":{\"kind\":\"weak\"},\"as\":\"unused\"},{\"node_rows\":true,\"from\":\"g\"}]",
  )
  let policy = policy(false)
  let initial = sources(0, policy)
  let initial_graph = @input.check(p, initial, policy, caps()).unwrap()
  let empty_program = @program.check_applications(
    @host.source_claims(initial),
    [],
    max_work=100,
  ).unwrap()
  let empty_sequence = @sequence.check_applications(
    p,
    initial,
    policy,
    [],
    max_work=100,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      initial_graph,
      empty_program,
      empty_sequence,
      max_work=100,
    )
    is Err(MissingComponentsApplications(0)),
  )
  let id = @wire.cid(
    @input.bound_witness(@input.input_bound(initial_graph, 0, Nodes).unwrap()),
  )
  let nodes = graph_proof(
    "actql.bound.components-input-nodes",
    1L,
    "{\"op\":\"source\"}",
    unit="nodes",
    inputs=[id],
  )
  let rows = graph_proof(
    "actql.bound.components-nodes",
    1L,
    "{\"op\":\"source\"}",
    inputs=[id],
  )
  let host = @host.create(
    @policy.ceiling(policy, "max_graph_output_rows").unwrap(),
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let writer = @encode.writer(4096, 100, 10)
  @host.emit(host, writer)
  let host_wire = @wire.admit(
    @utf8.encode(@encode.finish(writer)),
    @host.cid(host),
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let sources = sources(
    0,
    policy,
    proofs=[nodes, rows],
    extra_wires=[host_wire],
    extra_limits=[
      component_limit_artifact(
        [@wire.program_proof_witness(nodes)],
        "nodes",
        ":nodes",
      ),
      component_limit_artifact(
        [host_wire, @wire.program_proof_witness(rows)],
        "rows",
        "",
      ),
    ],
  )
  let graph = @input.check(p, sources, policy, caps()).unwrap()
  let input = @program.GraphInput(@input.input_bound(graph, 0, Nodes).unwrap())
  let apps = [nodes, rows].map(proof => {
    @program.check_with_sources(p, 0, proof, [input]).unwrap()
  })
  let program = @program.check_applications(
    @host.source_claims(sources),
    apps,
    max_work=100,
  ).unwrap()
  let limit = @program.check_components_limits(
    p,
    0,
    sources,
    program,
    policy,
    2,
    3,
    max_work=100,
  ).unwrap()
  let list = [limit]
  let components = @program.check_components_applications(
    p,
    sources,
    program,
    policy,
    list,
    max_work=100,
  ).unwrap()
  list.clear()
  assert_true(
    physical_equal(
      @program.components_application_at(components, 0).unwrap(),
      limit,
    ),
  )
  assert_true(@program.components_application_at(components, -1) is None)
  assert_eq(@program.components_unconsumed_limit_count(components), 2)
  let work = @program.components_application_work(components)
  assert_eq(work, 11)
  assert_true(
    @program.check_components_applications(
      p,
      sources,
      program,
      policy,
      [limit],
      max_work=work,
    )
    is Ok(_),
  )
  assert_true(
    @program.check_components_applications(
      p,
      sources,
      program,
      policy,
      [limit],
      max_work=work - 1,
    )
    is Err(WorkLimit),
  )
  assert_true(
    @program.check_components_applications(
      p,
      sources,
      program,
      policy,
      [],
      max_work=100,
    )
    is Err(MissingApplication(0)),
  )
  assert_true(
    @program.check_components_applications(
      p,
      sources,
      program,
      policy,
      [limit, limit],
      max_work=100,
    )
    is Err(DuplicateApplication(1)),
  )
  assert_true(
    @program.check_components_complete(
      p,
      sources,
      program,
      policy,
      [limit],
      max_work=100,
    )
    is Err(UnconsumedLimits(2)),
  )
  let other_program = @program.check_applications(
    @host.source_claims(sources),
    apps,
    max_work=100,
  ).unwrap()
  assert_true(
    @program.check_components_applications(
      p,
      sources,
      other_program,
      policy,
      [limit],
      max_work=100,
    )
    is Err(ForeignProgram(0)),
  )
  let sequence = @sequence.check_applications(
    p,
    sources,
    policy,
    [],
    max_work=100,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      max_work=100,
    )
    is Err(MissingComponentsApplications(0)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      other_program,
      sequence,
      components=Some(components),
      max_work=100,
    )
    is Err(ForeignProgram),
  )
  let covered = @capacity_graph_preflight.check_application_coverage(
    graph,
    program,
    sequence,
    components=Some(components),
    max_work=100,
  ).unwrap()
  let exact = @capacity_graph_preflight.application_coverage_work(covered)
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      components=Some(components),
      max_work=exact,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      components=Some(components),
      max_work=exact - 1,
    )
    is Err(Consumer(WorkLimit)),
  )
  assert_true(
    physical_equal(
      @capacity_graph_preflight.consumer_coverage_components(
        @capacity_graph_preflight.application_coverage_consumers(covered),
      ).unwrap(),
      components,
    ),
  )
}
