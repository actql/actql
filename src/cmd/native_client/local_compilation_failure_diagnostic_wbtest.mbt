///|
test "compilation diagnostics preserve typed original resource refusal" {
  let fields : Map[Int, Int64] = Map([])
  let tag = local_compilation_preparation_tag(
    @local_values.Capacity(Resource(ExecutionLimit)),
    (tag, value) => fields[tag] = value,
  )
  assert_eq(tag, 208L)
  assert_eq(fields.get(13), Some(7L))
  assert_eq(fields.length(), 1)
}

///|
test "compilation diagnostics distinguish constructor limits ownership and work" {
  assert_eq(local_compilation_plan_tag(@run_host.InvalidLimits), 1L)
  assert_eq(local_compilation_plan_tag(@run_host.Encoding), 8L)
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  assert_eq(
    local_compilation_preparation_tag(@local_values.WrongPhase, emit),
    2L,
  )
  assert_eq(
    local_compilation_preparation_tag(@local_values.Work(WorkLimit), emit),
    306L,
  )
  assert_eq(fields.length(), 0)
}
