///|
test "Result import emitter matches independent input-position vectors" {
  // Expected hashes are independently fixed in the portability corpus,
  // not obtained from the issuer or the canonical encoder under test.
  let a = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let b = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let c = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let d = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let e = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  let cases = [
    (
      a, "rows", b, c, d, "81e86ff46a75d01544f1a6bba0ec84731355fe7a0f777ddf6fd90ba110650fba",
    ),
    (
      a, "other", b, c, d, "af427ef4243040832005f937b649334cda3247f5ec779983dc65bed1905c224a",
    ),
    (
      e, "rows", b, c, d, "93ce21b8e83d5ffd662d25036769875a27f4570852f7a0aef2b9e52eb7db129e",
    ),
    (
      a, "rows", e, c, d, "2b0ab336dffc32daa305b80681050e3b269ae9915da6e2eee1da10c9153ee267",
    ),
    (
      a, "rows", b, e, d, "56d25e97737b02092ca69a73f7703a365e3da421dfc1f50352c6bbcd899830d9",
    ),
    (
      a, "rows", b, c, e, "b30d493147c995e0f2785514fb09857819ee3ca0e87a870d9cc01e6d378e699f",
    ),
  ]
  for (consumer, name, interface, manifest, artifact, expected) in cases {
    let hash = @encode.hashing_writer(4096, 100, 8)
    emit_client_effect_result_import(
      hash,
      consumer,
      name,
      interface,
      manifest,
      artifact,
      None,
    )
    assert_eq(@encode.finish_hash(hash), expected)
    let wire = @encode.writer(4096, 100, 8)
    emit_client_effect_result_import(
      wire,
      consumer,
      name,
      interface,
      manifest,
      artifact,
      None,
    )
    let body = @encode.finish(wire)
    assert_eq(@sha.hex(@utf8.encode(body)), expected)
  }
}
