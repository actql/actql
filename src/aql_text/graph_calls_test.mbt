///|
test "named Graph calls lower through ordinary Program admission" {
  let text =
    #|AQL '0.1'; PROGRAM 'graph-call' { STAGE s {
    #|  INPUT g = {"carrier":"graph"};
    #|  DATA reached = FROM g |> reach(start: "A", direction: "out", max_depth: 2);
    #|  RESULT r = {"from":"reached"};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  match parse(text, limits()) {
    Ok(_) => ()
    Err(error) => fail(@debug.to_string(error))
  }
}

///|
test "named nested selector keeps its producer role" {
  let text =
    #|AQL '0.1'; PROGRAM 'graph-call' { STAGE s {
    #|  INPUT g = {"carrier":"graph"};
    #|  DATA selected = FROM g |> subgraph(nodes: {from: g, id: "node_id"});
    #|  RESULT r = {"from":"selected"};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  match parse(text, limits()) {
    Ok(_) => ()
    Err(error) => fail(@debug.to_string(error))
  }
}

///|
test "named graph list retains repeated references" {
  let text =
    #|AQL '0.1'; PROGRAM 'graph-call' { STAGE s {
    #|  INPUT g = {"carrier":"graph"};
    #|  DATA average = mean_graphs(with: [g, g], weights: [1, 1],
    #|    support: {nodes: 0.5, edges: 0.5},
    #|    properties: {nodes: {}, edges: {}});
    #|  RESULT r = {"from":"average"};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  match parse(text, limits()) {
    Ok(_) => ()
    Err(error) => fail(@debug.to_string(error))
  }
}

///|
test "named argument source span and measured limits remain bounded" {
  let text =
    #|AQL '0.1'; PROGRAM 'graph-call' { STAGE s {
    #|  INPUT g = {"carrier":"graph"};
    #|  DATA reached = FROM g |> reach(start: "A", direction: "out", max_depth: 2);
    #|  RESULT r = {"from":"reached"};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  let parsed = parse(text, limits(), source_path="named-graph.aql").unwrap()
  let root = @decode.open_object(@syntax.program_body(program(parsed))).unwrap()
  let stage = @decode.element_at(@decode.required(root, "stages").unwrap(), 0).unwrap()
  let step = @decode.element_at(
    @decode.required(@decode.open_object(stage).unwrap(), "steps").unwrap(),
    0,
  ).unwrap()
  let reach = @decode.required(@decode.open_object(step).unwrap(), "reach").unwrap()
  let start = @decode.required(@decode.open_object(reach).unwrap(), "start").unwrap()
  let origin = @builder.origin(source(parsed), start).unwrap()
  assert_eq(@origin.kind(origin), @origin.Authored)
  assert_eq(@origin.span(origin).source_path, "named-graph.aql")
  assert_eq(@origin.span(origin).start_line, 3)
  let syntax_nodes = usage(parsed, SyntaxNodes)
  assert_true(
    parse(text, {
      ..limits(),
      frontend: { ..limits().frontend, max_syntax_nodes: syntax_nodes, },
    })
    is Ok(_),
  )
  assert_true(
    parse(text, {
      ..limits(),
      frontend: { ..limits().frontend, max_syntax_nodes: syntax_nodes - 1, },
    })
    is Err(_),
  )
  let work = usage(parsed, LoweringWork)
  assert_true(
    parse(text, {
      ..limits(),
      frontend: { ..limits().frontend, max_lowering_work: work - 1, },
    })
    is Err(_),
  )
}

///|
test "named Graph call and existing OP share the Program identity" {
  let named =
    #|AQL '0.1'; PROGRAM 'identity' { STAGE s {
    #|  INPUT g = {"carrier":"graph"};
    #|  DATA reached = FROM g |> reach(start: "A", direction: "out", max_depth: 2);
    #|  RESULT r = {"from":"reached"};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  let existing =
    #|AQL '0.1'; PROGRAM 'identity' { STAGE s {
    #|  INPUT g = {"carrier":"graph"};
    #|  DATA reached = FROM g |> OP reach {"start":"A","direction":"out","max_depth":2};
    #|  RESULT r = {"from":"reached"};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  let named_program = program(parse(named, limits()).unwrap())
  let existing_program = program(parse(existing, limits()).unwrap())
  assert_eq(
    identity_projection(named_program),
    identity_projection(existing_program),
  )
}
