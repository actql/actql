///|
test "object and property lowering emit the existing closed expression wire" {
  let source = ",{\"derive\":[{\"value\":{\"object\":{\"z\":{\"field\":\"id\"},\"a/~\":{\"property\":{\"value\":{\"object\":{\"nested\":{\"field\":\"id\"}}},\"name\":\"nested\"}}}}}]}"
  let kernel = ordered_kernel(source)
  let references = @lowering_relation.prepare_ordered_references(
    kernel,
    reference_limits(),
  ).unwrap()
  assert_eq(
    references_wire(references),
    "[{\"at\":\"/bindings/0/expr/body/a~1~0/body/value/body/nested\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/0/expr/body/z\",\"target\":{\"input_field\":\"id\"}}]",
  )
  let expression = @lowering_relation.lower_expression(
    expression_pipeline(source),
    1,
    0,
    expression_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_expression(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"body\":{\"a/~\":{\"body\":{\"name\":\"nested\",\"value\":{\"body\":{\"nested\":{\"body\":\"id\",\"op\":\"field\"}},\"op\":\"object\"}},\"op\":\"property\"},\"z\":{\"body\":\"id\",\"op\":\"field\"}},\"op\":\"object\"}",
  )
}

///|
test "object reference pointers charge UTF-8 names and escape each segment" {
  let kernel = ordered_kernel(
    ",{\"derive\":[{\"value\":{\"object\":{\"😀\":{\"field\":\"id\"}}}}]}",
  )
  // /bindings/0/expr/body/ is 22 ASCII bytes and the name is four UTF-8 bytes.
  let exact = { ..reference_limits(), max_pointer_bytes: 26, }
  let references = @lowering_relation.prepare_ordered_references(kernel, exact).unwrap()
  assert_eq(
    @lowering_relation.ordered_reference_at(references, 0).unwrap().at,
    "/bindings/0/expr/body/😀",
  )
  assert_true(
    @lowering_relation.prepare_ordered_references(kernel, {
      ..exact,
      max_pointer_bytes: 25,
    })
    is Err(@lowering_relation.ReferenceLimit),
  )
}
