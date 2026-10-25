///|
test "finite scalar wire allowance includes the 25-byte fixed-negative spelling" {
  let value = -0.0000010000000000000002
  let out = writer(25, 1, 1)
  number_value(out, value)
  let document = finish_document(out)
  assert_eq(document_text(document), "-0.0000010000000000000002")
  assert_eq(document_bytes(document), 25)
  let short = try {
    let out = writer(24, 1, 1)
    number_value(out, value)
    finish_document(out) |> ignore
    false
  } catch {
    OutputLimit => true
    _ => false
  }
  assert_true(short)
}
