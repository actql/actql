///|
test "publication diagnostics preserve original export failure and cleanup wrapper" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  local_publication_failure_tags(
    @local_host.Publication(Prepare(Export(UnknownResult))),
    emit,
  )
  assert_eq(fields.get(10), Some(10L))
  assert_eq(fields.get(11), Some(8006L))
  assert_eq(fields.get(12), Some(2L))
  assert_eq(fields.get(13), Some(2L))
  fields.clear()
  local_publication_failure_tags(
    @local_host.Publication(PrepareCleanup(InvalidCapturedRun, [])),
    emit,
  )
  assert_eq(fields.get(12), Some(1001L))
  assert_eq(fields.get(15), None)
}

///|
test "publication diagnostics retain Work export and exact SQL cause without payload" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  local_publication_failure_tags(@local_host.Work(Export(UnknownResult)), emit)
  assert_eq(fields.get(10), Some(10L))
  assert_eq(fields.get(11), Some(7008L))
  assert_eq(fields.get(12), Some(2L))
  fields.clear()
  local_publication_failure_tags(
    @local_host.Publication(Prepare(Output(0, Store(Database(BodyTooLarge))))),
    emit,
  )
  assert_eq(fields.get(11), Some(8006L))
  assert_eq(fields.get(12), Some(4L))
  assert_eq(fields.get(13), Some(201L))
  assert_eq(fields.get(15), Some(10L))
}
