///|
fn policy(
  points? : Int64 = 100L,
  bytes? : Int64 = 400L,
  output? : Int64 = 10000L,
  replacements? : Int64 = 101L,
) -> @policy.Policy {
  let text = "{\"max_input_codepoints\":" +
    points.to_string() +
    ",\"max_input_utf8_bytes\":" +
    bytes.to_string() +
    ",\"max_output_bytes\":" +
    output.to_string() +
    ",\"max_pattern_bytes\":100,\"max_replacements\":" +
    replacements.to_string() +
    ",\"version\":\"actql-text-time-host-policy/0.1\"}"
  let bytes = @utf8.encode(text)
  @policy.admit(bytes, "sha256:" + @sha.hex(bytes), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn text_type(
  points? : Int64? = None,
  bytes? : Int64? = None,
  nullable? : Bool = false,
) -> @contract.Contract {
  @contract.string_contract(
    nullable~,
    max_codepoints=points,
    max_utf8_bytes=bytes,
  ).unwrap()
}

///|
fn value(contract : @contract.Contract, json : String) -> @value.CheckedValue {
  let node = @source.parse_json(json, {
    max_input_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @value.admit(contract, cursor, {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn replacement() -> @replacement.Replacement {
  @replacement.parse("ab$1$1", {
    max_input_bytes: 100,
    max_parts: 100,
    max_ast_bytes: 1000,
    max_ast_nodes: 100,
  }).unwrap()
}

///|
test "nested bounds preserve child derivations and selected policy without rescanning" {
  let p = policy()
  let root = from_contract(text_type(), p).unwrap()
  let child = derive_output(root, Utf8Truncate(Some(2.0))).unwrap()
  let input = from_output(child).unwrap()
  assert_eq(input_origin(input), DerivedOutput)
  assert_true(physical_equal(input_producer(input).unwrap(), child))
  assert_true(
    physical_equal(output_input(input_producer(input).unwrap()), root),
  )
  assert_eq(input_origin(root), RuntimePreflight)
  assert_eq(input_extent(input), (2L, 2L))
  assert_true(physical_equal(input_policy(input), p))
  assert_eq(output_bytes(derive_output(input, CaseFold).unwrap()), 32L)
  let number = derive_output(root, TryNumber).unwrap()
  assert_true(from_output(number) is Err(InvalidInputType))
  // Output allowance is not a waiver of the next operation's input ceiling.
  let p = policy(points=3L, bytes=10L, output=1000L)
  let root = from_contract(text_type(points=Some(3L), bytes=Some(10L)), p).unwrap()
  let child = derive_output(root, Nfkc).unwrap()
  assert_eq(output_bytes(child), 216L)
  assert_true(from_output(child) is Err(InputCeiling))
}

///|
test "text input extent combines contract evidence without silently clamping it" {
  let p = policy()
  for
    (contract, expected) in [
      (text_type(points=Some(10L)), (10L, 40L)),
      (text_type(bytes=Some(10L)), (10L, 10L)),
      (text_type(points=Some(10L), bytes=Some(5L)), (5L, 5L)),
      (text_type(points=Some(2L), bytes=Some(100L)), (2L, 8L)),
      (text_type(points=Some(0L)), (0L, 0L)),
    ] {
    let bound = from_contract(contract, p).unwrap()
    assert_eq(input_extent(bound), expected)
    assert_eq(input_origin(bound), ValueContract)
    assert_true(physical_equal(input_contract(bound), contract))
    assert_true(physical_equal(input_policy(bound), p))
    assert_true(input_value(bound) is None)
  }
  let runtime = from_contract(text_type(), p).unwrap()
  assert_eq(input_origin(runtime), RuntimePreflight)
  assert_eq(input_extent(runtime), (100L, 400L))
  assert_true(
    from_contract(text_type(points=Some(101L)), p) is Err(InputCeiling),
  )
  assert_true(
    from_contract(text_type(bytes=Some(401L)), p) is Err(InputCeiling),
  )
  assert_true(
    from_contract(@contract.primitive(@contract.NumberType, nullable=false), p)
    is Err(InvalidInputType),
  )
}

///|
test "checked values supply exact multibyte and known-null input extent" {
  let p = policy()
  let checked = value(text_type(nullable=true), "\"é😀\"")
  let input = from_value(checked, p, max_text_bytes=6).unwrap()
  assert_eq(input_origin(input), KnownValue)
  assert_eq(input_extent(input), (2L, 6L))
  assert_true(physical_equal(input_value(input).unwrap(), checked))
  assert_true(from_value(checked, p, max_text_bytes=5) is Err(BudgetExceeded))
  assert_true(from_value(checked, p, max_text_bytes=-1) is Err(InvalidLimits))
  assert_true(
    from_value(checked, policy(points=1L), max_text_bytes=6)
    is Err(InputCeiling),
  )
  let checked = value(text_type(nullable=true), "null")
  let input = from_value(checked, p, max_text_bytes=0).unwrap()
  assert_eq(input_extent(input), (0L, 0L))
  assert_eq(output_bytes(derive_output(input, Nfkc).unwrap()), 0L)
  let t = @contract.primitive(@contract.TimestampType, nullable=false)
  assert_eq(input_extent(from_contract(t, p).unwrap()), (24L, 24L))
  assert_eq(
    input_extent(
      from_value(value(t, "\"2024-01-01T00:00:00.000Z\""), p, max_text_bytes=24).unwrap(),
    ),
    (24L, 24L),
  )
}

///|
test "all text-time output formulas preserve conservative bounds and nullability" {
  let input = from_contract(
    text_type(points=Some(3L), bytes=Some(10L)),
    policy(),
  ).unwrap()
  // Independent fixed arithmetic: replacements=4, per-match=2+2*10,
  // regex_replace=10+4*22=98. NFKC=3*18*4, folding=3*4*4.
  for
    (operation, bytes, points) in [
      (Operation::SplitPart, 10L, 3L),
      (Substring(Some(1.0)), 4L, 3L),
      (Substring(Some(0.0)), 0L, 0L),
      (Substring(None), 10L, 3L),
      (Utf8Truncate(Some(2.0)), 2L, 2L),
      (Utf8Truncate(None), 10L, 3L),
      (RegexExtract, 10L, 3L),
      (Nfkc, 216L, 54L),
      (CaseFold, 48L, 12L),
      (RegexReplace(replacement()), 98L, 98L),
    ] {
    let out = derive_output(input, operation).unwrap()
    assert_true(physical_equal(output_input(out), input))
    assert_eq(output_bytes(out), bytes)
    match output_contract(out).shape {
      @contract.Text(limits) => {
        assert_eq(limits.max_codepoints, Some(points))
        assert_eq(limits.max_utf8_bytes, Some(bytes))
      }
      _ => fail("expected text extent")
    }
    assert_eq(output_contract(out).nullable, operation is RegexExtract)
  }
  for
    (operation, bytes, nullable) in [
      (Operation::TryNumber, 32L, true),
      (RegexMatch, 5L, false),
      (ParseTimestamp, 24L, false),
      (TryTimestamp, 24L, true),
    ] {
    let out = derive_output(input, operation).unwrap()
    assert_eq(output_bytes(out), bytes)
    assert_eq(output_contract(out).nullable, nullable)
  }
  let pattern = @timestamp.parse("yyyy-MM-dd", @timestamp.Format, {
    max_pattern_bytes: 100,
    max_components: 100,
    max_ast_bytes: 1000,
    max_ast_nodes: 100,
  }).unwrap()
  let t = from_contract(
    @contract.primitive(@contract.TimestampType, nullable=true),
    policy(),
  ).unwrap()
  assert_eq(
    output_bytes(derive_output(t, FormatTimestamp(pattern)).unwrap()),
    10L,
  )
  assert_true(
    derive_output(input, FormatTimestamp(pattern)) is Err(InvalidInputType),
  )
  assert_true(derive_output(t, SplitPart) is Err(InvalidInputType))
  let pattern = @timestamp.parse("yyyy-MM-dd", @timestamp.Parse, {
    max_pattern_bytes: 100,
    max_components: 100,
    max_ast_bytes: 1000,
    max_ast_nodes: 100,
  }).unwrap()
  assert_true(
    derive_output(t, FormatTimestamp(pattern)) is Err(InvalidPatternMode),
  )
}

///|
test "length operands are not evaluated and exact arithmetic rejects only actual ceiling excess" {
  let t = text_type(points=Some(3L), bytes=Some(10L))
  let input = from_contract(t, policy()).unwrap()
  for n in [-1.0, 0.5, 0.0 / 0.0, 1.0 / 0.0, 9007199254740992.0, -0.0] {
    assert_eq(
      output_bytes(derive_output(input, Substring(Some(n))).unwrap()),
      10L,
    )
    assert_eq(
      output_bytes(derive_output(input, Utf8Truncate(Some(n))).unwrap()),
      10L,
    )
  }
  assert_eq(
    output_bytes(
      derive_output(input, Substring(Some(9007199254740991.0))).unwrap(),
    ),
    10L,
  )
  for (cap, success) in [(97L, false), (98L, true), (99L, true)] {
    let input = from_contract(t, policy(output=cap, replacements=4L)).unwrap()
    let out = derive_output(input, RegexReplace(replacement()))
    assert_eq(out is Ok(_), success)
    if out is Ok(out) {
      assert_eq(output_replacements(out), Some(4L))
    }
  }
  let input = from_contract(t, policy(replacements=3L)).unwrap()
  assert_true(
    derive_output(input, RegexReplace(replacement())) is Err(ReplacementCeiling),
  )
  let maximum = 9007199254740991L
  let input = from_contract(
    text_type(bytes=Some(maximum)),
    policy(points=maximum, bytes=maximum, output=maximum, replacements=maximum),
  ).unwrap()
  assert_true(derive_output(input, Nfkc) is Err(OutputCeiling))
  assert_true(
    derive_output(input, RegexReplace(replacement())) is Err(ReplacementCeiling),
  )
  let input = from_contract(
    text_type(points=Some(maximum - 1L), bytes=Some(maximum)),
    policy(points=maximum, bytes=maximum, output=maximum, replacements=maximum),
  ).unwrap()
  assert_true(
    derive_output(input, RegexReplace(replacement())) is Err(OutputCeiling),
  )
}
