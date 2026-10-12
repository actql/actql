///|
test "GoogleSQL direct trig spellings retain canonical unary operations" {
  for
    (name, mixed) in [
      ("sin", "SiN"),
      ("cos", "CoS"),
      ("tan", "TaN"),
      ("asin", "AsIn"),
      ("acos", "AcOs"),
      ("atan", "AtAn"),
      ("sinh", "SiNh"),
      ("cosh", "CoSh"),
      ("tanh", "TaNh"),
      ("asinh", "AsInH"),
      ("acosh", "AcOsH"),
      ("atanh", "AtAnH"),
    ] {
    for spelling in [name, name.to_upper(), mixed, "`" + mixed + "`"] {
      for
        (operand, child) in [
          ("x", "{\"field\":\"x\"}"),
          ("@n", "{\"$param\":\"n\"}"),
          ("NULL", "{\"literal\":null}"),
          ("1 / 0", "{\"divide\":[{\"literal\":1},{\"literal\":0}]}"),
        ] {
        assert_eq(
          emit(spelling + "(" + operand + ")"),
          "{\"" + name + "\":" + child + "}",
        )
      }
      assert_eq(
        emit(spelling + "(" + spelling + "(0.5))"),
        "{\"" + name + "\":{\"" + name + "\":{\"literal\":0.5}}}",
      )
      for args in ["", "1,2", "1,2,3"] {
        assert_true(
          lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
          is Err({ issue: InvalidArguments, .. }),
        )
      }
    }
  }
}

///|
test "GoogleSQL atan2 keeps ordered authored children for every spelling" {
  for spelling in ["atan2", "ATAN2", "AtAn2", "`AtAn2`"] {
    for
      (arguments, children) in [
        ("x, @p", "[{\"field\":\"x\"},{\"$param\":\"p\"}]"),
        ("@p, x", "[{\"$param\":\"p\"},{\"field\":\"x\"}]"),
        (
          "NULL, 1 / 0", "[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]",
        ),
        (
          "1 / 0, NULL", "[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":null}]",
        ),
        (
          "SIN(0.5), COS(1)", "[{\"sin\":{\"literal\":0.5}},{\"cos\":{\"literal\":1}}]",
        ),
      ] {
      assert_eq(
        emit(spelling + "(" + arguments + ")"),
        "{\"atan2\":" + children + "}",
      )
    }
    for args in ["", "1", "1,2,3"] {
      assert_true(
        lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
  }
}

///|
test "direct trig registry identity adds no aliases SAFE prefix or scoped extensions" {
  let names = [
    "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh",
    "asinh", "acosh", "atanh",
  ]
  for name in names {
    assert_true(
      same_scalar_function(
        scalar_identity_name(name),
        scalar_identity_name(name.to_upper(), quoted=true),
      ),
    )
    for other in names {
      if name != other {
        assert_false(
          same_scalar_function(
            scalar_identity_name(name),
            scalar_identity_name(other),
          ),
        )
      }
    }
    let args = if name == "atan2" { "1,2" } else { "1" }
    for spelling in ["SAFE." + name, "ACTQL." + name, "safe_" + name] {
      assert_true(
        lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
        is Err({ issue: UnsupportedFunction, .. }),
      )
    }
    for scope in ["SAFE", "ACTQL"] {
      assert_false(
        same_scalar_function(
          [{ value: scope, quoted: false, }, { value: name, quoted: false, }],
          scalar_identity_name(name),
        ),
      )
    }
  }
}
