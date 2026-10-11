///|
test "Foreign original Effect materials produce only a fixed diagnostic code" {
  assert_eq(
    source_compute_issue_code(@resident_host.ForeignEffectMaterials),
    "foreign-effect-materials",
  )
}
