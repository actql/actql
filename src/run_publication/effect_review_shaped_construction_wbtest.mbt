///|
// Independent pinned logical representation tariff (H16/R8/W8/U16=2/B1).
// Constructor facts never grant Resource credit or infer a physical ACK.
fn review_shape_test_cost(
  value : EffectPreviewIdentityConstructionInventory,
) -> Int64 {
  16L * value.record_headers +
  8L * value.reference_slots +
  8L * value.scalar_words +
  2L * value.owned_utf16_units +
  value.owned_wire_bytes
}

///|
test "review constructor bounds preserve the observed complete101-row projection under its original policy" {
  // Read-only offline geometry of the actual failed101-row fixture. No wire,
  // key, semantic admission, owner or permission is synthesized by these DATA.
  let input : @encode.EncodingConstructionGeometry = {
    bytes: 267145,
    nodes: 5406,
    depth: 10,
    arrays: 10,
    objects: 1014,
    fields: 5100,
    largest_object: 5100,
    strings: 5406,
    text_units: 267145,
  }
  let output = review_original_output_bound(input, 1, 101, 262144, 65536, 64).unwrap()
  // Independent complete output observation, including its real self-CID.
  assert_true(output.bytes >= 247266 && output.nodes >= 5280)
  assert_true(output.objects >= 1014 && output.arrays >= 6)
  assert_true(output.fields >= 5174 && output.strings >= 4056)
  assert_eq(output.bytes, 262144)
  let (returned, temporary) = review_original_inventory_for_geometry(
    input, 1, 101, 262144, 65536, 64,
  ).unwrap()
  let r = review_shape_test_cost(returned)
  let e = r + review_shape_test_cost(temporary)
  assert_true(r > 0L && e >= r && e < 536870912L)
  println(
    "Observed101 Review constructor component: R=\{r} E=\{e}; original selected512MiB limit unchanged",
  )
  // The original policy still bounds the renderer. Smaller policy/failing
  // prefixes keep the general category quote, never an invented empty shape.
  assert_true(review_original_output_bound(input, 1, 101, 32, 2, 1) is None)
  assert_true(
    review_original_inventory_for_geometry(input, 1, 101, 32, 2, 1) is Some(_),
  )
  assert_true(
    review_original_inventory_for_geometry(input, 1, 101, 0, 2, 1) is None,
  )
}
