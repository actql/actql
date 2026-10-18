///|
test "exact UTC Parameters preserve original strings in the existing identity preimage" {
  let declaration = "{\"x\":{\"type\":\"timestamp\"}}"
  let old = identity_ready(declaration, "{\"x\":\"1970-01-01T00:00:00.123Z\"}")
  let fine = identity_ready(
    declaration, "{\"x\":\"1970-01-01T00:00:00.123000001Z\"}",
  )
  assert_eq(
    identity_text(old),
    "{\"values\":{\"x\":\"1970-01-01T00:00:00.123Z\"},\"version\":\"actql-parameter-values/0.1\"}",
  )
  assert_eq(
    identity_text(fine),
    "{\"values\":{\"x\":\"1970-01-01T00:00:00.123000001Z\"},\"version\":\"actql-parameter-values/0.1\"}",
  )
  assert_not_eq(identity_cid(old), identity_cid(fine))
  // SHA-256 of the two literal preimages above, independently transcribed.
  assert_eq(
    identity_cid(old),
    "sha256:0fd34e5bc2ca23628fc928994cc1dc175557f2e6c690a41764bd49e87a0853aa",
  )
  assert_eq(
    identity_cid(fine),
    "sha256:6be6d54724ac639f90095920e3e22a2937c9dd527cf22cb7d6279becafd6b022",
  )
  assert_true(
    bind(declaration, "{\"x\":\"1970-01-01T00:00:00.1230Z\"}") is Err(_),
  )
}
