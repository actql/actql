///|
fn sequence_authored_defaults_body(
  grouping : Bool,
  overlap : Bool,
  contiguity : Bool,
) -> String {
  "{\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":{\"literal\":true}},{\"as\":\"closed\",\"where\":{\"literal\":false}}],\"within\":20" +
  (if grouping { ",\"by\":[]" } else { "" }) +
  (if overlap { ",\"overlap\":\"disallow\"" } else { "" }) +
  (if contiguity { ",\"contiguity\":\"adjacent\"" } else { "" }) +
  "}"
}

///|
test "sequence completes only omitted grouping and modes through its original checked owner" {
  for grouping in [false, true] {
    for overlap in [false, true] {
      for contiguity in [false, true] {
        let body = cursor(
          sequence_authored_defaults_body(grouping, overlap, contiguity),
        )
        let checked = @relation_typing.check_sequence(
          body,
          @carrier.relation(sequence_rows(false)),
          None,
          limits(),
        ).unwrap()
        assert_true(
          physical_equal(@relation_typing.sequence_source(checked), body),
        )
        assert_eq(@relation_typing.sequence_keys(checked).length(), 0)
        assert_eq(@relation_typing.sequence_overlap(checked), Disallow)
        assert_eq(@relation_typing.sequence_contiguity(checked), Adjacent)
        assert_true(@relation_typing.sequence_per_key_guard(checked) is None)
        assert_true(@relation_typing.sequence_output_guard(checked) is None)
        assert_eq(@relation_typing.sequence_pattern_count(checked), 2)
      }
    }
  }
}

///|
test "sequence explicit grouping and modes are never replaced by omission defaults" {
  let body = cursor(
    sequence_authored_defaults_body(true, true, true)
    .replace(old="\"by\":[]", new="\"by\":[\"group\",\"group\"]")
    .replace(old="\"overlap\":\"disallow\"", new="\"overlap\":\"allow\"")
    .replace(
      old="\"contiguity\":\"adjacent\"",
      new="\"contiguity\":\"subsequence\"",
    ),
  )
  let checked = @relation_typing.check_sequence(
    body,
    @carrier.relation(sequence_rows(false)),
    None,
    limits(),
  ).unwrap()
  assert_eq(@relation_typing.sequence_keys(checked).length(), 2)
  assert_eq(@relation_typing.sequence_overlap(checked), Allow)
  assert_eq(@relation_typing.sequence_contiguity(checked), Subsequence)
  let fields = @schema.fields(@relation_typing.sequence_output(checked))
  assert_eq(
    fields.filter(field => field.name == Unqualified("group")).length(),
    1,
  )
}

///|
test "sequence omission never accepts malformed present values or missing required roles" {
  let original = sequence_authored_defaults_body(false, false, false)
  let input = @carrier.relation(sequence_rows(false))
  for
    (key, value) in [
      ("by", "null"),
      ("by", "\"group\""),
      ("overlap", "null"),
      ("overlap", "3"),
      ("overlap", "\"invented\""),
      ("contiguity", "null"),
      ("contiguity", "[]"),
      ("contiguity", "\"invented\""),
    ] {
    let text = original.replace(
      old="\"within\":20",
      new="\"within\":20,\"" + key + "\":" + value,
    )
    let issue = @relation_typing.check_sequence(
      cursor(text),
      input,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, InvalidBody)
    assert_eq(issue.path, [Key(key)])
  }
  for
    text in [
      original.replace(old="\"id\":\"id\",", new=""),
      original.replace(old="\"time\":\"clock\",", new=""),
      original.replace(old=",\"within\":20", new=""),
      original.replace(old="\"within\":20", new="\"within\":null"),
      original.replace(
        old="\"within\":20",
        new="\"within\":20,\"unexpected\":true",
      ),
    ] {
    assert_true(
      @relation_typing.check_sequence(cursor(text), input, None, limits())
      is Err(_),
    )
  }
}

///|
test "sequence completed defaults retain exact cumulative checking budgets" {
  let body = cursor(sequence_authored_defaults_body(false, false, false))
  let input = @carrier.relation(sequence_rows(false))
  let checked = @relation_typing.check_sequence(body, input, None, limits()).unwrap()
  let used = @relation_typing.sequence_usage(checked)
  let exact : @relation_typing.Limits = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_tokens: used.tokens,
  }
  assert_true(
    @relation_typing.check_sequence(body, input, None, exact) is Ok(_),
  )
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_tokens: used.tokens - 1, },
    ] {
    assert_true(
      @relation_typing.check_sequence(body, input, None, short) is Err(_),
    )
  }
}
