///|
fn measured_text_payload_bytes(utf16_units : Int) -> Int64 {
  utf16_units.to_int64() * 2L
}

///|
fn measured_text_payload_copies() -> Int {
  2
}
