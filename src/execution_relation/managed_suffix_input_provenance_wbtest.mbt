///|
// Real completed-copy, managed retention and checked receiving input. This
// component proves correspondence only, not Model or Effect authority.
fn suffix_original_managed_input_fixture() -> (
  CompletedOutput,
  ManagedCompletedOutput[Int],
  ManagedInputBinding,
  Ref[Bool],
) raise {
  let owner = capture_fixture()
  let live = Ref(true)
  let (snapshot, _) = retained_fixture(owner, live)
  let importing = prepare_completed_output_import(
    snapshot,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(importing, output_fixture_row(owner, row)).unwrap()
  }
  let original = finish_completed_output_import(importing).unwrap()
  let values = prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    4096,
    managed_test_measure_limits(),
    completed_projection=Some(original),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(values, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 7, 128L, () => live.val))).unwrap()
  for row in 0..<2 {
    append_completed_projection_managed_values(values, original, row).unwrap()
  }
  let material = retain_managed_output(
    retention,
    finish_managed_output_values(values).unwrap(),
  ).unwrap()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let port = prepare_managed_completion_port(
    selected_managed_execution_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
  ).unwrap()
  let output = complete_managed_output(port, ()).unwrap()
  let receiver = projected_consumer(
    owner,
    "[\"n\",\"s\"]",
    "[{\"select\":[\"n\",\"s\"]}]",
    target=Step(1),
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, output, 1000, 10000,
  ).unwrap()
  (original, output, managed_relation_input_binding(input), live)
}

///|
test "managed suffix completion keeps original occurrence DATA without input custody" {
  let (original, output, input, _) = suffix_original_managed_input_fixture()
  assert_true(input.ordinary is None)
  assert_true(input.relation is Some(_))
  assert_true(managed_input_binding_available(input))
  let occurrence = managed_completed_output_original_occurrence(output).unwrap()
  assert_true(
    completed_output_occurrence_matches_original(occurrence, original),
  )
}

///|
test "managed suffix occurrence rejects equal-valued foreign completion and changed target" {
  let (original, output, _, _) = suffix_original_managed_input_fixture()
  let (foreign, _, _, _) = suffix_original_managed_input_fixture()
  let occurrence = managed_completed_output_original_occurrence(output).unwrap()
  assert_false(
    completed_output_occurrence_matches_original(occurrence, foreign),
  )
  assert_false(
    completed_output_occurrence_matches_original(occurrence, {
      ..original,
      target: Step(0),
    }),
  )
}

///|
test "managed suffix occurrence DATA survives revocation without granting availability" {
  let (raw, output, input, live) = suffix_original_managed_input_fixture()
  let original_live = Ref(true)
  let original = restrict_completed_output(raw, () => original_live.val)
  let occurrence = managed_completed_output_original_occurrence(output).unwrap()
  original_live.val = false
  assert_false(completed_output_available(original))
  assert_true(managed_completed_output_available(output))
  assert_true(
    completed_output_occurrence_matches_original(occurrence, original),
  )
  original_live.val = true
  live.val = false
  assert_false(managed_completed_output_available(output))
  assert_false(managed_input_binding_available(input))
  assert_true(completed_output_available(original))
  // Historical equality is not an Allow; the consuming caller still requires
  // fresh original Model-use and final Result/export currentness.
  assert_true(
    completed_output_occurrence_matches_original(occurrence, original),
  )
}

///|
test "managed suffix occurrence refuses manually equal managed output provenance" {
  let output = managed_read_fixture(capture_fixture(), Ref(true))
  assert_true(managed_completed_output_original_occurrence(output) is None)
}

///|
test "managed suffix occurrence preserves the existing materialized original family" {
  let (original, _, _, _) = suffix_original_managed_input_fixture()
  let occurrence = completed_output_original_occurrence(original)
  assert_true(
    completed_output_occurrence_matches_original(occurrence, original),
  )
}
