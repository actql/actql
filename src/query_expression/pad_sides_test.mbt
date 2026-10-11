///|
test "GoogleSQL side slices and padding keep every authored child once" {
  for name in ["LEFT", "RIGHT", "LPAD", "RPAD"] {
    let tag = if name == "LEFT" {
      "left"
    } else if name == "RIGHT" {
      "right"
    } else if name == "LPAD" {
      "lpad"
    } else {
      "rpad"
    }
    for spelling in [name, tag, "`" + name + "`"] {
      assert_eq(
        emit(spelling + "(x, @n)"),
        "{\"" + tag + "\":[{\"field\":\"x\"},{\"$param\":\"n\"}]}",
      )
      for args in ["", "'x'", "'x',1,'a','b'"] {
        assert_true(
          lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
          is Err({ issue: InvalidArguments, .. }),
        )
      }
    }
    assert_true(
      lower(fixture("ACTQL." + name + "('x',1)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
    if name == "LEFT" || name == "RIGHT" {
      assert_true(
        lower(fixture(name + "('x',1,'a')"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    } else {
      assert_eq(
        emit(name + "(NULL, -1, p)"),
        "{\"" +
        tag +
        "\":[{\"literal\":null},{\"literal\":-1},{\"field\":\"p\"}]}",
      )
    }
  }
}

///|
test "side and pad scalar identities preserve spelling aliases but distinct functions" {
  for
    (lower, upper) in [
      ("left", "LEFT"),
      ("right", "RIGHT"),
      ("lpad", "LPAD"),
      ("rpad", "RPAD"),
    ] {
    assert_true(
      same_scalar_function(
        scalar_identity_name(lower),
        scalar_identity_name(upper, quoted=true),
      ),
    )
  }
  for
    (left, right) in [
      ("LEFT", "RIGHT"),
      ("LPAD", "RPAD"),
      ("LEFT", "SUBSTR"),
      ("RIGHT", "SUBSTRING"),
      ("LPAD", "LEFT"),
    ] {
    assert_false(
      same_scalar_function(
        scalar_identity_name(left),
        scalar_identity_name(right),
      ),
    )
  }
}
