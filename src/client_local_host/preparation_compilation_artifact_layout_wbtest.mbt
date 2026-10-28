///|
test "compilation artifact packet retains distinct wire owners and excludes borrowed program" {
  let a = compilation_artifact_retained_layout(100, 50, 25).unwrap()
  assert_eq(a.owned_utf16_units, 388L)
  assert_eq(a.record_headers, 14L)
  let b = compilation_artifact_retained_layout(101, 50, 25).unwrap()
  assert_eq(
    @execution.preparation_representation_cost(b).unwrap() -
    @execution.preparation_representation_cost(a).unwrap(),
    2L,
  )
  assert_true(compilation_artifact_retained_layout(-1, 50, 25) is None)
}

///|
test "compilation ancestry quote retains full semantic node authority separately" {
  let narrow = compilation_writer_ancestry_layout(
    500308, 10, 14, 1, 1, 12238072,
  ).unwrap()
  let general = closed_values_writer_layout(500308, 10, 1, 1, 12238072).unwrap()
  assert_eq(narrow.owned_utf16_units, general.owned_utf16_units)
  assert_eq(
    @execution.preparation_representation_cost(general).unwrap() -
    @execution.preparation_representation_cost(narrow).unwrap(),
    256L * (500308L - 140L),
  )
  assert_true(compilation_canonical_emitter_layout(10) is Some(_))
  assert_true(compilation_canonical_emitter_layout(-1) is None)
}
