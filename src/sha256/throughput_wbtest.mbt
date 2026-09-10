///|
// Byte-wise absorption is retained here only as a benchmark baseline.
fn bytewise_digest(input : Bytes) -> Bytes {
  let h = hasher()
  h.length = input.length().to_uint64()
  for byte in input {
    append(h, byte)
  }
  finish_bytes(h)
}

///|
test "SHA256 direct blocks 1 MiB" (it : @bench.T) {
  let input = Bytes::make(1048576, 0xab)
  it.bench(fn() { it.keep(digest(input)) })
}

///|
test "SHA256 bytewise baseline 1 MiB" (it : @bench.T) {
  let input = Bytes::make(1048576, 0xab)
  it.bench(fn() { it.keep(bytewise_digest(input)) })
}

///|
test "direct blocks preserve every partial block alignment" {
  let input = Bytes::from_array(Array::makei(513, i => i.to_byte()))
  let expected = bytewise_digest(input)
  for split = 0; split <= 129; split = split + 1 {
    let h = hasher()
    update(h, Bytes::from_array(Array::makei(split, i => input[i])))
    update(
      h,
      Bytes::from_array(
        Array::makei(input.length() - split, i => input[split + i]),
      ),
    )
    assert_eq(finish_digest(h), expected)
  }
}
