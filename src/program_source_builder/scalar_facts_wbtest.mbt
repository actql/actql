///|
fn scalar_fact_builder(input : Int, per_text : Int, total : Int) -> Builder {
  create(@origin.document("", input).unwrap(), {
    source: { max_input_bytes: input, max_nodes: 20, max_depth: 4, },
    tree: {
      max_nodes: 20,
      max_depth: 4,
      max_string_bytes: per_text,
      max_total_string_bytes: total,
    },
    max_origin_entries: 40,
    max_output_bytes: 1000,
  }).unwrap()
}

///|
// Retained original: first admit the input, then independently admit the output.
fn previous_normalized_scalar(
  builder : Builder,
  text : String,
  remaining : Int,
  identifier : Bool,
  admit : (String, Int) -> Result[Int, @scalar.Utf8AdmissionIssue],
) -> (String, Int) raise Failure {
  let allowance = builder.limits.tree.max_string_bytes.min(remaining)
  match admit(text, builder.limits.source.max_input_bytes.max(allowance)) {
    Err(@scalar.MalformedUtf16(_)) => raise Failure(InvalidScalar)
    Err(_) => raise Failure(StringLimit)
    Ok(_) => ()
  }
  let text = if identifier {
    match @canonical.normalize_nfc_lf(text) {
      Ok(text) => text
      Err(_) => raise Failure(InvalidScalar)
    }
  } else {
    text
  }
  match admit(text, allowance) {
    Ok(size) => (text, size)
    Err(_) => raise Failure(StringLimit)
  }
}

///|
fn scalar_fact_result(
  builder : Builder,
  text : String,
  remaining : Int,
  identifier : Bool,
  previous : Bool,
  admit : (String, Int) -> Result[Int, @scalar.Utf8AdmissionIssue],
) -> Result[(String, Int), Issue] {
  Ok(
    if previous {
      previous_normalized_scalar(builder, text, remaining, identifier, admit)
    } else {
      normalized(builder, text, remaining, identifier~, admit~)
    },
  ) catch {
    Failure(issue) => Err(issue)
  }
}

///|
test "raw builder scalar consumes one complete UTF8 admission and its original size" {
  let builder = scalar_fact_builder(100, 20, 100)
  for
    (text, bytes) in [
      ("", 0),
      ("type", 4),
      ("\r\n", 2),
      ("é", 2),
      ("e\u{0301}", 3),
      ("😀", 4),
      ("\u0000", 1),
    ] {
    let calls = Ref(0)
    let admit = (value, allowance) => {
      calls.val += 1
      @scalar.admit_utf8_length(value, allowance)
    }
    let prior = scalar_fact_result(builder, text, 20, false, true, admit)
    assert_eq(prior, Ok((text, bytes)))
    assert_eq(calls.val, 2)
    calls.val = 0
    assert_eq(scalar_fact_result(builder, text, 20, false, false, admit), prior)
    assert_eq(calls.val, 1)
  }
}

///|
test "raw scalar reuse retains tighter bounds and original malformed precedence" {
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  for
    (input, per_text, total, text, remaining, identifier, expected) in [
      (100, 2, 10, "界", 10, false, Err(StringLimit)),
      (100, 10, 2, "界", 2, false, Err(StringLimit)),
      (100, 1, 10, "a" + malformed, 1, false, Err(InvalidScalar)),
      (1, 1, 10, "a" + malformed, 1, false, Err(StringLimit)),
      (100, 10, 10, malformed, 10, false, Err(InvalidScalar)),
      (100, 10, 10, "x", -1, false, Err(StringLimit)),
      (100, 3, 10, "e\u{0301}", 3, true, Ok(("é", 2))),
      (100, 1, 10, "\r\n", 1, true, Ok(("\n", 1))),
      (100, 1, 10, "é", 1, true, Err(StringLimit)),
    ] {
    let builder = scalar_fact_builder(input, per_text, total)
    let previous = scalar_fact_result(
      builder, text, remaining, identifier, true, @scalar.admit_utf8_length,
    )
    assert_eq(previous, expected)
    assert_eq(
      scalar_fact_result(
        builder, text, remaining, identifier, false, @scalar.admit_utf8_length,
      ),
      previous,
    )
  }
}
