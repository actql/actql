///|
test "source coverage rejects a self-consistent but unauthenticated Contract source" {
  // Fixed wire identity from capacity_witness's independent corpus.
  let text = "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"sha256:0000000000000000000000000000000000000000000000000000000000000003\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"contract_ceiling\",\"source\":{\"contract_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"field\":\"max_items\",\"kind\":\"contract\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:ae090fc6182e0c2f8f7f43269de098eaa8e13ba89c9199d3f604406e3ec39997\"}"
  let witness = @wire.admit(
    @utf8.encode(text),
    "sha256:ae090fc6182e0c2f8f7f43269de098eaa8e13ba89c9199d3f604406e3ec39997",
    { max_bytes: 4096, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let mixed = @wire.check_mixed_claims([witness], [], {
    max_entities: 10,
    max_references: 100,
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 10,
    max_references: 100,
  }).unwrap()
  let source = @host.bind_claim_sources(claims, [], {
    max_entries: 10,
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let graph = @capacity_graph_preflight.check(
    fixture_pipeline(false),
    source,
    policy(false),
    caps(),
  ).unwrap()
  let program = @program.check_applications(claims, [], max_work=2).unwrap()
  assert_true(
    @capacity_graph_preflight.check_source_coverage(graph, program, max_work=1)
    is Err(UnsupportedSource(0)),
  )
  let sequence = @sequence.check_applications(
    @capacity_graph_preflight.checked_pipeline(graph),
    source,
    policy(false),
    [],
    max_work=0,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_coverage(
      graph,
      program,
      sequence,
      max_work=10,
    )
    is Err(Source(UnsupportedSource(0))),
  )
}

///|
test "source coverage binds Program and Host checks to the same collection" {
  let p = policy(false)
  let source = sources(0, p)
  let pipeline = fixture_pipeline(true)
  let graph = @capacity_graph_preflight.check(pipeline, source, p, caps()).unwrap()
  let claims = @host.source_claims(source)
  let program = @program.check_applications(claims, [], max_work=100).unwrap()
  let n = @wire.claim_count(@wire.program_claim_arithmetic(claims))
  let checked = @capacity_graph_preflight.check_source_coverage(
    graph,
    program,
    max_work=n,
  ).unwrap()
  assert_eq(@capacity_graph_preflight.source_coverage_work(checked), n)
  assert_true(
    physical_equal(
      @capacity_graph_preflight.source_coverage_graph(checked),
      graph,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_graph_preflight.source_coverage_program(checked),
      program,
    ),
  )
  assert_true(
    @capacity_graph_preflight.check_source_coverage(
      graph,
      program,
      max_work=n - 1,
    )
    is Err(WorkLimit),
  )
  assert_true(
    @capacity_graph_preflight.check_source_coverage(graph, program, max_work=-1)
    is Err(InvalidLimits),
  )
  let other = @program.check_applications(
    @host.source_claims(sources(0, p)),
    [],
    max_work=100,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_source_coverage(graph, other, max_work=n)
    is Err(ForeignClaims),
  )
}

///|
test "source coverage does not imply consumption of unused valid limits" {
  let p = policy(false)
  let source = sources(8, p)
  let graph = @capacity_graph_preflight.check(
    fixture_pipeline(false),
    source,
    p,
    caps(),
  ).unwrap()
  let program = @program.check_applications(
    @host.source_claims(source),
    [],
    max_work=100,
  ).unwrap()
  let checked = @capacity_graph_preflight.check_source_coverage(
    graph,
    program,
    max_work=100,
  ).unwrap()
  assert_eq(
    @capacity_graph_preflight.unconsumed_limit_count(
      @capacity_graph_preflight.source_coverage_graph(checked),
    ),
    2,
  )
}
