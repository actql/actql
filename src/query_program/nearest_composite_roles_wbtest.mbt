///|
test "typed NEAREST retains ordered composite identities without rebuilding vectors" {
  let a = @schema.Unqualified("a")
  let b = @schema.Unqualified("b")
  let v = @schema.Unqualified("embedding")
  let rows = @carrier.rows(
    [
      (a, Some(@contract.primitive(StringType, nullable=false))),
      (b, Some(@contract.primitive(NumberType, nullable=false))),
      (v, Some(@contract.vector_contract(2, nullable=false).unwrap())),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=20,
  ).unwrap()
  guard @carrier.vectors(rows, ids=[b, a], components=v, max_identity_fields=2).unwrap()
    is @carrier.VectorValue(vectors) else {
    abort("typed Vectors control")
  }
  let text = "FROM q |> NEAREST c AS corpus QUERY KEY (b, a) VECTOR embedding CANDIDATE KEY (corpus.b, corpus.a) VECTOR corpus.embedding METRIC dot K 2 AS hit"
  let query = @query.parse_query(text, mapping_syntax_limits()).unwrap()
  guard @query.operation_at(query, 0) is Some(Nearest(clause)) else {
    abort("NEAREST control")
  }
  let document = @origin.document(text, 10000).unwrap()
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = {
    builder,
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
    model_tasks: None,
    parameter_names: None,
    infer_labels: false,
    infer_budget: { remaining_work: mapping_limits().max_expression_work, },
  }
  let visible = [("a", "a"), ("b", "b"), ("embedding", "embedding")]
  let candidate : Input = {
    relation: [{ value: "c", quoted: false, }],
    name: "candidate_vectors",
    source: StepReference,
    visible_fields: visible.map(field => field.0),
    graph_bindings: [],
  }
  let (steps, fields) = lower_nearest_steps(
    construction,
    clause,
    candidate,
    visible,
    [({ value: "q", quoted: false, }, visible)],
    visible.map(field => field.0),
    [("from", construction.text("query_vectors"))],
    0,
    [],
    10000,
    query_typed=Some((vectors, "query_vectors")),
    candidate_typed=Some(vectors),
  )
  assert_eq(fields, ["a", "b", "embedding", "hit"])
  let source = @builder.finish(
    builder,
    construction.array(steps.map(step => construction.object(step))),
  ).unwrap()
  let cursor = @builder.cursor(source)
  for i in 0..<steps.length() {
    let step = @wire.open_object(@wire.element_at(cursor, i).unwrap()).unwrap()
    assert_true(@wire.lookup(step, "to_vectors") is None)
    if @wire.lookup(step, "vectors") is Some(_) {
      assert_eq(@wire.text(@wire.lookup(step, "from").unwrap()), Ok("query_vectors"))
    }
  }
  let nearest_steps = @wire.elements(cursor)
    .unwrap()
    .filter(step => {
      @wire.lookup(@wire.open_object(step).unwrap(), "nearest") is Some(_)
    })
  assert_eq(nearest_steps.length(), 1)
  let nearest = @wire.open_object(nearest_steps[0]).unwrap()
  assert_eq(
    @wire.text(@wire.lookup(nearest, "from").unwrap()),
    Ok("candidate_vectors"),
  )
  let options = @wire.open_object(@wire.lookup(nearest, "nearest").unwrap()).unwrap()
  assert_eq(
    @wire.text(@wire.lookup(options, "queries").unwrap()),
    Ok("query_vectors"),
  )
  let derives = @wire.elements(cursor)
    .unwrap()
    .filter_map(step => @wire.lookup(@wire.open_object(step).unwrap(), "derive"))
  let extraction = derives[0]
  let keys = @wire.object_field_names(extraction).unwrap()
  let extraction = @wire.open_object(extraction).unwrap()
  // Independent positional identity contract: component zero is b, one is a.
  for
    (i, field, index) in [
      (0, "query_id", "0"),
      (1, "query_id", "1"),
      (2, "candidate_id", "0"),
      (3, "candidate_id", "1"),
    ] {
    let expr = @wire.open_object(@wire.lookup(extraction, keys[i]).unwrap()).unwrap()
    let property = @wire.open_object(@wire.lookup(expr, "property").unwrap()).unwrap()
    assert_eq(@wire.text(@wire.lookup(property, "name").unwrap()), Ok(index))
    let value = @wire.open_object(@wire.lookup(property, "value").unwrap()).unwrap()
    assert_eq(@wire.text(@wire.lookup(value, "field").unwrap()), Ok(field))
  }
  assert_eq(
    nearest_vector_roles(clause.query_roles, vectors, visible, [
      ({ value: "q", quoted: false, }, visible),
    ]).0,
    [("b", "b"), ("a", "a")],
  )
}
