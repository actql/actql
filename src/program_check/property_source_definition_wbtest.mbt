///|
fn source_graph_domain(program : CheckedProgram, step : Int) -> String {
  guard @pipeline.step_at(program.units[0].pipeline, step).unwrap().output
    is @carrier.GraphValue(graph) else {
    abort("expected current Graph")
  }
  @carrier.property_graph_domain(@carrier.graph_property_definition(graph))
}

///|
fn source_graph_steps(name : String, derived? : Bool = false) -> String {
  (if derived {
    "{\"from\":\"" + name + "\",\"filter\":\"id > 0\",\"as\":\"derived\"},"
  } else {
    ""
  }) +
  "{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"" +
  (if derived { "derived" } else { name }) +
  "\",\"key\":[\"id\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"id\",\"to\":\"id\"}]}}]}],\"edges\":[]},\"as\":\"g\"},{\"match_nodes\":{\"definition\":\"N\",\"fields\":[\"id\"],\"where\":{\"literal\":true}}}"
}

///|
test "current Graph keeps original Source declaration and selected Catalog owner through MATCH" {
  let program = checked_direct_program_fixture(
    graph_steps=source_graph_steps("remote"),
    property_graph=true,
  )
  let pipeline = program.units[0].pipeline
  guard @pipeline.input_contract_at(pipeline, 0)
    is Some(@pipeline.SourceViewInput(stage, name, declaration, owner)) else {
    fail("original Source definition owner was discarded")
  }
  assert_eq(name, "remote")
  assert_eq(
    @decode.tree_index(declaration, declaration),
    @decode.tree_index(@syntax.stage_body(stage), declaration),
  )
  let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
  let steps = @decode.required(body, "steps").unwrap()
  assert_eq(
    @decode.tree_index(steps, @pipeline.source(pipeline)),
    @decode.tree_index(steps, steps),
  )
  assert_true(
    physical_equal(
      @pipeline.input_at(pipeline, 0).unwrap().1,
      @environment.carrier_schema_value(
        @environment.source_view_carrier_schema(owner),
      ),
    ),
  )
  let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
  assert_eq(publication_policy_source_count(policy), 1)
  assert_eq(publication_policy_carrier_step_at(policy, 0).unwrap().step, 1)
  assert_true(
    @pipeline.step_at(pipeline, 1).unwrap().operation is GraphMatch(_),
  )
  // Independently SHA-256 the authored constructor and fixed Catalog input
  // preimage; no compiler output was used to produce this expected identity.
  assert_eq(
    source_graph_domain(program, 0),
    "sha256:4e99c7ad4487c68499e66d81ddef818b42053f8b6f439ca65dcfcd975a850cc3",
  )
}

///|
test "Source Graph domain ignores DATA aliases but retains changed producer semantics" {
  let first = checked_direct_program_fixture(
    graph_steps=source_graph_steps("remote"),
    property_graph=true,
  )
  let renamed = checked_direct_program_fixture(
    input_name="renamed",
    graph_steps=source_graph_steps("renamed"),
    property_graph=true,
  ) catch {
    Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
      fail("renamed Source pipeline: " + @debug.to_string(issue.kind))
    error => raise error
  }
  let changed = checked_direct_program_fixture(
    graph_steps=source_graph_steps("remote", derived=true),
    property_graph=true,
  ) catch {
    Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
      fail("changed Source pipeline: " + @debug.to_string(issue.kind))
    error => raise error
  }
  assert_eq(source_graph_domain(first, 0), source_graph_domain(renamed, 0))
  assert_false(source_graph_domain(first, 0) == source_graph_domain(changed, 1))
}
