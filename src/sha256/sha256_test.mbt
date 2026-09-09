///|
// NIST SHA-256 worked examples:
// https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf
test "SHA-256 known answers" {
  let vectors = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    (
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    ),
  ]
  for (input, expected) in vectors {
    assert_eq(text_hex(input), Ok(expected))
  }
}

///|
fn raw_utf16(units : Array[Int]) -> String {
  String::from_array(units.map(fn(unit) { unit.unsafe_to_char() }))
}

///|
test "SHA-256 text rejects unpaired surrogates with stable offsets" {
  let vectors = [
    ([0xD800], 0),
    ([0xDBFF], 0),
    ([0xDC00], 0),
    ([0xDFFF], 0),
    ([0xD800, 0x41], 0),
    ([0x41, 0xD800], 1),
    ([0x41, 0xDC00], 1),
    ([0xD800, 0xD800], 0),
    ([0xDC00, 0xD800], 0),
    ([0xD800, 0xD7FF], 0),
    ([0xDBFF, 0xE000], 0),
    ([0x41, 0xD83D, 0xDE00, 0xDC00], 3),
    ([0x41, 0xD83D, 0xDE00, 0xD800], 3),
  ]
  for (units, offset) in vectors {
    assert_eq(text_hex(raw_utf16(units)), Err(UnpairedSurrogate(offset)))
  }
  // A rejected call must not affect the next valid digest.
  assert_eq(
    text_hex("abc"),
    Ok("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
  )
}

///|
test "SHA-256 text accepts surrogate pairs and adjacent scalar boundaries" {
  let input = raw_utf16([
    0xD7FF, 0xD800, 0xDC00, 0xDBFF, 0xDFFF, 0xE000, 0xD83D, 0xDE00,
  ])
  // U+D7FF, U+10000, U+10FFFF, U+E000, U+1F600.
  let expected_utf8 = Bytes::from_array([
    0xED, 0x9F, 0xBF, 0xF0, 0x90, 0x80, 0x80, 0xF4, 0x8F, 0xBF, 0xBF, 0xEE, 0x80,
    0x80, 0xF0, 0x9F, 0x98, 0x80,
  ])
  assert_eq(text_hex(input), Ok(hex(expected_utf8)))
}

///|
// Additional fixed answers cross-checked with Node's crypto.createHash("sha256").
test "SHA-256 long messages" {
  assert_eq(
    text_hex(
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
    ),
    Ok("cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
  )
  assert_eq(
    hex(Bytes::from_array(Array::make(1000000, b'a'))),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
// Input byte i is i modulo 256. Expected digests are fixed Node crypto answers,
// not output from this implementation.
test "SHA-256 padding and block boundaries" {
  let vectors = [
    (55, "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59"),
    (56, "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562"),
    (63, "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488"),
    (64, "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108"),
    (65, "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781"),
    (119, "da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6"),
    (120, "f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c"),
    (256, "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880"),
  ]
  for (length, expected) in vectors {
    let bytes : Array[Byte] = []
    for i = 0; i < length; i = i + 1 {
      bytes.push((i % 256).to_byte())
    }
    assert_eq(hex(Bytes::from_array(bytes)), expected)
  }
}

///|
test "SHA-256 arbitrary bytes are not interpreted as text" {
  assert_eq(
    hex(Bytes::from_array([0x00, 0x80, 0xff])),
    "5240672d7b51756b829ad0ef8d9468b7a078afa2f410484fd3892dab47becb72",
  )
}

///|
test "SHA-256 raw digest, input preservation and independent calls" {
  let input = Bytes::from_array([0x61, 0x62, 0x63])
  let expected = Bytes::from_array([
    0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d,
    0xae, 0x22, 0x23, 0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10,
    0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
  ])
  let first = digest(input)
  assert_eq(first.length(), 32)
  assert_eq(first, expected)
  assert_eq(
    hex(input),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(hex(input).length(), 64)
  assert_eq(
    text_hex(""),
    Ok("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
  )
  assert_eq(digest(input), expected)
  assert_eq(first, expected)
  assert_eq(input, Bytes::from_array([0x61, 0x62, 0x63]))
}

///|
// UTF-8 and normalization-sensitive answers cross-checked with Node crypto.
test "SHA-256 text uses UTF-8 without NFC or newline normalization" {
  let japanese = "日本語😀"
  let utf8 = Bytes::from_array([
    0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0xac, 0xe8, 0xaa, 0x9e, 0xf0, 0x9f, 0x98, 0x80,
  ])
  assert_eq(text_hex(japanese), Ok(hex(utf8)))
  assert_eq(
    text_hex(japanese),
    Ok("94817f31083740f98f4b518e6989116e8aa08d8c6b76966abc057cc495564a17"),
  )
  assert_eq(
    text_hex("\u{e9}"),
    Ok("4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c"),
  )
  assert_eq(
    text_hex("e\u{301}"),
    Ok("bf12767b0f2a56b2190075bae8169f656e3ce8d6357d4aff184bc6c7ea48f9f6"),
  )
  assert_eq(
    text_hex("a\r\nb\rc\n"),
    Ok("7a481f8dd64383e5c6d7c7dd12a88d3594eed36da128736ebf4ffecb48f06cac"),
  )
  assert_eq(
    text_hex("a\nb\nc\n"),
    Ok("880553fca8fcea94e325ee2cfb48e5a985cc797f39a14cc6d3cedecfeb2ae4d2"),
  )
}
