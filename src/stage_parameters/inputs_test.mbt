///|
test "stage source requires exactly the declared input names including unused inputs" {
  let program = @stage.parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{"a":"relation","unused":"relation"},"from":"a","steps":[],"results":{"out":{"from":"a","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = prepared(program)
  let body = @decode.open_object(
    @stage.stage_body(stage_at(source, 0).unwrap()),
  ).unwrap()
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let make = fn(names : Array[String]) {
    @pipeline.check(
      @decode.required(body, "steps").unwrap(),
      names.map(n => (n, schema)),
      Some(declarations(source)),
      @decode.lookup(body, "from"),
      {
        max_steps: 0,
        max_work: 1000,
        max_nodes: 100,
        max_depth: 100,
        max_text_bytes: 1000,
        max_tokens: 0,
      },
    ).unwrap()
  }
  let pipeline = make(["a", "unused"])
  let collected = collect(source, 0, pipeline, caps()).unwrap()
  assert_eq(
    collection_work(collected),
    @collection.work(collection(collected)) + 4,
  )
  let exact = { ..caps(), max_work: collection_work(collected), }
  assert_true(collect(source, 0, pipeline, exact) is Ok(_))
  assert_true(
    collect(source, 0, pipeline, { ..exact, max_work: exact.max_work - 1, })
    is Err(Collection(_)),
  )
  assert_true(
    collect(source, 0, pipeline, { ..exact, max_work: 3, })
    is Err(Collection(@collection.WorkLimit)),
  )
  assert_true(collect(source, 0, make(["unused", "a"]), caps()) is Ok(_))
  assert_true(
    collect(source, 0, make(["a"]), caps()) is Err(InputCountMismatch),
  )
  assert_true(
    collect(source, 0, make(["a", "unused", "extra"]), caps())
    is Err(InputCountMismatch),
  )
  assert_true(
    collect(source, 0, make(["a", "other"]), caps())
    is Err(ForeignInput("other")),
  )
  assert_true(
    collect_operations(source, [make(["a", "other"])], caps())
    is Err(Stage(0, ForeignInput("other"))),
  )
}
