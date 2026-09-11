///|
fn kernel_wire(
  owner : @lowering_relation.BoundPrepared,
  index : Int,
) -> String raise {
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    index,
    max_bindings=100,
    max_name_bytes=1000,
    expression_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  @encode.finish(writer)
}

///|
test "full AoA step vectors preserve wiring params and authored column order" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"z\":\"id + 1\"},\"as\":\"augmented\"},{\"filter\":\"z > 1\"},{\"from\":\"augmented\",\"select\":[\"z\",\"id\"]}",
  )
  assert_eq(
    kernel_wire(owner, 1),
    "{\"id\":\"derive_1\",\"in\":[\"values_0\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{\"z\":{\"body\":[{\"body\":\"id\",\"op\":\"field\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"add\"}}}}",
  )
  assert_eq(
    kernel_wire(owner, 2),
    "{\"id\":\"where_2\",\"in\":[\"derive_1\"],\"op\":\"REL.where\",\"params\":{\"expr\":{\"body\":[{\"body\":\"z\",\"op\":\"field\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"gt\"}}}",
  )
  assert_eq(
    kernel_wire(owner, 3),
    "{\"id\":\"select_3\",\"in\":[\"derive_1\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"z\",\"id\"]}}",
  )
}

///|
test "empty map emits a real node and exact byte limits apply to the whole step" {
  let owner = expression_pipeline(",{\"derive\":{}}")
  let expected = "{\"id\":\"derive_1\",\"in\":[\"values_0\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{}}}"
  assert_eq(kernel_wire(owner, 1), expected)
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=0,
    max_name_bytes=0,
    expression_limits(),
  ).unwrap()
  let exact = @encode.writer(expected.length(), 100, 100)
  @lowering_relation.emit_kernel_node(kernel, exact)
  assert_eq(@encode.finish(exact), expected)
  let short = @encode.writer(expected.length() - 1, 100, 100)
  let failed = try {
    @lowering_relation.emit_kernel_node(kernel, short)
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(failed)
}
