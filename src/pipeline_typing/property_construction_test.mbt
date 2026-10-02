///|
fn property_pipeline(
  node_id : Int,
  output_name : String,
  extra : String,
  input_name? : String = "seed",
) -> @pipeline_typing.CheckedPipeline {
  @pipeline_typing.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":" +
      node_id.to_string() +
      "}]},\"as\":\"" +
      input_name +
      "\"}," +
      "{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"" +
      input_name +
      "\",\"key\":[\"id\"]}],\"edges\":[]},\"as\":\"" +
      output_name +
      "\"" +
      extra +
      "}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
}

///|
fn property_pipeline_domain(
  pipeline : @pipeline_typing.CheckedPipeline,
) -> String {
  guard @pipeline_typing.output_carrier(pipeline)
    is Some(@carrier.GraphValue(graph)) else {
    abort("Graph required")
  }
  @carrier.property_graph_domain(
    @carrier.graph_property_definition(graph).unwrap(),
  )
}

///|
test "renaming a resolved producer alias cannot change the constructor definition domain" {
  assert_eq(
    property_pipeline_domain(property_pipeline(1, "g", "")),
    property_pipeline_domain(
      property_pipeline(1, "g", "", input_name="renamed"),
    ),
  )
}

///|
test "common constructor issues an independently derived producer definition domain excluding outer alias and metadata" {
  let first = property_pipeline(1, "g", "")
  // Independent canonical preimage: constructor + {body: VALUES declaration,
  // dependencies: []} + version. Neither product output nor a Run is hashed
  // to generate this literal; SHA-256 was computed separately with Node.
  assert_eq(
    property_pipeline_domain(first),
    "sha256:0b9c0345677606c4a3e2fbac68f9eaf42a4c050b7b977a60049ae286821f45c6",
  )
  assert_eq(
    property_pipeline_domain(
      property_pipeline(
        1, "renamed", ",\"meta\":{\"note\":\"different location\"}",
      ),
    ),
    property_pipeline_domain(first),
  )
  assert_true(
    property_pipeline_domain(property_pipeline(2, "g", "")) !=
    property_pipeline_domain(first),
  )
  let step = @pipeline_typing.step_at(first, 1).unwrap()
  guard step.operation is PropertyGraphConstruction(inputs~, checked~) else {
    fail("new constructor owner")
  }
  assert_eq(inputs, [Step(0)])
  assert_eq(@pipeline_typing.input_occurrence_count(step), 1)
  assert_true(
    @pipeline_typing.input_occurrence_at(step, 0)
    is Some({ role: Sample(0), target: Step(0), }),
  )
  assert_eq(@graph.property_construction_pending_count(checked), 5)
  assert_eq(
    @pipeline_typing.operation_profile_at(step.operation, 0),
    Some(PropertyGraph),
  )
  assert_eq(
    @graph.property_construction_pending_at(checked, 4),
    Some(ResolvePropertyGraphProfile),
  )
  let profile_requirement = @pipeline_typing.operation_obligation_group_at(
    step.operation,
    0,
  ).unwrap()
  assert_eq(
    @pipeline_typing.operation_profile_requirement(
      @pipeline_typing.operation_obligations_at(profile_requirement, 4).unwrap(),
    ),
    Some(PropertyGraph),
  )
  assert_eq(
    @graph.property_construction_pending_at(checked, 1),
    Some(RejectDuplicateDefinitionKeys),
  )
  assert_eq(
    @graph.property_construction_pending_at(checked, 2),
    Some(ExcludeNullKeysAndMissingEndpoints),
  )
  let counts = @pipeline_typing.graph_count(first, Step(1)).unwrap()
  assert_eq(counts.nodes.unwrap().upper, 1L)
  assert_eq(counts.edges.unwrap().upper, 0L)
}

///|
test "multiple definitions preserve ordered repeated producer occurrences and independent edge schemas" {
  let pipeline = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"values":{"schema":{"id":{"type":"number","nullable":true},"src":{"type":"number","nullable":true},"dst":{"type":"number","nullable":true}},"rows":[{"id":1,"src":1,"dst":1}]},"as":"rows"},
        #| {"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"rows","key":["id"]},{"name":"Other","from":"rows","key":["id"]}],"edges":[{"name":"E","from":"rows","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}]},"as":"g"}]
      ),
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let step = @pipeline_typing.step_at(pipeline, 1).unwrap()
  guard step.operation is PropertyGraphConstruction(inputs~, checked~) else {
    fail("checked construction")
  }
  assert_eq(inputs, [Step(0), Step(0), Step(0)])
  assert_eq(@pipeline_typing.input_occurrence_count(step), 3)
  assert_eq(
    @pipeline_typing.input_occurrence_at(step, 2).unwrap().role,
    Sample(2),
  )
  assert_eq(@graph.property_construction_node_count(checked), 2)
  assert_eq(@graph.property_construction_edge_count(checked), 1)
  let count = @pipeline_typing.graph_count(pipeline, Step(1)).unwrap()
  assert_eq(count.nodes.unwrap().upper, 2L)
  assert_eq(count.edges.unwrap().upper, 1L)
}

///|
test "runtime parameter values do not enter the checked constructor definition domain" {
  let body =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":{"$param":"n"}}]},"as":"seed"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"]}],"edges":[]},"as":"g"}]
  let domains = []
  let bound_values = []
  for actual in [1, 2] {
    let declarations = @parameter.read_declarations(
      Some(
        cursor(
          "{\"n\":{\"type\":\"number\",\"default\":" + actual.to_string() + "}}",
        ),
      ),
      { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 100, },
    ).unwrap()
    let pipeline = @pipeline_typing.check_carriers(
      cursor(body),
      [],
      Some(declarations),
      None,
      limits(),
    ).unwrap()
    domains.push(property_pipeline_domain(pipeline))
    guard @parameter.bind(declarations, None, {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 100,
      })
      is Ok(Ready(values)) else {
      fail("parameter value")
    }
    bound_values.push(@parameter.stringify_values(values, 1000, 100, 10))
  }
  assert_eq(domains[0], domains[1])
  assert_true(bound_values[0] != bound_values[1])
}

///|
test "a bare external carrier is not sufficient producer definition provenance" {
  let body =
    #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"rows","key":["id"]}],"edges":[]},"as":"g"}]
  assert_true(
    @pipeline_typing.check_carriers(
      cursor(body),
      [("rows", graph_rows_input())],
      None,
      None,
      limits(),
    )
    is Err({ kind: MissingPropertyProducerDefinition, .. }),
  )
  // An old constructor is still accepted on the same declared input.
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{\"graph\":{\"source\":\"src_id\",\"target\":\"dst_id\"}}]"),
      [("rows", graph_rows_input())],
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
}

///|
test "new constructor rejects implicit legacy conversion unresolved references and conflicting outer from" {
  for
    body in [
      "[{\"property_graph\":{\"source\":\"src_id\",\"target\":\"dst_id\"},\"as\":\"g\"}]",
      "[{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"missing\",\"key\":[\"id\"]}],\"edges\":[]},\"as\":\"g\"}]",
      "[{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[],\"edges\":[]},\"as\":\"g\",\"from\":\"rows\"}]",
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor(body),
        [("rows", graph_rows_input())],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
