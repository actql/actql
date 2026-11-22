///|
test "JSON_VALUE scans only the selected source prefix and preserves numeric lexemes" {
  for
    (source, expected) in [
      (
        (
          #|{"json_value":[{"literal":"{\"skip\":[0,{\"discard\":false}],\"n\":9007199254740993}"},{"literal":"$.n"}]}
        ),
        "9007199254740993",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"n\":-12.30e+02} invalid trailing data"},{"literal":"$.n"}]}
        ),
        "-12.30e+02",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"hello\": \"world\""},{"literal":"$.hello"}]}
        ),
        "world",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"a.b\":[{\"ignore\":1},{\"x\":\"caf\\u00e9\\uD83D\\uDE42\"}]}"},{"literal":"$.\"a.b\"[1].x"}]}
        ),
        "café🙂",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"first\":false,\"first\":true}"},{"literal":"$.first"}]}
        ),
        "false",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"a\\\\q\": 7}"},{"literal":"$.\"a\\q\""}]}
        ),
        "7",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"a b\": [\"first\"]}"},{"literal":"$.a b[ 0 ]"}]}
        ),
        "first",
      ),
      (
        (
          #|{"json_value":[{"literal":"{\"a\\\"b\": true}"},{"literal":"$.\"a\\\"b\""}]}
        ),
        "true",
      ),
      ("{\"json_value\":[{\"literal\":\"true\"}]}", "true"),
    ] {
    assert_true(
      run_expr(source) is Ok(Text(actual)) && actual == expected,
      msg=source,
    )
  }
}

///|
test "JSON_VALUE selects admitted data or distinguishes missing values from invalid paths" {
  let typed =
    #|{"json_value":[{"typed_literal":{"type":"json","value":"{\"a.b\":[null,42]}"}},{"literal":"$.\"a.b\"[1]"}]}
  assert_true(run_expr(typed) is Ok(Text("42")))
  for
    source in [
      (
        #|{"json_value":[{"literal":"{}"},{"literal":"$.n"}]}
      ),
      (
        #|{"json_value":[{"literal":"{\"n\":null}"},{"literal":"$.n"}]}
      ),
      (
        #|{"json_value":[{"literal":"{\"n\":[1,2]}"},{"literal":"$.n"}]}
      ),
      (
        #|{"json_value":[{"literal":"{\"n\":-1e+}"},{"literal":"$.n"}]}
      ),
      (
        #|{"json_value":[{"literal":"{\"n\":\"\\uD800\"}"},{"literal":"$.n"}]}
      ),
      (
        #|{"json_value":[{"literal":"[]"},{"literal":"$[999999999999999999999]"}]}
      ),
      (
        #|{"json_value":[{"literal":"[1,2]"},{"literal":"$[ -1 ]"}]}
      ),
      (
        #|{"json_value":[{"literal":"{}"},{"literal":null}]}
      ),
    ] {
    assert_true(run_expr(source) is Ok(Null), msg=source)
  }
  for
    source in [
      (
        #|{"json_value":[{"literal":"{}"},{"literal":"$."}]}
      ),
      (
        #|{"json_value":[{"literal":"[]"},{"literal":"$[*]"}]}
      ),
      (
        #|{"json_value":[{"literal":"{}"},{"literal":"$.\"bad"}]}
      ),
    ] {
    assert_true(
      run_expr(source) is Err({ kind: Scalar(InvalidOperand), .. }),
      msg=source,
    )
  }
}

///|
test "JSON_VALUE keeps literal backslash pairs at the end of a quoted member" {
  let open_path = "$.\"k" + "\\".repeat(2)
  let document : Json = { "k\\\\": "pair", "k\\": "single" }
  let raw = document.stringify()
  let typed : Json = { "typed_literal": { "type": "json", "value": raw } }
  for input in [({ "literal": raw } : Json), typed] {
    let valid : Json = {
      "json_value": [input, { "literal": open_path + "\"" }],
    }
    assert_true(
      run_expr(valid.stringify()) is Ok(Text("pair")),
      msg=valid.stringify(),
    )
    for path in [open_path, open_path + "\\\""] {
      let invalid : Json = { "json_value": [input, { "literal": path }] }
      assert_true(
        run_expr(invalid.stringify())
        is Err({ kind: Scalar(InvalidOperand), .. }),
        msg=invalid.stringify(),
      )
    }
  }
}

///|
test "JSON_VALUE stops at the selected scalar and still meters an unselected prefix" {
  let tail = " ".repeat(4096)
  let first = lowered(
    "{\"json_value\":[{\"literal\":\"{\\\"a\\\":\\\"yes\\\"," +
    tail +
    "\"},{\"literal\":\"$.a\"}]}",
  )
  let missing = lowered(
    "{\"json_value\":[{\"literal\":\"{\\\"b\\\":" +
    tail +
    "1}\"},{\"literal\":\"$.a\"}]}",
  )
  assert_true(
    evaluate_expression(first, {}, [], { remaining: 100, max_frames: 100, })
    is Ok(Text("yes")),
  )
  assert_true(
    evaluate_expression(missing, {}, [], { remaining: 100, max_frames: 100, })
    is Err({ kind: ControlLimit, .. }),
  )
}
