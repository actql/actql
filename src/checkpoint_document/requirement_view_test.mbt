///|
test "Common claim view bounds do not accept empty extra unknown or substituted claims" {
  assert_eq(@checkpoint_document.requirement_max_arity("run_scope"), Some(1))
  assert_eq(@checkpoint_document.requirement_max_arity("effect_set"), Some(2))
  assert_eq(@checkpoint_document.requirement_max_arity("unknown"), None)
  assert_false(@checkpoint_document.requirements_valid("run_scope", []))
  assert_true(
    @checkpoint_document.requirements_valid("run_scope", [
      "invocation_scope_approved",
    ]),
  )
  assert_false(
    @checkpoint_document.requirements_valid("run_scope", [
      "effect_scope_approved",
    ]),
  )
  assert_true(
    @checkpoint_document.requirements_valid("effect_set", [
      "effect_scope_approved", "partial_application_accepted",
    ]),
  )
  assert_false(
    @checkpoint_document.requirements_valid("effect_set", [
      "effect_scope_approved", "partial_application_accepted", "effect_scope_approved",
    ]),
  )
  assert_false(@checkpoint_document.requirements_valid("unknown", []))
}
