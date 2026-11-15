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

///|
test "compilation diagnostics retain the closed Effect materials cause family" {
  let cases : Array[(@run_host.ClientEffectRunMaterialsIssue, Int64)] = [
    (
      @run_host.Input(
        @run_host.MaterialsConstructionRefused("private-codec-boundary"),
      ),
      1L,
    ),
    (@run_host.Program(@run_host.RequestValuePolicyConstruction), 2L),
    (@run_host.Compilation(@run_host.Encoding), 3L),
    (@run_host.Binding(@run_host.ForeignCompilation), 4L),
    (@run_host.RunMismatch, 5L),
    (@run_host.Request(@run_host.IdentityMismatch), 6L),
    (@run_host.Normalization(@run_host.MissingOriginalJournal), 7L),
    (@run_host.TargetSelection(@run_host.Limit), 8L),
  ]
  for (cause, expected) in cases {
    assert_eq(local_compilation_effect_materials_tag(cause), expected)
  }
}
