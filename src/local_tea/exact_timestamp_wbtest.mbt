///|
test "event clock projection and watermark threshold preserve one nanosecond" {
  let before = timestamp("1970-01-01T00:00:00.009999999Z")
  let equal = timestamp("1970-01-01T00:00:00.010Z")
  let after = timestamp("1970-01-01T00:00:00.010000001Z")
  let threshold = @grid.from_finite_number(10.0).unwrap()
  assert_eq(@grid.compare_coordinates(event_window_coordinate(before, true).unwrap(), threshold), -1)
  assert_eq(@grid.compare_coordinates(event_window_coordinate(equal, true).unwrap(), threshold), 0)
  assert_eq(@grid.compare_coordinates(event_window_coordinate(after, true).unwrap(), threshold), 1)
  assert_true(event_window_coordinate(before, false) is None)
}

///|
test "actual watermark Owner marks only the original nanosecond-before record" {
  let producer = producer_owner(true)
  let output = @records.prepare_output(producer, @pipeline.Step(0), limits(), 4096L, fn() { true }).unwrap()
  for (index, instant) in [
    (0, "1970-01-01T00:00:00.009999999Z"),
    (1, "1970-01-01T00:00:00.010Z"),
    (2, "1970-01-01T00:00:00.010000001Z"),
  ] {
    @records.append_record(output, [
      (@schema.Unqualified("event_id"), number(index.to_double())),
      (@schema.Unqualified("occurred_at"), timestamp(instant)),
      (@schema.Unqualified("payload"), text("original")),
    ]).unwrap()
  }
  let source = @records.finish_output(output).unwrap()
  let owner = watermark_owner(producer, "mark")
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_watermark(@bounded.control(), sequence(owner), 0, read, limits(), 4096L, fn() { true }).unwrap()
  let completed = finish(execution)
  let storage = @records.completed_storage(completed).unwrap()
  for (row, late) in [(0, true), (1, false), (2, false)] {
    assert_true(field(storage, row, "late").value is @value.Boolean(actual) && actual == late)
    assert_true(field(storage, row, "payload").value is @value.Text("original"))
  }
  assert_eq(cleanup_watermark(execution), Ok(true))
  assert_true(@records.producer_read_available(read))
}
