///|
test "P2 authored SGA output names require quoted reserved words" {
  for keyword in ["SELECT", "null", "WITH", "by", "RIGHT"] {
    for role in ["identity", "source", "target"] {
      let text = "match_edges(bindings: {" + role + ": " + keyword + "})"
      assert_true(
        parse_sga_call(text, query_limits())
        is Err({ issue: Syntax("Reserved output name requires backticks"), .. }),
        msg=text,
      )
      assert_eq(
        parse_sga_call(
          "match_edges(bindings: {" + role + ": `" + keyword + "`})",
          query_limits(),
        ).unwrap().arguments,
        [
          (
            "bindings",
            ObjectValue([(role, OutputName({ value: keyword, quoted: true, }))]),
          ),
        ],
      )
    }
  }
}

///|
test "P2 closed keys and literal data retain separate name admission" {
  let call = parse_sga_call(
    "match_edges(BINDINGS: {SOURCE: src, `Target`: dst}, where: {literal: {SELECT: 'exact', select: 'other', NULL: null}}, fields: [src, dst])",
    query_limits(),
  ).unwrap()
  assert_eq(
    call.arguments[0].1,
    ObjectValue([
      ("source", OutputName({ value: "src", quoted: false, })),
      ("target", OutputName({ value: "dst", quoted: false, })),
    ]),
  )
  assert_eq(
    call.arguments[1].1,
    ObjectValue([
      (
        "literal",
        ObjectValue([
          ("SELECT", TextValue("exact")),
          ("select", TextValue("other")),
          ("NULL", NullValue),
        ]),
      ),
    ]),
  )
  assert_true(
    parse_sga_call(
      "match_edges(bindings: {source: src, `SOURCE`: dst})",
      query_limits(),
    )
    is Err({ issue: Syntax("Duplicate SGA argument"), .. }),
  )
}
