///|
test "Effect-only prelude uses the admitted Preview identity without a public Result" {
  let preview = effect_receipt_test_preview()
  assert_eq(
    computation_prelude_program_identity([], Some(preview)),
    Some(preview.program_definition_cid),
  )
  assert_eq(computation_prelude_program_identity([], None), None)
}
