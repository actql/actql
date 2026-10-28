///|
test "original incremental admission retains field and UTF16 dimensions once across Unicode suspension" {
  let input = node(
    @source.Object([
      entry("é", node(@source.String("🙂".repeat(40)))),
      entry(
        "rows",
        node(
          @source.Array([node(@source.Number(1)), node(@source.String("x"))]),
        ),
      ),
    ]),
  )
  let reader = start_admission(input, budget()).unwrap()
  let mut original = None
  while original is None {
    match advance_admission(reader, 1).unwrap() {
      AdmissionContinue(..) => ()
      AdmissionComplete(cursor, ..) => original = Some(cursor)
      AdmissionFailed(_, ..) => fail("original Unicode admission must succeed")
    }
  }
  let root = original.unwrap()
  let cached = admission_preparation_data(root)
  assert_eq(cached, { fields: 2, texts: 2, max_key_utf16: 4, total_utf16: 86L, })
  let child = required(open_object(root).unwrap(), "rows").unwrap()
  assert_true(physical_equal(cached, admission_preparation_data(child)))
  assert_true(physical_equal(cached, admission_preparation_data(root)))
  assert_eq(admission_usage(root).nodes, 5)
}
