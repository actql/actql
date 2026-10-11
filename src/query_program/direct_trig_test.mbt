///|
test "direct trig SQL spellings match independent complete checked Programs" {
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
    for
      (operand, child) in [
        ("0.5", "{\"literal\":0.5}"),
        ("NULL", "{\"literal\":null}"),
        ("1 / 0", "{\"divide\":[{\"literal\":1},{\"literal\":0}]}"),
      ] {
      let expected = round_trunc_literal_control(
        "{\"" + name + "\":" + child + "}",
      )
      assert_true(
        @check.check_parsed(expected, check_environment(), None, check_limits())
        is Checked(_),
      )
      for spelling in [name, name.to_upper(), mixed, "`" + mixed + "`"] {
        let source = "SELECT " + spelling + "(" + operand + ") AS value"
        let actual = compile(
          @query.parse_query(source, syntax_limits()).unwrap(),
          { ..fixture_context(), inputs: [], },
          construction_limits(),
        ).unwrap()
        assert_eq(semantic(actual), semantic(expected), msg=source)
        assert_true(
          @check.check_parsed(actual, check_environment(), None, check_limits())
          is Checked(_),
        )
      }
    }
  }
}

///|
test "atan2 Programs match independent ordered canonical controls" {
  for
    (arguments, children) in [
      ("1, 2", "[{\"literal\":1},{\"literal\":2}]"),
      ("2, 1", "[{\"literal\":2},{\"literal\":1}]"),
      ("NULL, 1", "[{\"literal\":null},{\"literal\":1}]"),
      ("1, NULL", "[{\"literal\":1},{\"literal\":null}]"),
      ("NULL, NULL", "[{\"literal\":null},{\"literal\":null}]"),
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
    let expected = round_trunc_literal_control("{\"atan2\":" + children + "}")
    assert_true(
      @check.check_parsed(expected, check_environment(), None, check_limits())
      is Checked(_),
    )
    for spelling in ["atan2", "ATAN2", "AtAn2", "`AtAn2`"] {
      let source = "SELECT " + spelling + "(" + arguments + ") AS value"
      let actual = compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=source)
      assert_true(
        @check.check_parsed(actual, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}

///|
fn direct_trig_assert_query_rejected(expression : String) -> Unit raise {
  match
    @query.parse_query("SELECT " + expression + " AS value", syntax_limits()) {
    Err(_) => ()
    Ok(parsed) =>
      match
        compile(
          parsed,
          { ..fixture_context(), inputs: [], },
          construction_limits(),
        ) {
        Err(_) => ()
        Ok(program) =>
          assert_true(
            @check.check_parsed(
              program,
              check_environment(),
              None,
              check_limits(),
            )
            is Rejected(_),
            msg=expression,
          )
      }
  }
}

///|
test "direct trig Programs reject malformed foreign and nonfinite inputs" {
  for
    name in [
      "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN", "SINH", "COSH", "TANH", "ASINH",
      "ACOSH", "ATANH",
    ] {
    for
      args in [
        "", "1,2", "1,2,3", "'0.5'", "TRUE", "CAST('0.5' AS DECIMAL(8,3))", "1e400",
      ] {
      direct_trig_assert_query_rejected(name + "(" + args + ")")
    }
    for prefix in ["SAFE.", "ACTQL.", "SAFE_"] {
      direct_trig_assert_query_rejected(prefix + name + "(1)")
    }
  }
  for
    args in [
      "", "1", "1,2,3", "'1',2", "1,'2'", "TRUE,2", "1,TRUE", "CAST('1' AS DECIMAL(8,3)),2",
      "1,CAST('2' AS DECIMAL(8,3))", "NULL,'2'", "'1',NULL", "1e400,1", "1,1e400",
    ] {
    direct_trig_assert_query_rejected("ATAN2(" + args + ")")
  }
  for prefix in ["SAFE.", "ACTQL.", "SAFE_"] {
    direct_trig_assert_query_rejected(prefix + "ATAN2(1,2)")
  }
}

///|
test "direct trig Programs retain Number parameter validation for every operand" {
  for
    name in [
      "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN", "SINH", "COSH", "TANH", "ASINH",
      "ACOSH", "ATANH", "ATAN2",
    ] {
    let arguments = if name == "ATAN2" { ["@p,1", "1,@p"] } else { ["@p"] }
    for args in arguments {
      let actual = compile(
        @query.parse_query(
          "SELECT " + name + "(" + args + ") AS value",
          syntax_limits(),
        ).unwrap(),
        {
          ..fixture_context(),
          inputs: [],
          parameter_declarations: Some(number_parameter_declarations()),
        },
        construction_limits(),
      ).unwrap()
      for
        (body, valid) in [
          ("{\"p\":0.5}", true),
          ("{\"p\":\"0.5\"}", false),
          ("{\"p\":true}", false),
        ] {
        let supplied = @wire.admit(
          @source.parse_json(body, construction_limits().source.source).unwrap(),
          construction_limits().source.tree,
        ).unwrap()
        let checked = @check.check_parsed(
          actual,
          check_environment(),
          Some(supplied),
          check_limits(),
        )
        if valid {
          assert_true(checked is Checked(_))
        } else {
          assert_true(checked is Rejected(_))
        }
      }
    }
  }
}
