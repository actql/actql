///|
test "checked window grouping replaces an aggregate spelling without recycling its old label" {
  let query = @query.parse_query(
    "FROM rows |> window_group(by: [cohort], aggregates: {id: {fn: 'count'}})",
    mapping_syntax_limits(),
  ).unwrap()
  let document = @query.query_document(query)
  let construction : Construction = {
    builder: @builder.create(document, mapping_limits().source).unwrap(),
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
    model_tasks: None,
    parameter_names: None,
    infer_labels: true,
    infer_budget: { remaining_work: 100000, },
  }
  let raw = @wire.admit(
    @source.parse_json(
      (
        #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"at":{"type":"number","nullable":false},"cohort":{"type":"string","nullable":false}},"rows":[{"id":1,"at":0,"cohort":"a"}]},"as":"seed"},{"from":"seed","row_window":{"kind":"fixed","time":"at","size":"1m"},"as":"rows"},{"from":"rows","window_group":{"by":["cohort"],"aggregates":{"id":{"fn":"count"}}},"as":"out"}]
      ),
      mapping_limits().source.source,
    ).unwrap(),
    mapping_limits().source.tree,
  ).unwrap()
  let steps = @wire.elements(raw)
    .unwrap()
    .map(source => import_query_cursor(construction, source))
  let pipeline = checked_query_prefix_pipeline(
    construction,
    query,
    mapping_context(),
    [],
    [],
    steps,
    mapping_limits(),
    construction.infer_budget,
  )
  let columns = [
    ("ticket", "id"),
    ("at", "at"),
    ("cohort", "cohort"),
    ("window_start", "window_start"),
    ("window_end", "window_end"),
  ]
  let scope : JoinChainScope = {
    visible: columns,
    columns,
    value_table: false,
    value_columns: [],
    ranges: [],
    star_ranges: [],
    receivers: [],
    scalar_ranges: [],
    key_labels: [
      ("id", "ticket"),
      ("at", "at"),
      ("cohort", "historical_cohort"),
      ("window_start", "window_start"),
      ("window_end", "window_end"),
    ],
  }
  let sources : ScriptSources = {
    declarations: [],
    stages: [],
    prior_stages: [],
    bound: Map([]),
    unshared: [],
    ranges: Map([("rows", scope)]),
    value_tables: Map([]),
    binding_ranges: [],
    carriers: Map([]),
    carrier_work: construction.infer_budget.remaining_work,
  }
  let target = @pipeline.lookup(pipeline, "out").unwrap()
  let carrier = @pipeline.carrier_at(pipeline, target).unwrap()
  guard @query.operation_at(query, 0) is Some(GraphCall(call)) else {
    fail("expected the authored grouping call")
  }
  retain_script_carrier_column_scope(
    construction,
    sources,
    "rows",
    "out",
    carrier,
    pipeline,
    target,
    [],
    call,
  )
  let labels = Map(sources.ranges.get("out").unwrap().key_labels)
  assert_eq(labels.get("id"), Some("id"))
  assert_eq(labels.get("cohort"), Some("historical_cohort"))
  assert_eq(labels.get("window_start"), Some("window_start"))
  assert_eq(labels.get("window_end"), Some("window_end"))
  assert_eq(labels.get("at"), None)
  @builder.discard(construction.builder)
}

///|
test "fresh ranking role labels defer conflicting selectors until actual key adoption" {
  let (construction, _) = infer_key_labels_test_construction(10000)
  let query = @query.parse_query(
    "FROM rows |> merge_rankings(with: other, by: [old.id, ticket], candidate: item, rank: position, k: 1, score_policy: {rrf: {rank_constant: 1, weights: [1, 1]}})",
    mapping_syntax_limits(),
  ).unwrap()
  guard @query.operation_at(query, 0) is Some(GraphCall(call)) else {
    fail("expected the authored ranking call")
  }
  let by = call.arguments.filter(argument => argument.0 == "by")[0].1
  let fields = [@schema.Unqualified("slot"), @schema.Unqualified("slot")]
  let ambiguous : Map[String, String] = Map([])
  infer_carrier_ranking_role(construction, by, fields, ambiguous)
  assert_eq(ambiguous.get("slot"), Some(""))
  let same = @query.ListValue([
    @query.FieldReference([{ value: "ticket", quoted: false, }]),
    @query.FieldReference([{ value: "ticket", quoted: false, }]),
  ])
  infer_carrier_ranking_role(construction, same, fields, ambiguous)
  // infer_prefix_check rejects this empty name after selecting the exact key;
  // repeated later selectors must not silently turn it into a usable label.
  assert_eq(ambiguous.get("slot"), Some(""))
  let labels : Map[String, String] = Map([])
  infer_carrier_ranking_role(construction, same, fields, labels)
  assert_eq(labels.get("slot"), Some("ticket"))
  @builder.discard(construction.builder)
}
