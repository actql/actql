///|
fn origin_lookup(c : @decode.Cursor, key : String) -> @decode.Cursor {
  @decode.lookup(@decode.open_object(c).unwrap(), key).unwrap()
}

///|
test "pipeline propagates original mixed-expression type locations" {
  let source = cursor(
    "{\"stages\":[{\"steps\":[{\"derive\":{\"bad\":{\"add\":[\"len('😀') + TRUE\",{\"literal\":1}]}}}]}]}",
  )
  let stages = @decode.elements(origin_lookup(source, "stages")).unwrap()
  let steps = origin_lookup(stages[0], "steps")
  let step = @decode.elements(steps).unwrap()[0]
  let slot = @decode.elements(
      origin_lookup(origin_lookup(origin_lookup(step, "derive"), "bad"), "add"),
    ).unwrap()[0]
  match
    @pipeline_typing.check(
      steps,
      [("rows", @schema.from_object(row()).unwrap())],
      None,
      None,
      limits(),
    ) {
    Err(issue) => {
      assert_true(issue.kind is Operation(Expression(_)))
      assert_eq(issue.path, @decode.cursor_path(slot))
      assert_eq(issue.span, @decode.cursor_span(slot))
      assert_eq(issue.range, Some({ start: 11, end: 15, }))
    }
    Ok(_) => fail("expected type rejection")
  }
}
