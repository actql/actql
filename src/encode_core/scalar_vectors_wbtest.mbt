///|
fn assert_encoding_closed(w : Writer) -> Unit raise {
  let closed = try {
    null_value(w)
    false
  } catch {
    ClosedWriter => true
    _ => false
  }
  assert_true(closed)
  let unpublished = try {
    ignore(finish_document(w))
    false
  } catch {
    ClosedWriter => true
    _ => false
  }
  assert_true(unpublished)
}
