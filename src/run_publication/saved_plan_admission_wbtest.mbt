///|
test "saved compiled Plan value admission preserves full identity and wire checks" {
  let original = binding_construction_plan_fixture()
  let actual = admit_saved_compiled_plan_value(
    original.wire,
    original.value,
    65536,
    8192,
    64,
  ).unwrap()
  assert_eq(actual.wire, original.wire)
  assert_eq(actual.identity, original.identity)
  let foreign = @json.object_with_string_field(
    @json.object_without_field(original.value, "compiled_plan_cid").unwrap(),
    "compiled_plan_cid",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  assert_true(
    admit_saved_compiled_plan_value(original.wire, foreign, 65536, 8192, 64)
    is Err(IdentityMismatch),
  )
  assert_true(
    saved_compiled_plan_matches_definition(original, original, None) == false,
  )
  assert_true(saved_compiled_plan_validation_construction(0) is None)
  let small = saved_compiled_plan_validation_construction(10).unwrap()
  let large = saved_compiled_plan_validation_construction(100).unwrap()
  assert_true(large.reference_slots > small.reference_slots)
}
