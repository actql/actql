///|
fn composite_nearest_context() -> Context {
  let seeds = [
    (
      "queries",
      ["tenant", "request_id", "embedding", "note"],
      (
        #|{"values":{"schema":{"tenant":{"type":"string","nullable":false},"request_id":{"type":"number","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":false}},"rows":[{"tenant":"one","request_id":1,"embedding":[1,0],"note":"original-query"}]},"as":"queries"}
      ),
    ),
    (
      "candidates",
      ["tenant", "item_id", "embedding", "body"],
      (
        #|{"values":{"schema":{"tenant":{"type":"string","nullable":false},"item_id":{"type":"number","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"body":{"type":"string","nullable":false}},"rows":[{"tenant":"one","item_id":1,"embedding":[1,0],"body":"first"},{"tenant":"two","item_id":1,"embedding":[0,1],"body":"second"}]},"as":"candidates"}
      ),
    ),
  ]
  {
    ..nearest_context(),
    inputs: seeds.map(seed => {
      relation: [{ value: seed.0, quoted: false, }],
      name: seed.0,
      source: GeneratedValues(
        @wire.admit(
          @source.parse_json(seed.2, construction_limits().source.source).unwrap(),
          construction_limits().source.tree,
        ).unwrap(),
      ),
      visible_fields: seed.1,
      graph_bindings: [],
    }),
  }
}

///|
test "explicit composite Relation NEAREST keeps complete ordered query and candidate keys" {
  let query = @query.parse_query(
    "FROM queries AS q |> NEAREST candidates AS c QUERY KEY (q.request_id, q.tenant) VECTOR q.embedding CANDIDATE KEY (c.item_id, c.tenant) VECTOR c.embedding METRIC dot K 2 KEEP (q.note) AS hit",
    syntax_limits(),
  ).unwrap()
  let program = compile(
    query,
    composite_nearest_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"id\":[\"request_id\",\"tenant\"]"))
  assert_true(wire.contains("\"id\":[\"item_id\",\"tenant\"]"))
  assert_true(wire.contains("\"cardinality\":\"many_to_one\""))
  assert_true(!wire.contains("\"cardinality\":\"one_to_one\""))
  assert_true(wire.contains("\"query_key\":{\"object\":{\"request_id\":{"))
  assert_true(wire.contains("\"candidate_key\":{\"object\":{\"item_id\":{"))
  assert_true(wire.contains("\"body\":{\"field\":"))
  match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("Closed original Values inputs")
  }
}
