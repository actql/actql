///|
/// Shared logical checks, independent of the algorithm that produces pairs.
/// Both Local execution and native preflight use this exact failure ordering.
fn[L : IndexedRows, R : IndexedRows] validate_join_obligations(
  profile : @lower.PreparedInnerJoin,
  left : L,
  right : R,
  keys : Array[(Int, Int)],
  orders : Array[Array[ColumnOrder]],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, RowIssue] {
  let assertion = @lower.inner_join_assertion(profile)
  let fail_null = @lower.inner_join_fails_null(profile)
  if validate_join_index_input(left, keys, true, fail_null, control) is Err(e) {
    return Err(join_index_failure(e))
  }
  if assertion is Some(OneToOne | OneToMany) &&
    validate_join_unique_indices(left, orders[0], true, control, workspace)
    is Err(e) {
    return Err(join_index_failure(e))
  }
  if validate_join_index_input(right, keys, false, fail_null, control) is Err(e) {
    return Err(join_index_failure(e))
  }
  if assertion is Some(OneToOne | ManyToOne) &&
    validate_join_unique_indices(right, orders[1], false, control, workspace)
    is Err(e) {
    return Err(join_index_failure(e))
  }
  Ok(())
}

///|
pub(all) struct FixedJoinValidationLimits {
  max_rows : Int
  max_work : Int
  max_entries : Int
}

///|
/// Preflight evidence for exact immutable fixed inputs, not a Compute result or
/// proof of output guards. It retains liveness until execution has completed.
struct FixedJoinValidation {
  owner : @lower.BoundPrepared
  profile : @lower.PreparedInnerJoin
  inputs : Array[ProducerRead]
  work : Int
  peak : Int
}

///|
pub fn validate_fixed_join_inputs(
  owner : @lower.BoundPrepared,
  profile : @lower.PreparedInnerJoin,
  inputs : Array[ProducerRead],
  limits : FixedJoinValidationLimits,
) -> Result[FixedJoinValidation, RowIssue] {
  if limits.max_rows < 0 || limits.max_work < 0 || limits.max_entries < 0 {
    return Err(InvalidRowLimits)
  }
  let prepared = @lower.bound_preparation(owner)
  let count = @lower.preparation_input_count(prepared)
  if count < 1 ||
    count > 2 ||
    inputs.length() != count ||
    @lower.node_count(prepared) != 1 {
    return Err(InputMismatch)
  }
  let step = @lower.node_at(prepared, 0).unwrap()
  guard @lower.inner_join_matches_node(profile, step) &&
    @lower.node_input_target(step, 0) is Some(@pipeline.Input(li)) &&
    @lower.node_input_target(step, 1) is Some(@pipeline.Input(ri)) else {
    return Err(OwnerMismatch)
  }
  let control = ControlBudget::{ remaining: limits.max_work, max_frames: 0, }
  let workspace = RowWorkspace::{ limit: limits.max_entries, live: 0, peak: 0, }
  if !reserve_slots(workspace, count + 2) || !spend_control(control, count) {
    return Err(RowLimit)
  }
  for port in 0..<count {
    let input = inputs[port]
    if !physical_equal(producer_read_receiver(input), owner) {
      return Err(OwnerMismatch)
    }
    if producer_read_input_index(input) != port ||
      !producer_read_available(input) {
      return Err(InputMismatch)
    }
    if producer_read_row_count(input) > limits.max_rows {
      return Err(RowLimit)
    }
  }
  let resolve = fn(input : ProducerRead, field : @schema.FieldName) -> Int? {
    let name = @schema.reference_name(field)
    for column in 0..<@schema.field_count(input.schema) {
      let candidate = @schema.field_at(input.schema, column).unwrap().name
      if !spend_control(control, 1) ||
        !spend_control_text(control, name) ||
        !spend_control_text(control, @schema.reference_name(candidate)) {
        return None
      }
      if candidate == field {
        return Some(column)
      }
    }
    None
  }
  let keys = []
  let orders : Array[Array[ColumnOrder]] = [[], []]
  for index in 0..<@lower.inner_join_key_count(profile) {
    if !reserve_slots(workspace, 4) || !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let (lf, rf) = @lower.inner_join_key_at(profile, index).unwrap()
    guard resolve(inputs[li], lf) is Some(lc) &&
      resolve(inputs[ri], rf) is Some(rc) else {
      return Err(RowLimit)
    }
    keys.push((lc, rc))
    orders[0].push({ column: lc, descending: false, nulls_first: true, })
    orders[1].push({ column: rc, descending: false, nulls_first: true, })
  }
  match
    validate_join_obligations(
      profile,
      ProducerGuardRows::{ input: inputs[li], },
      ProducerGuardRows::{ input: inputs[ri], },
      keys,
      orders,
      control,
      workspace,
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      Ok({
        owner,
        profile,
        inputs: inputs.copy(),
        work: limits.max_work - control.remaining,
        peak: workspace.peak,
      })
  }
}

///|
pub fn fixed_join_validation_matches(
  validation : FixedJoinValidation,
  owner : @lower.BoundPrepared,
  profile : @lower.PreparedInnerJoin,
  inputs : Array[ProducerRead],
) -> Bool {
  if !physical_equal(owner, validation.owner) ||
    !physical_equal(profile, validation.profile) ||
    inputs.length() != validation.inputs.length() {
    return false
  }
  for port in 0..<inputs.length() {
    if !physical_equal(inputs[port], validation.inputs[port]) ||
      !producer_read_available(inputs[port]) {
      return false
    }
  }
  true
}

///|
/// Physical preflight work and peak scratch slots; not a language budget credit.
pub fn fixed_join_validation_usage(
  validation : FixedJoinValidation,
) -> (Int, Int) {
  (validation.work, validation.peak)
}
