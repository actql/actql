///|
test "same-named local snapshot in another actual stage is not applicable" {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{"b":"relation"},"steps":[],"results":{"out":{}}},{"id":"t","inputs":{"b":"relation","r":{"result":{"stage":"s","result":"out"}}},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"t","result":"out"}}}}
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
  let source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let index = @refs.prepare(source, { max_work: 10000, max_text_bytes: 10000, }).unwrap()
  let first = prepare(source, 0, caps()).unwrap()
  let second = prepare(source, 1, caps()).unwrap()
  let supplied = [snapshot_for("b", schema_fields())]
  assert_true(reconcile_snapshots(first, index, supplied, caps()) is Ok(_))
  assert_true(
    reconcile_snapshots(second, index, supplied, caps())
    is Err(ForeignStage("source:local/s/b")),
  )
}
