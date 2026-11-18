///|
fn review_limits(max_wire_bytes : Int) -> @checkpoint_document.Limits {
  { max_wire_bytes, max_nodes: 1000, max_depth: 16, }
}

// Independent literal preimages: sorted UTF-16 keys, exact DATA strings and
// root-only self exclusion. No product serializer generated these constants.

///|
let model_review_wire = "{\"displayed_scope\":{\"label\":\"é\\r\\n\",\"review_projection_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"},\"review_projection_cid\":\"sha256:e6ce9d746e603404a18538dd03b0c2e9cf17b103b9d0ab890082fb1faf639bd9\",\"version\":\"actql-run-review-projection/0.1\"}"

///|
let model_review_cid = "sha256:e6ce9d746e603404a18538dd03b0c2e9cf17b103b9d0ab890082fb1faf639bd9"

///|
let effect_review_wire = "{\"displayed_rows\":[{\"é\":\"é\\r\\n\",\"é\":\"é\",\"😀\":\"astral\",\"\":\"bmp\"}],\"review_projection_cid\":\"sha256:b632384371a1644f6d747d46b6a32fc759af749b602f074985c19a3509aba646\",\"version\":\"actql-review-projection/0.1\"}"

///|
let effect_review_cid = "sha256:b632384371a1644f6d747d46b6a32fc759af749b602f074985c19a3509aba646"

///|
test "pure review integrity preserves existing Model and opaque Effect preimages" {
  for
    (wire, cid) in [
      (model_review_wire, model_review_cid),
      (effect_review_wire, effect_review_cid),
    ] {
    assert_true(
      @checkpoint_document.review_bytes_match_cid(
        @utf8.encode(wire),
        cid,
        review_limits(10000),
      ),
    )
  }
}

///|
test "semantic review requires original canonical bytes while legacy keeps full-byte identity" {
  for wire in [" " + model_review_wire, "\u{feff}" + model_review_wire] {
    assert_false(
      @checkpoint_document.review_bytes_match_cid(
        @utf8.encode(wire),
        model_review_cid,
        review_limits(10000),
      ),
    )
  }
  assert_false(
    @checkpoint_document.review_bytes_match_cid(
      @utf8.encode(
        model_review_wire.replace(
          old="actql-run-review-projection/0.1",
          new="actql-run-review-projection/other",
        ),
      ),
      model_review_cid,
      review_limits(10000),
    ),
  )
  assert_true(
    @checkpoint_document.review_bytes_match_cid(
      b"",
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      review_limits(10000),
    ),
  )
  assert_true(
    @checkpoint_document.review_bytes_match_cid(
      Bytes::from_array([255]),
      "sha256:a8100ae6aa1940d0b663bb31cd466142ebbdbd5187131b92d93818987832eb89",
      review_limits(10000),
    ),
  )
}

///|
test "review byte allowance is checked before either identity path" {
  let raw = @utf8.encode(effect_review_wire)
  assert_true(
    @checkpoint_document.review_bytes_match_cid(
      raw,
      effect_review_cid,
      review_limits(raw.length()),
    ),
  )
  assert_false(
    @checkpoint_document.review_bytes_match_cid(
      raw,
      effect_review_cid,
      review_limits(raw.length() - 1),
    ),
  )
  assert_false(
    @checkpoint_document.review_bytes_match_cid(
      raw,
      model_review_cid,
      review_limits(10000),
    ),
  )
}
