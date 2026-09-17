///|
test "initial Local managed support is a finite unary surface" {
  let (_, acquisition) = query_issuer_fixture()
  let source = @query.query_sequence_owner(acquisition)
  let shapes = [
    ("[{\"select\":[\"id\"]}]", true),
    ("[{\"filter\":\"id > 0\"}]", true),
    ("[{\"derive\":{\"x\":\"id + 1\"}}]", true),
    ("[{\"sort\":[]}]", true),
    (
      "[{\"join\":{\"with\":\"prior\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}}}]",
      false,
    ),
    (
      "[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      true,
    ),
  ]
  for (wire, expected) in shapes {
    let receiver = typed_receiver(source, wire)
    assert_eq(
      @execution.generated_sequence_is_projection_only(
        task_test_generated(receiver),
      ),
      wire == "[{\"select\":[\"id\"]}]",
    )
    assert_eq(
      @local_connector.local_managed_sequence_supported(
        task_test_generated(receiver),
      ),
      expected,
    )
  }
  let ordered = local_managed_support_owner(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2},{\"id\":1}]},\"as\":\"seed\"},{\"sort\":[{\"id\":\"asc\"}],\"as\":\"ordered\"}]",
  )
  for
    wire in [
      "[{\"sort\":[{\"id\":\"desc\"}]}]", "[{\"take\":1}]", "[{\"filter\":\"id > 0\"},{\"derive\":{\"x\":\"id + 1\"}},{\"sort\":[{\"x\":\"asc\"}]},{\"take\":1},{\"select\":[\"x\"]}]",
    ] {
    let receiver = typed_receiver(ordered, wire, target=Step(1))
    assert_true(
      @local_connector.local_managed_sequence_supported(
        task_test_generated(receiver),
      ),
    )
  }
  let values = local_managed_support_owner(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":7}]},\"as\":\"seed\"}]",
  )
  assert_true(
    @local_connector.local_managed_sequence_supported(
      task_test_generated(values),
    ),
  )
}

///|
fn local_managed_support_owner(source : String) -> @lower.BoundPrepared {
  let pipeline = @pipeline.check(input_cursor(source), [], None, None, {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}
