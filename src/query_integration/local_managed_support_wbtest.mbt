///|
test "initial Local managed support is projection-only" {
  let (_, acquisition) = query_issuer_fixture()
  let source = @query.query_sequence_owner(acquisition)
  let shapes = [
    ("[{\"select\":[\"id\"]}]", true),
    ("[{\"filter\":\"id > 0\"}]", false),
    ("[{\"derive\":{\"x\":\"id + 1\"}}]", false),
    (
      "[{\"join\":{\"with\":\"prior\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}}}]",
      false,
    ),
    (
      "[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      false,
    ),
  ]
  for (wire, expected) in shapes {
    let receiver = typed_receiver(source, wire)
    assert_eq(
      @execution.generated_sequence_is_projection_only(
        task_test_generated(receiver),
      ),
      expected,
    )
  }
}
