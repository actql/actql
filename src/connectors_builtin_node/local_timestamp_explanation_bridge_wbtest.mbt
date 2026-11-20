///|
extern "js" fn timestamp_explanation_actual_option(
  description : String?,
  absent : String?,
) -> Bool =
  #|(description,absent)=>typeof description==='string' &&
  #| description.includes('2026-01-02T03:04:05.123Z') &&
  #| description.includes('3-9 fractional digits') && absent===undefined

///|
test "timestamp explanation Node bridge preserves actual String Option ABI" {
  assert_true(
    timestamp_explanation_actual_option(
      local_managed_failure_explanation(
        "evaluation.timestamp_canonical_required",
      ),
      local_managed_failure_explanation("evaluation.invalid_operand"),
    ),
  )
}
