///|
/// Compile-only codec boundary. This does not open crypto or disclose a key.
test "holder Review custody key requires exactly canonical 32 bytes" {
  let key = holder_effect_review_key("00".repeat(31) + "ff").unwrap()
  assert_eq(key.length(), 32)
  assert_eq(key[0], b'\x00')
  assert_eq(key[31], b'\xff')
  for
    invalid in [
      "",
      "00".repeat(31),
      "00".repeat(33),
      "00".repeat(31) + "FF",
      "00".repeat(31) + "gg",
      "00".repeat(32) + "\n",
    ] {
    assert_true(holder_effect_review_key(invalid) is None)
  }
}

///|
/// The configured key is local Store custody material, not a grant or Reviewer
/// identity. Refuse noncanonical or incomplete text instead of trimming values.
fn holder_effect_review_key(value : String) -> Bytes? {
  if value.length() != 64 {
    return None
  }
  let nibble = (value : UInt16) => {
    let number = value.to_int()
    if number >= 48 && number <= 57 {
      Some(number - 48)
    } else if number >= 97 && number <= 102 {
      Some(number - 97 + 10)
    } else {
      None
    }
  }
  let bytes : Array[Byte] = []
  for index in 0..<32 {
    guard nibble(value[index * 2]) is Some(high) &&
      nibble(value[index * 2 + 1]) is Some(low) else {
      return None
    }
    bytes.push((high * 16 + low).to_byte())
  }
  Some(Bytes::from_array(bytes))
}

///|
test "unavailable Review installation preserves roots then current refusal ordering" {
  let current_reads = Ref(0)
  let current = () => {
    current_reads.val += 1
    true
  }
  assert_false(holder_effect_review_installation_available(None, None, current))
  assert_false(
    holder_effect_review_installation_available(Some("policy"), None, current),
  )
  assert_false(
    holder_effect_review_installation_available(
      Some(""),
      Some("catalog"),
      current,
    ),
  )
  assert_eq(current_reads.val, 0)
  assert_false(
    holder_effect_review_installation_available(
      Some("policy"),
      Some("catalog"),
      current,
    ),
  )
  assert_eq(current_reads.val, 1)
  assert_false(
    holder_effect_review_installation_available(
      Some("policy"),
      Some("catalog"),
      () => {
        current_reads.val += 1
        false
      },
    ),
  )
  assert_eq(current_reads.val, 2)
}
