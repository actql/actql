///|
test "direct trig Number signatures preserve nullability without implicit conversions" {
  let fields = "{\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true},\"s\":{\"type\":\"string\",\"nullable\":false},\"d\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":8,\"scale\":3},\"t\":{\"type\":\"timestamp\",\"nullable\":false}}"
  for
    name in [
      "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "asinh",
      "acosh", "atanh",
    ] {
    for
      (operand, nullable) in [
        ("n", "false"),
        ("m", "true"),
        ("NULL", "true"),
        ("-1", "false"),
        ("0.5", "false"),
        ("1.7976931348623157e308", "false"),
        ("$p", "false"),
      ] {
      assert_type(
        "\"" + name + "(" + operand + ")\"",
        fields,
        "{\"p\":{\"type\":\"number\"}}",
        "{\"type\":\"number\",\"nullable\":" + nullable + "}",
      )
    }
    for operand in ["s", "d", "t", "'0.5'", "TRUE", "[1]"] {
      assert_rejected(
        "\"" + name + "(" + operand + ")\"",
        fields,
        "null",
        "TypeMismatch",
      )
      assert_rejected(
        "\"if(FALSE," + name + "(" + operand + "),1)\"",
        fields,
        "null",
        "TypeMismatch",
      )
    }
    assert_type(
      "\"if(FALSE," + name + "(1 / 0),7)\"",
      fields,
      "null",
      "{\"type\":\"number\",\"nullable\":false}",
    )
  }
}

///|
test "atan2 types both ordered Number operands and joins their nullability" {
  let fields = "{\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true},\"s\":{\"type\":\"string\",\"nullable\":false},\"d\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":8,\"scale\":3},\"t\":{\"type\":\"timestamp\",\"nullable\":false}}"
  for
    (arguments, nullable) in [
      ("n,n", "false"),
      ("n,m", "true"),
      ("m,n", "true"),
      ("m,m", "true"),
      ("NULL,n", "true"),
      ("n,NULL", "true"),
      ("NULL,m", "true"),
      ("m,NULL", "true"),
      ("NULL,NULL", "true"),
      ("-1,0.5", "false"),
      ("1.7976931348623157e308,-1.7976931348623157e308", "false"),
    ] {
    assert_type(
      "\"atan2(" + arguments + ")\"",
      fields,
      "null",
      "{\"type\":\"number\",\"nullable\":" + nullable + "}",
    )
  }
  for invalid in ["s", "d", "t", "'1'", "TRUE", "[1]"] {
    for valid in ["n", "NULL"] {
      for arguments in [invalid + "," + valid, valid + "," + invalid] {
        assert_rejected(
          "\"atan2(" + arguments + ")\"",
          fields,
          "null",
          "TypeMismatch",
        )
        assert_rejected(
          "\"if(FALSE,atan2(" + arguments + "),1)\"",
          fields,
          "null",
          "TypeMismatch",
        )
      }
    }
  }
  for arguments in ["NULL,1 / 0", "1 / 0,NULL"] {
    assert_type(
      "\"atan2(" + arguments + ")\"",
      fields,
      "null",
      "{\"type\":\"number\",\"nullable\":true}",
    )
  }
}

///|
test "direct trig typed topology retains every authored child in order" {
  let source = syntax("\"atan2(sin(0.5),cos(1 / 0))\"")
  let typed = @expression_typing.check(source, env(), test_limits()).unwrap()
  assert_true(physical_equal(@expression_typing.expression(typed), source))
  assert_eq(@expression_typing.node_count(typed), 7)
  assert_eq(@expression_typing.child_count(typed, 0), Some(2))
  assert_eq(@expression_typing.child_at(typed, 0, 0), Some(1))
  assert_eq(@expression_typing.child_at(typed, 0, 1), Some(3))
  assert_eq(@expression_typing.child_at(typed, 1, 0), Some(2))
  assert_eq(@expression_typing.child_at(typed, 3, 0), Some(4))
  assert_eq(@expression_typing.child_at(typed, 4, 0), Some(5))
  assert_eq(@expression_typing.child_at(typed, 4, 1), Some(6))
  for
    (index, tag) in [
      (0, "atan2"),
      (1, "sin"),
      (2, "literal"),
      (3, "cos"),
      (4, "divide"),
      (5, "literal"),
      (6, "literal"),
    ] {
    match @expression_typing.node_form(typed, index) {
      Some(Expression(actual, _)) => assert_eq(actual, tag)
      _ => fail("expected retained direct trig expression node")
    }
  }
}
