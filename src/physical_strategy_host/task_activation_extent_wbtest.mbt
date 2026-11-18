///|
test "field-neutral activation carrier does not increase Normal logical representation" {
  // Independent constructor inventory under the SAME existing tariff, not
  // runtime heap/RSS measurement, a grant or a reservation. The root stores
  // one existing slot in both representations. None/Unarmed are inline.
  let old_none_slot = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let new_unarmed_slot = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(old_none_slot, 8L)
  assert_eq(new_unarmed_slot, old_none_slot)
  let old_grant : (Int, Int)? = Some((3, 7))
  let new_grant : CapturedTaskActivation = Granted(3, 7)
  assert_true(old_grant is Some((3, 7)))
  assert_true(new_grant is Granted(3, 7))
  // Old Some(pair): Some H1/R1/W1 plus pair H1/W2.
  let old_some_pair = @execution.preparation_representation_cost({
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // Actual new Granted(task,revision): one variant H1 and tag+two words W3.
  let new_granted = @execution.preparation_representation_cost({
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(old_some_pair, 64L)
  assert_eq(new_granted, 40L)
  assert_true(new_granted <= old_some_pair)
  // Observed(holder), its moved optional grant, latest facts and read wrappers
  // are additional Debug-only inventory. No existing spare field or quantity
  // is claimed for them; the selected caller must fund them before enabling.
}
