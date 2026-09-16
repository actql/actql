///|
test "ASCII spans preserve mixed escaping Unicode and exact byte ceilings" {
  for length in [0, 1, 255, 256, 257, 258, 1024] {
    let prefix = "x".repeat(length)
    let value = prefix + "\"\\\n\u0001é😀" + prefix
    let expected = "\"" + prefix + "\\\"\\\\\\n\\u0001é😀" + prefix + "\""
    let bytes = length * 2 + 20
    for cap in [bytes - 1, bytes, bytes + 1] {
      for kind in 0..<4 {
        let out = match kind {
          0 => writer(cap, 1, 0)
          1 => measuring_writer(cap, 1, 0)
          2 => hashing_writer(cap, 1, 0)
          _ => buffered_hashing_writer(cap, 1, 0, cap)
        }
        let success = try {
          string_value(out, value)
          true
        } catch {
          OutputLimit => false
          _ => abort("unexpected encoding failure")
        }
        assert_eq(success, cap >= bytes)
        if success {
          match kind {
            0 => assert_eq(finish(out), expected)
            1 => assert_eq(finish_measurement_usage(out), (bytes, 1, 0))
            _ => {
              if kind == 3 {
                assert_eq(drain_hash_output(out), expected)
              }
              let (hex, actual_bytes, nodes) = finish_hash_usage(out)
              assert_eq(hex, @sha256.text_hex(expected).unwrap())
              assert_eq((actual_bytes, nodes), (bytes, 1))
            }
          }
        }
      }
    }
  }
}

///|
test "ASCII span exhaustion precedes later invalid Unicode and closes buffered output" {
  let value = "x".repeat(257) + "😀".unsafe_substring(start=0, end=1)
  for cap in [1, 256, 257, 258, 259] {
    for buffered in [false, true] {
      let out = if buffered {
        buffered_hashing_writer(1000, 1, 0, cap)
      } else {
        writer(cap, 1, 0)
      }
      let issue = try {
        string_value(out, value)
        "success"
      } catch {
        OutputLimit => "limit"
        InvalidUnicode => "unicode"
        _ => "other"
      }
      assert_eq(issue, if cap < 258 { "limit" } else { "unicode" })
      assert_true(
        try {
          string_value(out, "ok")
          false
        } catch {
          ClosedWriter => true
          _ => false
        },
      )
    }
  }
}
