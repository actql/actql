///|
fn consumer_pipeline(
  unknown_graph : Bool,
  joins? : Bool = false,
  tail? : String = "",
  sequence_guards? : String = "",
  parameters? : @parameter.Declarations? = None,
) -> @pipeline.CheckedPipeline {
  let text = "[{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"a\",\"where\":\"true\"},{\"as\":\"b\",\"where\":\"true\"}],\"within\":1,\"overlap\":\"allow\",\"contiguity\":\"adjacent\"" +
    sequence_guards +
    "},\"from\":\"rows\"}" +
    (if joins {
      ",{\"join\":{\"with\":\"rows\",\"kind\":\"inner\",\"on\":\"id\"},\"from\":\"rows\"}"
    } else {
      ""
    }) +
    tail +
    "]"
  let root = @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 4096,
      max_nodes: 100,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
  ).unwrap()
  let graph = if unknown_graph {
    @carrier.unknown_carrier(GraphKind)
  } else {
    @carrier.graph(
      @contract.primitive(StringType, nullable=false),
      @carrier.unknown_rows(),
      @carrier.unknown_rows(),
      labels=None,
      max_labels=0,
      max_label_bytes=0,
    ).unwrap()
  }
  let row = @schema.from_object(
    @contract.object_contract(
      [("id", @contract.primitive(NumberType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    ).unwrap(),
  ).unwrap()
  @pipeline.check_carriers(
    root,
    [("g", graph), ("rows", @carrier.relation(@carrier.typed_rows(row)))],
    parameters,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn sequence_consumers(
  p : @pipeline.CheckedPipeline,
  source : @host.HostSources,
) -> @sequence.Applications {
  let selected = policy(false)
  let app = @sequence.check_host_limits(
    p,
    0,
    source,
    selected,
    2,
    3,
    max_work=4,
  ).unwrap()
  @sequence.check_applications(p, source, selected, [app], max_work=100).unwrap()
}

///|
test "Graph and sequence consumer coverage accounts for every limit without conflating scopes" {
  for unknown_graph in [false, true] {
    let p = consumer_pipeline(unknown_graph)
    let source = combined_sources(false)
    let graph = @capacity_graph_preflight.check(
      p,
      source,
      policy(false),
      caps(),
    ).unwrap()
    let sequence = sequence_consumers(p, source)
    assert_eq(@capacity_graph_preflight.unconsumed_limit_count(graph), 2)
    assert_eq(@sequence.unconsumed_limit_count(sequence), 2)
    let combined = @capacity_graph_preflight.check_consumer_coverage(
      graph,
      sequence,
      max_work=8,
    ).unwrap()
    assert_eq(@capacity_graph_preflight.consumer_coverage_work(combined), 8)
    assert_true(
      physical_equal(
        @capacity_graph_preflight.consumer_coverage_graph(combined),
        graph,
      ),
    )
    assert_true(
      physical_equal(
        @capacity_graph_preflight.consumer_coverage_sequence(combined),
        sequence,
      ),
    )
    assert_true(
      @capacity_graph_preflight.check_consumer_coverage(
        graph,
        sequence,
        max_work=7,
      )
      is Err(WorkLimit),
    )
    assert_true(
      @capacity_graph_preflight.check_consumer_coverage(
        graph,
        sequence,
        max_work=-1,
      )
      is Err(InvalidLimits),
    )
    let program = @program.check_applications(
      @host.source_claims(source),
      [],
      max_work=100,
    ).unwrap()
    assert_true(
      @capacity_graph_preflight.check_source_coverage(
        graph,
        program,
        max_work=100,
      )
      is Ok(_),
    )
  }
}

///|
test "combined consumer coverage rejects unused limits and foreign identities" {
  let p = consumer_pipeline(true)
  let source = combined_sources(true)
  let graph = @capacity_graph_preflight.check(p, source, policy(false), caps()).unwrap()
  let sequence = sequence_consumers(p, source)
  assert_true(
    @capacity_graph_preflight.check_consumer_coverage(
      graph,
      sequence,
      max_work=9,
    )
    is Err(UnconsumedLimit(4)),
  )
  let foreign_pipeline = sequence_consumers(consumer_pipeline(true), source)
  assert_true(
    @capacity_graph_preflight.check_consumer_coverage(
      graph,
      foreign_pipeline,
      max_work=9,
    )
    is Err(ForeignPipeline),
  )
  let foreign_source = sequence_consumers(p, combined_sources(true))
  assert_true(
    @capacity_graph_preflight.check_consumer_coverage(
      graph,
      foreign_source,
      max_work=9,
    )
    is Err(ForeignSources),
  )
  let empty_pipeline = fixture_pipeline(false)
  let source = sources(8, policy(false))
  let graph = @capacity_graph_preflight.check(
    empty_pipeline,
    source,
    policy(false),
    caps(),
  ).unwrap()
  let other_policy = @sequence.check_applications(
    empty_pipeline,
    source,
    policy(true),
    [],
    max_work=10,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_consumer_coverage(
      graph,
      other_policy,
      max_work=10,
    )
    is Err(ForeignPolicy),
  )
}

///|
test "Graph-only collections compose with empty sequence coverage" {
  let p = fixture_pipeline(true)
  let selected = policy(false)
  let source = sources(0, selected)
  let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
  let sequence = @sequence.check_applications(
    p,
    source,
    selected,
    [],
    max_work=2,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_consumer_coverage(
      graph,
      sequence,
      max_work=4,
    )
    is Ok(_),
  )
}

///|
test "join consumption joins Graph and sequence without hiding omitted or unused limits" {
  for extra in [false, true] {
    let p = consumer_pipeline(true, joins=true)
    let source = combined_sources(extra, joins=true)
    let selected = policy(false)
    let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
    let sequence = sequence_consumers(p, source)
    let program = @program.check_applications(
      @host.source_claims(source),
      [],
      max_work=100,
    ).unwrap()
    let index = if extra { 5 } else { 4 }
    let join_limit = @program.check_join_limit(
      p,
      1,
      source,
      program,
      selected,
      index,
      max_work=100,
    ).unwrap()
    let joined = @program.check_join_applications(
      p,
      source,
      program,
      selected,
      [join_limit],
      max_work=100,
    ).unwrap()
    let result = @capacity_graph_preflight.check_consumer_coverage(
      graph,
      sequence,
      joins=Some(joined),
      max_work=if extra { 10 } else { 9 },
    )
    if extra {
      assert_true(result is Err(UnconsumedLimit(4)))
    } else {
      let covered = result.unwrap()
      assert_true(
        physical_equal(
          @capacity_graph_preflight.consumer_coverage_joins(covered).unwrap(),
          joined,
        ),
      )
      assert_eq(@capacity_graph_preflight.consumer_coverage_work(covered), 9)
      assert_true(
        @capacity_graph_preflight.check_consumer_coverage(
          graph,
          sequence,
          max_work=9,
        )
        is Err(UnconsumedLimit(4)),
      )
      assert_true(
        @capacity_graph_preflight.check_consumer_coverage(
          graph,
          sequence,
          joins=Some(joined),
          max_work=8,
        )
        is Err(WorkLimit),
      )
      let foreign = consumer_pipeline(true, joins=true)
      let foreign_limit = @program.check_join_limit(
        foreign,
        1,
        source,
        program,
        selected,
        index,
        max_work=100,
      ).unwrap()
      let foreign_joined = @program.check_join_applications(
        foreign,
        source,
        program,
        selected,
        [foreign_limit],
        max_work=100,
      ).unwrap()
      assert_true(
        @capacity_graph_preflight.check_consumer_coverage(
          graph,
          sequence,
          joins=Some(foreign_joined),
          max_work=9,
        )
        is Err(ForeignPipeline),
      )
    }
  }
}
