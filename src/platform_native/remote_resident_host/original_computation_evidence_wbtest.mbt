///|
/// Encoding fixtures are not issued Run/Receipt or Store proof. The production
/// caller supplies only original contracts from its admitted capture Owner.
fn original_computation_codec_fields() -> Array[(String, String)] {
  [
    ("run_definition_wire", "original Run"),
    ("invocation_wire", "original invocation"),
    ("result_definition_wire", "original definition"),
    ("result_artifact_wire", "original artifact"),
    ("result_manifest_wire", "original manifest"),
    ("computation_receipt_wire", "original Receipt"),
  ]
}

///|
test "original computation codec preserves all six original bodies without normalization" {
  let fields = original_computation_codec_fields()
  fields[3] = ("result_artifact_wire", "e\u0301\r\n\n\r\"\\")
  let wire = original_computation_evidence_wire(fields, {
    max_wire_bytes: 4096,
    max_nodes: 100,
    max_depth: 16,
  }).unwrap()
  let value = @canonical.from_json(
    @json.parse(wire),
    100,
    16,
    4096,
    data_keys=true,
  )
  assert_eq(@canonical.object_field_count(value), Some(6))
  for (name, original) in fields {
    assert_eq(original_review_text(value, name), Some(original))
  }
  assert_true(original_review_text(value, "result_artifact_wire") != Some("é"))
}

///|
test "original computation codec refuses incomplete foreign and oversized inventory" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 4096,
    max_nodes: 100,
    max_depth: 16,
  }
  assert_true(
    original_computation_evidence_wire([], limits) is Err(ForeignCapture),
  )
  let foreign = original_computation_codec_fields()
  foreign[2] = ("candidate_definition_wire", "candidate")
  assert_true(
    original_computation_evidence_wire(foreign, limits) is Err(ForeignCapture),
  )
  let extra = original_computation_codec_fields()
  extra.push(("extra", "extra"))
  assert_true(
    original_computation_evidence_wire(extra, limits) is Err(ForeignCapture),
  )
  let too_large = original_computation_codec_fields()
  too_large[3] = ("result_artifact_wire", "x".repeat(5000))
  assert_true(
    original_computation_evidence_wire(too_large, limits) is Err(Encoding),
  )
}

///|
test "original Review projection accepts only the named additional computation snapshot field" {
  let review = "original projection"
  let base = original_review_codec_wire(review)
  let fields = original_computation_codec_fields()
  let computation = original_computation_evidence_wire(fields, {
    max_wire_bytes: 4096,
    max_nodes: 100,
    max_depth: 16,
  }).unwrap()
  let add = name => {
    let writer = @encode.writer(4096, 100, 16)
    @encode.string_value(writer, computation)
    let encoded = @encode.finish(writer)
    let raw = base.replace_all(
      old="\"provider\":{",
      new="\"provider\":{\"" + name + "\":" + encoded + ",",
    )
    let value = @canonical.from_json(
      @json.parse(raw),
      100,
      16,
      4096,
      data_keys=true,
    )
    @canonical.stringify_value(value, 4096, 100, 16)
  }
  let wire = add("original_computation_wire")
  assert_true(
    original_review_codec_read(
      wire,
      original_review_codec_checkpoint(wire, review),
    )
    is Ok(_),
  )
  let foreign = add("candidate_computation_wire")
  assert_true(
    original_review_codec_read(
      foreign,
      original_review_codec_checkpoint(foreign, review),
    )
    is Err(BindingMismatch),
  )
}

///|
test "original computation decoder refuses unissued malformed and incomplete evidence" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 4096,
    max_nodes: 100,
    max_depth: 16,
  }
  let wire = original_computation_evidence_wire(
    original_computation_codec_fields(),
    limits,
  ).unwrap()
  // These labels are encoding fixtures, not proof of issued contracts.
  assert_true(
    original_computation_evidence_fields(wire, limits) is Err(Capture(_)),
  )
  assert_true(
    original_computation_evidence_fields("{}", limits) is Err(BindingMismatch),
  )
  assert_true(
    original_computation_evidence_fields(" { } ", limits)
    is Err(MalformedContinuation),
  )
  let duplicate = "{\"run_definition_wire\":\"original\",\"run_definition_wire\":\"replacement\"}"
  assert_true(
    original_computation_evidence_fields(duplicate, limits)
    is Err(MalformedContinuation),
  )
}
