///|
test "explicit DECIMAL_DIVIDE retains original operands target and mode" {
  assert_eq(
    emit("DECIMAL_DIVIDE(amount,31,18,2,'half_even')"),
    "{\"decimal_divide\":{\"left\":{\"field\":\"amount\"},\"precision\":18,\"right\":{\"literal\":31},\"rounding\":\"half_even\",\"scale\":2}}",
  )
}

///|
test "explicit DECIMAL_DIVIDE preserves original static target mode and refusal roles" {
  for mode in ["half_even", "half_up", "toward_zero", "floor", "ceiling"] {
    assert_eq(
      emit("`DeCiMaL_DiViDe`(@amount,@divisor,(38),(0),'" + mode + "')"),
      "{\"decimal_divide\":{\"left\":{\"$param\":\"amount\"},\"precision\":38,\"right\":{\"$param\":\"divisor\"},\"rounding\":\"" +
      mode +
      "\",\"scale\":0}}",
    )
  }
  for
    text in [
      "DECIMAL_DIVIDE(amount,2,4,2)", "DECIMAL_DIVIDE(amount,2,4,2,'floor',0)", "DECIMAL_DIVIDE(amount,2,@p,2,'floor')",
      "DECIMAL_DIVIDE(amount,2,4,2+0,'floor')", "DECIMAL_DIVIDE(amount,2,4,2,@mode)",
      "DECIMAL_DIVIDE(amount,2,0,0,'floor')", "DECIMAL_DIVIDE(amount,2,39,0,'floor')",
      "DECIMAL_DIVIDE(amount,2,4,5,'floor')", "DECIMAL_DIVIDE(amount,2,4,-1,'floor')",
      "DECIMAL_DIVIDE(amount,2,4,2,'nearest')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  for
    text in [
      "DECIMAL_DIVIDE(amount,2)", "ACTQL.DECIMAL_DIVIDE(amount,2,4,2,'floor')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
  assert_true(
    lower(fixture("DECIMAL_DIVIDE(amount,2,4,2,'floor')"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("DECIMAL_DIVIDE(amount,2,4,2,'floor')"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}

///|
test "exact division public SQL target is static and three arguments equal full body" {
  for scale in ["0", "3", "38"] {
    assert_eq(
      emit("`DeCiMaL_DiViDe`(@left,amount,(" + scale + "))"),
      emit("DECIMAL_DIVIDE(@left,amount,38," + scale + ",'exact')"),
    )
  }
  for
    text in [
      "DECIMAL_DIVIDE(a,b,@s)", "DECIMAL_DIVIDE(a,b,s)", "DECIMAL_DIVIDE(a,b,1+1)",
      "DECIMAL_DIVIDE(a,b,39)", "DECIMAL_DIVIDE(a,b,-1)", "DECIMAL_DIVIDE(a,b,1.5)",
      "DECIMAL_DIVIDE(a,b,'2')", "QUANTIZE(a,38,2,'exact')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
}
