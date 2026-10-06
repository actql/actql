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

///|
test "ASCII range hashing matches byte updates across block boundaries" {
  for length in [0, 1, 55, 56, 63, 64, 65, 127, 128, 257, 1024] {
    let input = "x".repeat(length)
    let h = hasher()
    update_ascii_range(h, "prefix" + input + "suffix", 6, 6 + length)
    assert_eq(finish_hex(h), hex(Bytes::from_array(Array::make(length, 0x78))))
  }
  let h = hasher()
  update_ascii_range(h, "ok", 0, 2)
  assert_true(
    try {
      update_ascii_range(h, "é", 0, 1)
      false
    } catch {
      InvalidAsciiRange => true
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
}

///|
test "ASCII range hashing completes partial blocks and closes on invalid full blocks" {
  for prefix in [0, 1, 17, 63, 64, 65] {
    for length in [0, 1, 63, 64, 65, 128, 129] {
      let h = hasher()
      update_ascii_range(h, "p".repeat(prefix), 0, prefix)
      update_ascii_range(h, "head" + "x".repeat(length), 4, 4 + length)
      let expected : Array[Byte] = []
      for _ in 0..<prefix {
        expected.push(0x70)
      }
      for _ in 0..<length {
        expected.push(0x78)
      }
      assert_eq(finish_hex(h), hex(Bytes::from_array(expected)))
    }
  }
  let h = hasher()
  let input = "x".repeat(80) + "é" + "x".repeat(80)
  assert_true(
    try {
      update_ascii_range(h, input, 0, input.length())
      false
    } catch {
      InvalidAsciiRange => true
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
}

///|
test "ASCII word absorption preserves every byte and rejects every invalid slot" {
  let pattern = String::from_array(
    Array::makei(256, i => (i % 128).unsafe_to_char()),
  )
  let expected = Bytes::from_array(Array::makei(256, i => (i % 128).to_byte()))
  for prefix in [0, 1, 31, 63] {
    let h = hasher()
    update(h, Bytes::make(prefix, 0x78))
    update_ascii_range(h, "head" + pattern + "tail", 4, 260)
    assert_eq(finish_hex(h), hex(Bytes::make(prefix, 0x78) + expected))
  }
  for bad in 0..<64 {
    let h = hasher()
    let input = "x".repeat(bad) + "é" + "x".repeat(63 - bad)
    assert_true(
      try {
        update_ascii_range(h, input, 0, 64)
        false
      } catch {
        InvalidAsciiRange => true
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
  }
}
