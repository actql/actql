///|
test "writer cancellation discards partial text and rejects all completion paths" {
  for buffered in [false, true] {
    let output = if buffered {
      buffered_hashing_writer(1000, 100, 10, 1000)
    } else {
      writer(1000, 100, 10)
    }
    begin_object(output)
    key(output, "private")
    string_value(output, "not-completed")
    cancel_writer(output)
    cancel_writer(output)
    assert_true(output.closed)
    assert_eq(output.frames.length(), 0)
    if output.output is BufferedHashOutput(buffer) {
      assert_eq(buffer.bytes, 0)
      assert_eq(buffer.text.to_string(), "")
    }
    if output.output is TextOutput(text) {
      assert_eq(text.to_string(), "")
    }
    let complete = try {
      finish(output) |> ignore
      false
    } catch {
      ClosedWriter => true
      _ => false
    }
    assert_true(complete)
    let append = try {
      end_object(output)
      false
    } catch {
      ClosedWriter => true
      _ => false
    }
    assert_true(append)
  }
}
