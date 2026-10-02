///|
fn component_limit_artifact(
  candidates : Array[@wire.WireWitness],
  unit : String,
  suffix : String,
  operation? : String = "components",
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
  let tail = ",\"subject_ref\":\"" +
    operation +
    ":checked-step:0" +
    suffix +
    "\",\"unit\":\"" +
    unit +
    "\",\"version\":\"actql-resolved-limit/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(prefix + tail))
  (@utf8.encode(prefix + ",\"resolved_limit_cid\":\"" + id + "\"" + tail), id)
}

///|
test "TRAIL ledger covers unused branches and binds retained MATCH input ownership" {
  let p = input_bound_pipeline(
    "[{\"traverse\":{\"start\":{\"ids\":[{\"domain\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"definition\":\"N\",\"key\":[\"a\"]}]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2,\"path_mode\":\"trail\",\"emit\":\"paths\"},\"as\":\"unused\"},{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]},\"from\":\"g\"}]",
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
    is Err(MissingTraversalApplications(0)),
  )
  let id = @wire.cid(
    @input.bound_witness(@input.input_bound(initial_graph, 0, Nodes).unwrap()),
  )
  let rows = graph_proof(
    "actql.bound.match-nodes",
    1L,
    "{\"op\":\"source\"}",
    reference="checked-step:1",
    inputs=[id],
  )
  let paths = graph_host_wire(policy, "max_graph_paths")
  let host_wire = graph_host_wire(policy, "max_graph_output_rows")
  let sources = sources(
    0,
    policy,
    proofs=[rows],
    extra_wires=[host_wire, paths],
    extra_limits=[
      component_limit_artifact([paths], "paths", ":paths", operation="traverse"),
      component_limit_artifact([host_wire], "rows", "", operation="traverse"),
    ],
  )
  let graph = @input.check(p, sources, policy, caps()).unwrap()
  let preparation : @program.PreparationLimits = {
    max_work: 1000,
    max_input_work: 1000,
    max_operand_work: 1000,
  }
  assert_true(
    @program.prepare_derived_applications(
      p,
      @host.source_claims(sources),
      preparation,
    )
    is Err(MissingDependency(_, _)),
  )
  assert_true(
    @program.prepare_derived_applications(
      p,
      @host.source_claims(sources),
      preparation,
      graph_inputs=Some(initial_graph),
    )
    is Err(ForeignGraphInputs),
  )
  assert_true(
    @program.prepare_derived_applications(
      input_bound_pipeline("[]"),
      @host.source_claims(sources),
      preparation,
      graph_inputs=Some(graph),
    )
    is Err(ForeignGraphInputs),
  )
  let input = @program.GraphInput(@input.input_bound(graph, 0, Nodes).unwrap())
  let apps = [rows].map(proof => {
    @program.check_with_sources(p, 1, proof, [input]).unwrap()
  })
  let program = @program.check_applications(
    @host.source_claims(sources),
    apps,
    max_work=100,
  ).unwrap()
  let limit = @program.check_traversal_limits(
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
  let prepared = prepared_coverage(p, sources, [
    Traversal(step=0, paths=2, output=3),
  ])
  let prepared_program = @capacity_graph_preflight.source_coverage_program(
    @capacity_graph_preflight.application_coverage_sources(prepared),
  )
  assert_true(
    physical_equal(
      @program.application_claims(prepared_program),
      @host.source_claims(sources),
    ),
  )
  let traversals = @program.check_traversal_applications(
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
      @program.traversal_application_at(traversals, 0).unwrap(),
      limit,
    ),
  )
  assert_true(@program.traversal_application_at(traversals, -1) is None)
  assert_eq(@program.traversal_unconsumed_limit_count(traversals), 2)
  let work = @program.traversal_application_work(traversals)
  assert_eq(work, 11)
  assert_true(
    @program.check_traversal_applications(
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
    @program.check_traversal_applications(
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
    @program.check_traversal_applications(
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
    @program.check_traversal_applications(
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
    @program.check_traversal_complete(
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
    @program.check_traversal_applications(
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
    is Err(MissingTraversalApplications(0)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      other_program,
      sequence,
      traversals=Some(traversals),
      max_work=100,
    )
    is Err(ForeignProgram),
  )
  let covered = @capacity_graph_preflight.check_application_coverage(
    graph,
    program,
    sequence,
    traversals=Some(traversals),
    max_work=100,
  ).unwrap()
  let exact = @capacity_graph_preflight.application_coverage_work(covered)
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      traversals=Some(traversals),
      max_work=exact,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      traversals=Some(traversals),
      max_work=exact - 1,
    )
    is Err(Consumer(WorkLimit)),
  )
  assert_true(
    physical_equal(
      @capacity_graph_preflight.consumer_coverage_traversals(
        @capacity_graph_preflight.application_coverage_consumers(covered),
      ).unwrap(),
      traversals,
    ),
  )
}
