///|
test "checked emitter inventory bounds payload frames without copying Contract text" {
  assert_true(@value_contract.checked_emission_construction_extent(0) is None)
  // One checked node: six member pairs/variants, <=14 active payload
  // alternatives, the original cursor/sort controls and two Array families.
  assert_eq(
    @value_contract.checked_emission_construction_extent(1),
    Some({ record_headers: 40L, reference_slots: 141L, scalar_words: 57L, }),
  )
  let large = @value_contract.checked_emission_construction_extent(2147483647).unwrap()
  assert_true(
    large.record_headers > 0L &&
    large.reference_slots > 0L &&
    large.scalar_words > 0L,
  )
}
