///|
test "Runtime projects only a Common bounded original claim view before exact validation" {
  assert_false(checkpoint_requirements_valid(RunScope, []))
  assert_true(
    checkpoint_requirements_valid(RunScope, [InvocationScopeApproved]),
  )
  assert_false(checkpoint_requirements_valid(RunScope, [EffectScopeApproved]))
  assert_true(checkpoint_requirements_valid(EffectSet, [EffectScopeApproved]))
  assert_true(
    checkpoint_requirements_valid(EffectSet, [
      EffectScopeApproved,
      PartialApplicationAccepted,
    ]),
  )
  assert_false(
    checkpoint_requirements_valid(EffectSet, [
      PartialApplicationAccepted,
      EffectScopeApproved,
    ]),
  )
  let extra = Array::make(10000, InvocationScopeApproved)
  assert_false(checkpoint_requirements_valid(RunScope, extra))
  assert_false(checkpoint_requirements_valid(EffectSet, extra))
}
