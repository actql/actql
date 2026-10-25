///|
test "compilation pipeline shape derives rows fields and independent encoded skeleton" {
  let empty=compilation_pipeline_shape(1,0,1,1).unwrap()
  assert_eq(empty.facts.node_upper,15)
  assert_eq(empty.facts.objects,6)
  assert_eq(empty.facts.fields_upper,13)
  let full=compilation_pipeline_shape(1,100000,1,1).unwrap()
  assert_eq(full.facts.node_upper,200015)
  assert_eq(full.facts.objects,100006)
  assert_eq(full.facts.fields_upper,100013)
  assert_eq(full.facts.input_bytes,3700188)
  assert_true(compilation_pipeline_shape(2147483647,2147483647,2147483647,2147483647) is None)
  assert_true(compilation_pipeline_shape(0,1,0,1) is None)
}
