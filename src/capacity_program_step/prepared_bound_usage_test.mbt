///|
test "prepared bound admission preserves separate input and operand budgets" {
  let p = fusion_pipeline(false, 3)
  let seed = @capacity_program_step.derive_bound(p, 0, [], derive_limits()).unwrap().bound
  let inputs = Array::make(3, @capacity_program_step.StepInput(seed))
  let derived = @capacity_program_step.derive_bound(
    p,
    2,
    inputs,
    derive_limits(),
  ).unwrap()
  let plan = @capacity_program_step.prepare_bound_derivation(p, 2).unwrap()
  let claim = @capacity_program_step.checked_proof(derived.bound)
  // Three exact-copy traversals and five reserved operand passes per input.
  let (checked, usage) = @capacity_program_step.check_prepared_bound(
    plan,
    claim,
    inputs,
    18,
    max_input_work=3,
    max_operand_work=15,
  )
  assert_true(checked is Ok(_))
  assert_eq(usage, (3, 15))
  let (short, usage) = @capacity_program_step.check_prepared_bound(
    plan,
    claim,
    inputs,
    17,
    max_input_work=3,
    max_operand_work=15,
  )
  assert_true(short is Err(InputWorkLimit))
  assert_eq(usage, (2, 15))
  let (short, usage) = @capacity_program_step.check_prepared_bound(
    plan,
    claim,
    inputs,
    18,
    max_input_work=2,
    max_operand_work=15,
  )
  assert_true(short is Err(InputWorkLimit))
  assert_eq(usage, (2, 15))
  let (short, usage) = @capacity_program_step.check_prepared_bound(
    plan,
    claim,
    inputs,
    18,
    max_input_work=3,
    max_operand_work=14,
  )
  assert_true(short is Err(OperandWorkLimit))
  assert_eq(usage, (0, 0))
}
