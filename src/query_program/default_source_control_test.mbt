///|
test "valid defaults remain bound through query compilation and common checking" {
  let cursor = @wire.admit(
    @source.parse_json(
      "{\"minimum\":{\"type\":\"number\",\"default\":7}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let declarations = @parameters.read_declarations(Some(cursor), {
    max_parameters: 1024,
    max_nodes: 8192,
    max_depth: 64,
    max_text_bytes: 65536,
  }).unwrap()
  let context = {
    ..values_context(),
    parameter_declarations: Some(declarations),
  }
  let used = @query.parse_query("SELECT @minimum AS n", syntax_limits()).unwrap()
  let program = compile(used, context, construction_limits()).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    NeedsInputs(_) => fail("A valid default must satisfy its declared value")
  }
  // A default is not a use: the existing complete Program inventory rejects it.
  let unused = @query.parse_query("SELECT 1 AS n", syntax_limits()).unwrap()
  let program = compile(unused, context, construction_limits()).unwrap()
  guard @check.check_parsed(program, check_environment(), None, check_limits())
    is Rejected(diagnostic) else {
    fail("An unused declaration must be rejected")
  }
  guard @check.diagnostic_cause(diagnostic)
    is @check.LocalConstructionFailure::Source(
      @check.SourceFailure::Identity(
        References(Usage(UnusedParameter(declaration)))
      )
    ) else {
    raise @check.diagnostic_cause(diagnostic)
  }
  assert_eq(declaration.name, "minimum")
}
