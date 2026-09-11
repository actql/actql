///|
test "expression slots retain unused branches and feed source-correspondent parameter indexing" {
  let root = cursor(
    (
      #|{"params":{"p":{"type":"number"}},"steps":[{"derive":{"a":"$p + amount"},"as":"unused"},{"filter":{"literal":true},"from":"rows"},{"derive":{"b":"amount + $p"}}]}
    ),
  )
  let fields = @decode.open_object(root).unwrap()
  let parameters = @parameter.read_declarations(
    @decode.lookup(fields, "params"),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let p = @pipeline_typing.check(
    @decode.lookup(fields, "steps").unwrap(),
    [("rows", schema())],
    Some(parameters),
    None,
    limits(),
  ).unwrap()
  let slots = collect_expression_slots(p, max_work=6, max_slots=3).unwrap()
  assert_true(physical_equal(expression_slots_pipeline(slots), p))
  assert_eq(expression_slot_count(slots), 3)
  assert_eq(expression_slots_work(slots), 6)
  let occurrences = []
  for i in 0..<3 {
    let slot = expression_slot_at(slots, i).unwrap()
    assert_eq(slot.step, i)
    occurrences.push(
      @expression.collect_parameter_occurrences(
        @typing.expression(slot.expression),
        max_work=100,
      ).unwrap(),
    )
  }
  let index = @parameter_refs.build(root, parameters, occurrences, {
    max_slots: 3,
    max_references: 2,
    max_pointer_units: 100,
  }).unwrap()
  assert_eq(@parameter_refs.reference_count(index), 2)
  assert_eq(
    @parameter_refs.reference_at(index, 0).unwrap().path,
    "/steps/0/derive/a/add/0",
  )
  assert_eq(
    @parameter_refs.reference_at(index, 1).unwrap().path,
    "/steps/2/derive/b/add/1",
  )
  assert_true(
    collect_expression_slots(p, max_work=5, max_slots=3) is Err(WorkLimit),
  )
  assert_true(
    collect_expression_slots(p, max_work=6, max_slots=2) is Err(SlotLimit),
  )
  assert_true(
    collect_expression_slots(p, max_work=-1, max_slots=3) is Err(InvalidLimits),
  )
  assert_true(expression_slot_at(slots, -1) is None)
  assert_true(expression_slot_at(slots, 3) is None)
}

///|
test "aggregate and analytic expressions are enumerated without field shorthand expansion" {
  for
    (steps, expected) in [
      (
        (
          #|[{"group":{"by":["id"],"aggregates":{"n":{"fn":"sum","expr":"amount","filter":"amount > 0"}}},"from":"l"}]
        ),
        2,
      ),
      (
        (
          #|[{"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"functions":{"r":{"fn":"rank"},"n":{"fn":"lag","expr":"amount"}}},"from":"l"}]
        ),
        1,
      ),
      (
        (
          #|[{"group":{"by":["id"],"aggregates":{"n":{"fn":"sum","field":"amount"}}},"from":"l"}]
        ),
        0,
      ),
    ] {
    let p = join_pipeline(steps).unwrap()
    let slots = collect_expression_slots(
      p,
      max_work=expected + 1,
      max_slots=expected,
    ).unwrap()
    assert_eq(expression_slot_count(slots), expected)
  }
  let p = @pipeline_typing.check(
    cursor("[]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let slots = collect_expression_slots(p, max_work=0, max_slots=0).unwrap()
  assert_eq(expression_slot_count(slots), 0)
  assert_eq(expression_slots_work(slots), 0)
}

///|
test "sequence expression slots retain all pattern predicates" {
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"to_events":{"id":"id","time":"amount"}},{"sequence":{"by":["id"],"id":"id","time":"amount","pattern":[{"as":"start","where":"amount > 0"},{"as":"end","where":{"literal":true}}],"within":1000,"overlap":"allow","contiguity":"adjacent"}}]
      ),
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let slots = collect_expression_slots(p, max_work=4, max_slots=2).unwrap()
  assert_eq(expression_slot_count(slots), 2)
  for i in 0..<2 {
    let slot = expression_slot_at(slots, i).unwrap()
    assert_eq(slot.step, 1)
    let e = @typing.expression(slot.expression)
    let origin = @expression.origin(e, @expression.tree(e)).unwrap()
    assert_eq(@expression.location_path(origin), [
      @source.Index(1),
      @source.Key("sequence"),
      @source.Key("pattern"),
      @source.Index(i),
      @source.Key("where"),
    ])
  }
}

///|
test "graph expression slots cover matches selectors hops and endpoints" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node_id"),
    Unqualified("source_id"),
    Unqualified("target_id"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  for
    (steps, count, work) in [
      (
        (
          #|[{"match_nodes":{"where":"true","fields":["node_id"]}}]
        ),
        1,
        2,
      ),
      (
        (
          #|[{"subgraph":{"nodes":{"where":"true"},"edges":"false"}}]
        ),
        2,
        3,
      ),
      (
        (
          #|[{"traverse":{"start":{"where":"true"},"hops":[{"direction":"in","edge_where":"true","node_where":"false"},{"direction":"out"}],"emit":"nodes"}}]
        ),
        3,
        6,
      ),
      (
        (
          #|[{"shortest_path":{"source":{"where":"true"},"target":{"where":"false"},"direction":"both","max_hops":3,"selection":"each_pair"}}]
        ),
        2,
        3,
      ),
      (
        (
          #|[{"shortest_path":{"source":1,"target":2,"direction":"both","max_hops":3}}]
        ),
        0,
        3,
      ),
    ] {
    let checked = @pipeline_typing.check_carriers(
      cursor(steps),
      [("g", graph)],
      None,
      None,
      limits(),
    )
    let p = match checked {
      Ok(p) => p
      Err(issue) => fail(steps + ": " + @debug.to_string(issue.kind))
    }
    let slots = collect_expression_slots(p, max_work=work, max_slots=count).unwrap()
    assert_eq(expression_slot_count(slots), count)
    assert_eq(expression_slots_work(slots), work)
    for i in 0..<count {
      let slot = expression_slot_at(slots, i).unwrap()
      assert_eq(slot.step, 0)
      let expression = @typing.expression(slot.expression)
      let origin = @expression.origin(expression, @expression.tree(expression)).unwrap()
      assert_true(
        @decode.tree_index(@pipeline_typing.source(p), origin.source) is Some(_),
      )
    }
    assert_true(
      collect_expression_slots(p, max_work=work - 1, max_slots=count)
      is Err(WorkLimit),
    )
  }
}
