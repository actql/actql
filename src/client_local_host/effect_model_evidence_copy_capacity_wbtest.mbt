///|
test "optional Effect copy uses measured input and bundle demand without a destination allowance" {
  let writer = @encode.construction_measuring_writer(100000, 1000, 20)
  @encode.begin_object(writer)
  @encode.key(writer, "inputs")
  @encode.begin_object(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "observed-version")
  @encode.end_object(writer)
  @encode.end_object(writer)
  let frame = @encode.finish_construction_measurement(writer)
  let small = client_effect_model_evidence_copy_capacity(
    256, 10, 3, frame, 12, 2,
  ).unwrap()
  let larger = client_effect_model_evidence_copy_capacity(
    1024, 10, 3, frame, 12, 2,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(larger) >
    @execution.execution_capacity_retained_bytes(small),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(small) >=
    @execution.execution_capacity_retained_bytes(small),
  )
  assert_true(
    client_effect_model_evidence_copy_capacity(0, 10, 3, frame, 12, 2) is None,
  )
  assert_true(
    client_effect_model_evidence_copy_capacity(256, 10, 3, frame, -1, 2) is None,
  )
  assert_true(
    client_effect_model_evidence_copy_capacity(256, 10, 3, frame, 12, 129)
    is None,
  )
}
