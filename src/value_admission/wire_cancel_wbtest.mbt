///|
test "wire cancellation drops a progressed long Reference continuation" {
  let wire = resource_reference_wire().replace(
    old="\"provider_namespace\":\"mail\"",
    new="\"provider_namespace\":\"" + String::make(1024, 'x') + "\"",
  )
  let contract = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let checked = issue_reference(
    bind_reference_issuer((_, candidate) => candidate == wire, _ => true),
    contract,
    wire,
    reference_limits(),
  ).unwrap()
  let writer = @encode.writer(4096, 64, 4)
  let cursor = start_wire_emit(checked.value, writer)
  let mut advanced = 0
  while @encode.writer_progress(writer).0 < 1024 {
    assert_false(advance_wire_emit(cursor))
    advanced += 1
    assert_true(advanced < 100)
  }
  guard cursor.pending[0] is ReferenceNext(reference) else {
    abort("expected the live Reference continuation after real output work")
  }
  let progress = @encode.writer_progress(writer)
  assert_true(progress.0 > 1024 && progress.0 < wire.length())
  cancel_wire_emit(cursor)
  cancel_wire_emit(cursor)
  assert_eq(wire_emit_pending_frames(cursor), 0)
  // Checking the borrowed inner handle distinguishes actually cancelling it
  // from merely discarding the outer frame during a conflict resolution.
  assert_true(@identity.advance_emit(reference))
  assert_eq(@encode.writer_progress(writer), progress)
  assert_true(
    try {
      @encode.finish(writer) |> ignore
      false
    } catch {
      @encode.InvalidStructure => true
      _ => false
    },
  )
  guard checked.value is Reference(source) else { abort("reference source") }
  assert_true(reference_available(source))
  assert_eq(reference_wire(source), wire)
}
