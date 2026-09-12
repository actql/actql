///|
test "source state emitter matches fixed Stage-sensitive preimages" {
  for
    (stage, expected) in [
      (
        "first", "936b29016cf74b9d60f4a016aa01ae12703f89404812b8e667c05fb8d33ff830",
      ),
      (
        "second", "c04021aec9a3e6fc025bd3097eccc1b7561345864c91d10eb73c3061fabba934",
      ),
    ] {
    let writer = @encode.hashing_writer(1000, 100, 10)
    emit_source_state_body(
      "sha256:" + "a".repeat(64),
      stage,
      "rows",
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      writer,
    )
    assert_eq(@encode.finish_hash(writer), expected)
  }
}
