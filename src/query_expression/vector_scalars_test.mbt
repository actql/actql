///|
test "adopted vector cosine surface preserves the existing scalar score body" {
  assert_eq(
    @json.parse(emit("VECTOR_COSINE_SIMILARITY(a,b)")),
    @json.parse(
      "{\"vector_score\":{\"left\":{\"field\":\"a\"},\"right\":{\"field\":\"b\"},\"metric\":\"cosine\"}}",
    ),
  )
}

///|
test "adopted vector inner product surface preserves the existing scalar score body" {
  assert_eq(
    @json.parse(emit("VECTOR_INNER_PRODUCT(a,b)")),
    @json.parse(
      "{\"vector_score\":{\"left\":{\"field\":\"a\"},\"right\":{\"field\":\"b\"},\"metric\":\"dot\"}}",
    ),
  )
}

///|
test "adopted vector L2 distance negates the existing negative distance score" {
  assert_eq(
    @json.parse(emit("VECTOR_L2_DISTANCE(a,b)")),
    @json.parse(
      "{\"negate\":{\"vector_score\":{\"left\":{\"field\":\"a\"},\"right\":{\"field\":\"b\"},\"metric\":\"l2\"}}}",
    ),
  )
}

///|
test "adopted vector concat preserves operand order and multiplicity" {
  assert_eq(
    @json.parse(emit("VECTOR_CONCAT(a,b,a)")),
    @json.parse(
      "{\"vector_concat\":[{\"field\":\"a\"},{\"field\":\"b\"},{\"field\":\"a\"}]}",
    ),
  )
}

///|
test "vector scalar arities reject through the existing argument diagnostic" {
  for
    text in [
      "VECTOR_COSINE_SIMILARITY(a)", "VECTOR_INNER_PRODUCT(a,b,a)", "VECTOR_L2_DISTANCE()",
      "VECTOR_CONCAT(a)",
    ] {
    match lower(fixture(text), path => Some(path[0].value), limits()) {
      Err({ issue: InvalidArguments, .. }) => ()
      _ => fail("expected vector scalar argument refusal")
    }
  }
}

///|
test "vector scalar registry preserves quoted lookup and distinct metric identity" {
  assert_eq(
    emit("`vector_inner_product`(a,b)"),
    emit("VECTOR_INNER_PRODUCT(a,b)"),
  )
  for
    left in [
      "VECTOR_COSINE_SIMILARITY", "VECTOR_INNER_PRODUCT", "VECTOR_L2_DISTANCE",
    ] {
    assert_true(
      same_scalar_function(
        scalar_identity_name(left),
        scalar_identity_name(left, quoted=true),
      ),
    )
    for
      right in [
        "VECTOR_COSINE_SIMILARITY", "VECTOR_INNER_PRODUCT", "VECTOR_L2_DISTANCE",
      ] {
      if left != right {
        assert_false(
          same_scalar_function(
            scalar_identity_name(left),
            scalar_identity_name(right),
          ),
        )
      }
    }
  }
  match
    lower(
      fixture("other.VECTOR_CONCAT(a,b)"),
      path => Some(path[0].value),
      limits(),
    ) {
    Err({ issue: UnsupportedFunction, .. }) => ()
    _ => fail("unknown namespace must remain unsupported")
  }
}
