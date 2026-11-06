///|
test "Salesforce original Base64 geometry includes full strings Unicode and failed prefixes" {
  for
    (text, expected) in [
      ("\"" + "a".repeat(250000) + "\"", 1),
      ("[0,0,0]", 5),
      ("{\"k\":\"é😀\"}", 4),
      ("{\"k\":\"[,\\\\\"}", 9),
      ("{\"k\":[0,", 7),
      ("{\"a\":0,\"a\":1}", 6),
    ] {
    let bytes = @utf8.encode(text)
    let encoded = @base64.encode(bytes)
    assert_eq(
      sf_initialization_original_geometry(encoded, 4000000, 400000),
      Some((bytes.length(), expected)),
    )
    // The existing admission limit remains a ceiling on allocation demand,
    // including duplicates and one-short/malformed grammar prefixes.
    assert_eq(
      sf_initialization_original_geometry(encoded, 4000000, 2),
      Some((bytes.length(), Int::min(expected, 2))),
    )
    assert_true(
      sf_initialization_original_geometry(encoded, bytes.length() - 1, 400000)
      is None,
    )
  }
}

///|
test "Salesforce original Base64 geometry refuses noncanonical padding without allocating a body" {
  for
    encoded in [
      "A", "====", "AA=A", "AA==AAAA", "AB==", "AAB=", "AA-_", "éAAA",
    ] {
    assert_true(
      sf_initialization_original_geometry(encoded, 4000000, 400000) is None,
    )
  }
  assert_eq(sf_initialization_original_geometry("", 1, 1), Some((0, 1)))
  assert_eq(sf_initialization_original_geometry("AA==", 1, 1), Some((1, 1)))
  assert_eq(sf_initialization_original_geometry("AAA=", 2, 1), Some((2, 1)))
  assert_eq(sf_initialization_original_geometry("AAAA", 3, 1), Some((3, 1)))
  assert_true(sf_initialization_original_geometry("AAAA", 0, 1) is None)
  assert_true(sf_initialization_original_geometry("AAAA", 3, 0) is None)
}

///|
test "Salesforce original structural quote keeps text and field work at unchanged admission limits" {
  let describe : @catalog.DescribeLimits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 32,
    max_fields: 1000,
    max_name_units: 200000,
  }
  let limits : @catalog.DeclarationLimits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 64,
  }
  let body = @utf8.encode("{\"description\":\"" + "a".repeat(250000) + "\"}")
  let encoded = @base64.encode(body)
  let original = initialization_original_construction_capacity(
    [Some(encoded)],
    984,
    [7],
    1446,
    10,
    14,
    describe,
    8000000,
    limits,
  ).unwrap()
  let old = initialization_construction_capacity(
    [body.length()],
    encoded.length(),
    984,
    [7],
    1446,
    10,
    14,
    describe,
    8000000,
    limits,
  ).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(old) > 536870912L)
  assert_true(
    @execution.execution_capacity_execution_bytes(original) < 536870912L,
  )
  // Independent exact old recipe with only the measured four-node bound.
  // The full byte input/normalizer/writers, F=1000 and text remain unchanged.
  let complete = initialization_construction_capacity(
    [body.length()],
    encoded.length(),
    984,
    [7],
    1446,
    10,
    14,
    { ..describe, max_nodes: 4, },
    8000000,
    limits,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(original),
    @execution.execution_capacity_execution_bytes(complete),
  )
  let short_text = initialization_original_construction_capacity(
    [Some("e30=")],
    984,
    [7],
    1446,
    10,
    14,
    describe,
    8000000,
    limits,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(original) >
    @execution.execution_capacity_execution_bytes(short_text),
  )
}
