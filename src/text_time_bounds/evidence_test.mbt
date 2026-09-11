///|
test "input evidence uses independently fixed canonical preimages and digests" {
  let p = policy()
  // Preimages written from the normative three-case rule; fixed digests were
  // computed with Node crypto, not this emitter or a product lowerer.
  for
    (input, text, expected, nodes, depth) in [
      (
        from_contract(text_type(points=Some(2L), bytes=Some(8L)), p).unwrap(),
        "{\"max_codepoints\":2,\"max_utf8_bytes\":8,\"nullable\":false,\"type\":\"string\"}",
        "sha256:85a2941d561c553ee4609dee9564a1c33d1b08751fa91497c72f2f29ba4095fa",
        5,
        1,
      ),
      (
        from_value(value(text_type(), "\"é😀\""), p, max_text_bytes=6).unwrap(),
        "{\"value\":\"é😀\",\"version\":\"actql-literal-text-extent/0.1\"}",
        "sha256:5f8734970b74a7b533b4a7196402a6fe3cb2a75b1bfb5a0c6924795d12db194e",
        3,
        1,
      ),
      (
        from_value(value(text_type(nullable=true), "null"), p, max_text_bytes=0).unwrap(),
        "{\"value\":null,\"version\":\"actql-literal-text-extent/0.1\"}",
        "sha256:8c79be79b304cc0413f23347de62165c25f25b1ff121764c9fd9f97dd6e0a5a0",
        3,
        1,
      ),
      (
        from_value(
          value(
            @contract.primitive(@contract.TimestampType, nullable=false),
            "\"2024-01-01T00:00:00.000Z\"",
          ),
          p,
          max_text_bytes=24,
        ).unwrap(),
        "{\"value\":\"2024-01-01T00:00:00.000Z\",\"version\":\"actql-literal-text-extent/0.1\"}",
        "sha256:dc90edbdd683db74f7187496eb2c729be19b931e338174eb137ec3f9b1195ad3",
        3,
        1,
      ),
      (
        from_contract(text_type(), p).unwrap(),
        "{\"contract\":{\"nullable\":false,\"type\":\"string\"},\"policy\":{\"max_input_codepoints\":100,\"max_input_utf8_bytes\":400,\"max_output_bytes\":10000,\"max_pattern_bytes\":100,\"max_replacements\":101,\"version\":\"actql-text-time-host-policy/0.1\"},\"version\":\"actql-text-time-runtime-preflight/0.1\"}",
        "sha256:1bfa9a8b6764ad6a75193411bb814e4f6f50bd76b04bab9f5d2d5be3b1b6b35f",
        12,
        2,
      ),
    ] {
    let bytes = @utf8.encode(text).length()
    assert_eq("sha256:" + @sha.hex(@utf8.encode(text)), expected)
    for cap in [bytes - 1, bytes, bytes + 1] {
      for n in [nodes - 1, nodes, nodes + 1] {
        for d in [depth - 1, depth, depth + 1] {
          let success = cap >= bytes && n >= nodes && d >= depth
          let w = @encode.writer(cap, n, d)
          let emitted = try {
            emit_input_evidence(input, w)
            assert_eq(@encode.finish(w), text)
            true
          } catch {
            _ => false
          }
          assert_eq(emitted, success)
          let hashed = try {
            assert_eq(input_evidence_cid(input, cap, n, d), expected)
            true
          } catch {
            _ => false
          }
          assert_eq(hashed, success)
          let measured = try {
            let w = @encode.measuring_writer(cap, n, d)
            emit_input_evidence(input, w)
            assert_eq(@encode.finish_measurement(w), bytes)
            true
          } catch {
            _ => false
          }
          assert_eq(measured, success)
          if !success {
            let closed = try {
              @encode.finish(w) |> ignore
              false
            } catch {
              @encode.ClosedWriter => true
              _ => false
            }
            assert_true(closed)
          }
        }
      }
    }
  }
}

///|
test "extent content identities do not erase policy or producer applicability" {
  let p = policy()
  let changed = policy(output=20000L)
  let runtime = from_contract(text_type(), p).unwrap()
  assert_eq(input_evidence_source(runtime), "runtime_preflight")
  assert_true(
    input_evidence_cid(runtime, 1000, 100, 10) !=
    input_evidence_cid(
      from_contract(text_type(), changed).unwrap(),
      1000,
      100,
      10,
    ),
  )
  let checked = value(text_type(), "\"é😀\"")
  let literal = from_value(checked, p, max_text_bytes=6).unwrap()
  assert_eq(input_evidence_source(literal), "literal")
  assert_eq(
    input_evidence_cid(literal, 1000, 100, 10),
    input_evidence_cid(
      from_value(checked, changed, max_text_bytes=6).unwrap(),
      1000,
      100,
      10,
    ),
  )
  let out = derive_output(runtime, Utf8Truncate(Some(2.0))).unwrap()
  let child = from_output(out).unwrap()
  let independent = from_contract(output_contract(out), p).unwrap()
  assert_eq(input_evidence_source(child), "value_contract")
  assert_eq(
    input_evidence_cid(child, 1000, 100, 10),
    input_evidence_cid(independent, 1000, 100, 10),
  )
  assert_true(physical_equal(input_producer(child).unwrap(), out))
  assert_true(input_producer(independent) is None)
  assert_eq(input_origin(output_input(out)), RuntimePreflight)
}
