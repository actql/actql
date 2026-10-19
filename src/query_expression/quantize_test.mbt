///|
test "explicit QUANTIZE preserves original static Decimal target and rounding mode" {
  assert_eq(
    emit("QUANTIZE(amount,4,2,'half_even')"),
    "{\"quantize\":{\"precision\":4,\"rounding\":\"half_even\",\"scale\":2,\"value\":{\"field\":\"amount\"}}}",
  )
}

///|
test "explicit QUANTIZE keeps target mode roles and original refusal bounds" {
  for mode in ["half_even", "half_up", "toward_zero", "floor", "ceiling"] {
    assert_eq(
      emit("`QuAnTiZe`(@amount,(38),(0),'" + mode + "')"),
      "{\"quantize\":{\"precision\":38,\"rounding\":\"" +
      mode +
      "\",\"scale\":0,\"value\":{\"$param\":\"amount\"}}}",
    )
  }
  for
    text in [
      "QUANTIZE(amount,4,2)", "QUANTIZE(amount,4,2,'nearest')", "QUANTIZE(amount,4,2,@mode)",
      "QUANTIZE(amount,4,2,'FLOOR')", "QUANTIZE(amount,@p,2,'floor')", "QUANTIZE(amount,4,2+0,'floor')",
      "QUANTIZE(amount,0,0,'floor')", "QUANTIZE(amount,39,0,'floor')", "QUANTIZE(amount,4,5,'floor')",
      "QUANTIZE(amount,4,-1,'floor')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  for text in ["QUANTIZE(amount,2)", "ACTQL.QUANTIZE(amount,4,2,'floor')"] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
  assert_true(
    lower(fixture("QUANTIZE(amount,4,2,'floor')"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("QUANTIZE(amount,4,2,'floor')"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}
