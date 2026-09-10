///|
test "incremental hashing preserves padding boundaries and independent states" {
  for size in [0, 1, 55, 56, 63, 64, 65, 119, 120, 129, 4096] {
    let input = Bytes::from_array(Array::makei(size, i => i.to_byte()))
    for chunk in [1, 7, 55, 64, 65, 127] {
      let h = hasher()
      let other = hasher()
      update(other, b"abc")
      let mut offset = 0
      while offset < size {
        let count = if size - offset < chunk { size - offset } else { chunk }
        update(
          h,
          Bytes::from_array(Array::makei(count, i => input[offset + i])),
        )
        update(h, b"")
        offset += count
      }
      assert_eq(h.block.length(), 64)
      assert_eq(h.words.length(), 64)
      assert_eq(finish_hex(h), hex(input))
      assert_eq(
        finish_hex(other),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      )
      assert_true(
        try {
          update(h, b"")
          false
        } catch {
          ClosedHasher => true
          _ => false
        },
      )
      assert_true(
        try {
          ignore(finish_digest(h))
          false
        } catch {
          ClosedHasher => true
          _ => false
        },
      )
    }
    let h = hasher()
    for byte in input {
      update_byte(h, byte)
    }
    assert_eq(finish_digest(h), digest(input))
  }
}

///|
test "length overflow closes the hash state before accepting more bytes" {
  let h = hasher()
  h.length = 0x1ffffffffffffffeUL
  update_byte(h, 0x00)
  assert_eq(h.length, 0x1fffffffffffffffUL)
  assert_true(
    try {
      update(h, b"x")
      false
    } catch {
      MessageTooLong => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(finish_hex(h))
      false
    } catch {
      ClosedHasher => true
      _ => false
    },
  )
  assert_true(
    try {
      update_byte(h, 0x00)
      false
    } catch {
      ClosedHasher => true
      _ => false
    },
  )
}
