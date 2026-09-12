///|
test "indexed calendar obligations retain repeated endpoint bindings" {
  let ds = @parameter.read_declarations(
    Some(cursor("{\"t\":{\"type\":\"timestamp\"}}")),
    { max_nodes: 100, max_depth: 20, max_text_bytes: 1000, max_parameters: 1, },
  ).unwrap()
  for
    (start, end, names) in [
      ("\"2000-01-01T00:00:00.000Z\"", "\"2001-01-01T00:00:00.000Z\"", []),
      ("{\"$param\":\"t\"}", "\"2001-01-01T00:00:00.000Z\"", ["t"]),
      ("{\"$param\":\"t\"}", "{\"$param\":\"t\"}", ["t", "t"]),
    ] {
    let c = @calendar_typing.check(
      Series,
      cursor(
        "{\"start\":" +
        start +
        ",\"end\":" +
        end +
        ",\"unit\":\"month\",\"timezone\":\"UTC\"}",
      ),
      None,
      Some(ds),
      Some(profile()),
      limits(),
    ).unwrap()
    let expected : Array[@calendar_typing.Obligation] = [
      ValidateCalendarValues,
      ValidateBoundaryDomain,
      ResolveResources,
    ]
    for name in names {
      expected.push(BindTimestamp(name))
    }
    if !names.is_empty() {
      expected.push(ValidateBoundRange)
    }
    assert_eq(@calendar_typing.pending_validation_count(c), expected.length())
    for i in 0..<expected.length() {
      assert_eq(@calendar_typing.pending_validation_at(c, i), Some(expected[i]))
    }
    let copied = @calendar_typing.pending_validations(c)
    assert_eq(copied, expected)
    copied.clear()
    assert_eq(@calendar_typing.pending_validation_count(c), expected.length())
    for i in [-1, expected.length(), 2147483647] {
      assert_true(@calendar_typing.pending_validation_at(c, i) is None)
    }
  }
}
