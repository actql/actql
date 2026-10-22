///|
// Serialization-only whitebox carriers. They grant no admitted Run, Source,
// Store or cleanup authority; real Native custody cases retain those checks.
fn native_custody_record_contract(
  name : String,
  wire : String,
) -> PublicationContract raise {
  {
    name,
    identity_field: "fixture_cid",
    wire_usage: None,
    identity: "fixture",
    wire,
    value: @json.from_json(Json::null(), 1, 1, 1),
  }
}

///|
fn native_custody_record_inputs() -> (
  PublicationContract,
  CapturedEffectSourceArtifact,
) raise {
  let run = native_custody_record_contract(
    "run_definition", "{\"run\":\"original\"}",
  )
  let source : CapturedEffectSourceArtifact = {
    effect_id: "fixture-effect",
    artifact: native_custody_record_contract(
      "effect_source_artifact", "{\"source\":\"original\"}",
    ),
    holding_cid: "holding-original",
  }
  (run, source)
}

///|
test "Native Source custody record retains independent intent and terminal bytes" {
  let (run, source) = native_custody_record_inputs()
  // Literal vectors are independent of the product writer. The Int64 exceeds
  // the exact-integer range of binary64 and must remain a decimal JSON string.
  for
    (complete, expected, size) in [
      (
        false, "{\"cleanup_complete\":false,\"holding_cid\":\"holding-original\",\"payload_request\":\"{\\\"request\\\":\\\"original\\\"}\",\"physical_bytes\":\"9007199254740993\",\"physical_digest\":\"digest-original\",\"run_definition\":\"{\\\"run\\\":\\\"original\\\"}\",\"source_artifact\":\"{\\\"source\\\":\\\"original\\\"}\",\"store_authority_cid\":\"authority-original\",\"version\":\"actql-native-effect-source-custody/0.1\"}",
        360,
      ),
      (
        true, "{\"cleanup_complete\":true,\"holding_cid\":\"holding-original\",\"payload_request\":\"{\\\"request\\\":\\\"original\\\"}\",\"physical_bytes\":\"9007199254740993\",\"physical_digest\":\"digest-original\",\"run_definition\":\"{\\\"run\\\":\\\"original\\\"}\",\"source_artifact\":\"{\\\"source\\\":\\\"original\\\"}\",\"store_authority_cid\":\"authority-original\",\"version\":\"actql-native-effect-source-custody/0.1\"}",
        359,
      ),
    ] {
    let result = native_effect_source_custody_record_json(
      run, source, "{\"request\":\"original\"}", "authority-original", "digest-original",
      9007199254740993L, complete, size,
    )
    assert_eq(result, Ok(expected))
    assert_eq(@utf8.encode(result.unwrap()), @utf8.encode(expected))
    assert_eq(@utf8.encode(expected).length(), size)
    assert_eq(
      native_effect_source_custody_record_json(
        run,
        source,
        "{\"request\":\"original\"}",
        "authority-original",
        "digest-original",
        9007199254740993L,
        complete,
        size - 1,
      ),
      Err(Encoding),
    )
  }
}

///|
test "Native Source custody record preserves nested wire escaping and UTF8 bounds" {
  let (run, source) = native_custody_record_inputs()
  // Preserve decomposed Unicode, a supplementary scalar and each already
  // escaped nested JSON character. The nested document stays a JSON string.
  let request = "{\"text\":\"é😀\\\\\\\"\\r\\n\\t\\u0001\"}"
  let expected = "{\"cleanup_complete\":false,\"holding_cid\":\"holding-original\",\"payload_request\":\"{\\\"text\\\":\\\"é😀\\\\\\\\\\\\\\\"\\\\r\\\\n\\\\t\\\\u0001\\\"}\",\"physical_bytes\":\"0\",\"physical_digest\":\"digest-original\",\"run_definition\":\"{\\\"run\\\":\\\"original\\\"}\",\"source_artifact\":\"{\\\"source\\\":\\\"original\\\"}\",\"store_authority_cid\":\"authority-original\",\"version\":\"actql-native-effect-source-custody/0.1\"}"
  let result = native_effect_source_custody_record_json(
    run, source, request, "authority-original", "digest-original", 0L, false, 365,
  )
  assert_eq(result, Ok(expected))
  assert_eq(@utf8.encode(result.unwrap()), @utf8.encode(expected))
  assert_eq(@utf8.encode(expected).length(), 365)
  assert_eq(
    native_effect_source_custody_record_json(
      run, source, request, "authority-original", "digest-original", 0L, false, 364,
    ),
    Err(Encoding),
  )
}

///|
test "Native Source custody record refuses invalid limits and malformed Unicode" {
  let (run, source) = native_custody_record_inputs()
  for max_bytes in [-1, 0, 1] {
    assert_eq(
      native_effect_source_custody_record_json(
        run, source, "{\"request\":\"original\"}", "authority-original", "digest-original",
        0L, false, max_bytes,
      ),
      Err(Encoding),
    )
  }
  let invalid = String::from_array([(0xd800).unsafe_to_char()])
  assert_eq(
    native_effect_source_custody_record_json(
      run, source, invalid, "authority-original", "digest-original", 0L, false, 4096,
    ),
    Err(Encoding),
  )
  assert_eq(
    native_effect_source_custody_record_json(
      run, source, "{\"request\":\"original\"}", invalid, "digest-original", 0L,
      false, 4096,
    ),
    Err(Encoding),
  )
}
