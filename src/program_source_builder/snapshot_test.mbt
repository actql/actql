///|
test "source snapshot retains immutable values and provenance while construction continues" {
  let document = @origin.document("x", 10).unwrap()
  let origin = @origin.range(document, 0, 1).unwrap()
  let builder = @program_source_builder.create(document, limits()).unwrap()
  let first = @program_source_builder.add(
    builder,
    String("e\u0301\r\n"),
    origin,
  ).unwrap()
  let prefix = @program_source_builder.add(builder, Array([first]), origin).unwrap()
  let saved = @program_source_builder.snapshot(builder, prefix).unwrap()
  let second = @program_source_builder.add(builder, String("é\n"), origin).unwrap()
  let complete = @program_source_builder.add(
    builder,
    Array([first, second]),
    origin,
  ).unwrap()
  let finished = @program_source_builder.finish(builder, complete).unwrap()
  let saved_cursor = @program_source_builder.cursor(saved)
  assert_eq(@wire.array_length(saved_cursor), Some(1))
  let value = @wire.element_at(saved_cursor, 0).unwrap()
  assert_eq(@wire.text(value).unwrap(), "e\u0301\r\n")
  assert_eq(
    @origin.span(@program_source_builder.origin(saved, value).unwrap()),
    @origin.span(origin),
  )
  assert_eq(@program_source_builder.usage(saved).nodes, 2)
  assert_eq(
    @wire.array_length(@program_source_builder.cursor(finished)),
    Some(2),
  )
  assert_true(@program_source_builder.snapshot(builder, prefix) is Err(Closed))
}

///|
test "source snapshot does not substitute a foreign owner or reopen a failed builder" {
  let document = @origin.document("x", 10).unwrap()
  let origin = @origin.range(document, 0, 1).unwrap()
  let builder = @program_source_builder.create(document, limits()).unwrap()
  let foreign = @program_source_builder.create(document, limits()).unwrap()
  let foreign_node = @program_source_builder.add(foreign, Null, origin).unwrap()
  assert_true(
    @program_source_builder.snapshot(builder, foreign_node) is Err(ForeignNode),
  )
  let own = @program_source_builder.add(builder, Bool(true), origin).unwrap()
  assert_true(
    @wire.boolean(
      @program_source_builder.cursor(
        @program_source_builder.finish(builder, own).unwrap(),
      ),
    ).unwrap(),
  )
  let failed = @program_source_builder.create(document, {
    ..limits(),
    source: { ..limits().source, max_nodes: 1, },
  }).unwrap()
  let node = @program_source_builder.add(failed, Null, origin).unwrap()
  assert_true(
    @program_source_builder.add(failed, Array([node]), origin) is Err(NodeLimit),
  )
  assert_true(@program_source_builder.snapshot(failed, node) is Err(Closed))
}
