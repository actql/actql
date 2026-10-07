///|
pub(all) enum ArrayProfileIssue {
  InvalidLimits
  BudgetExceeded
  InvalidCheckedProgram
  UnsupportedNestedArray(Int, Int, @expression.Location)
  UnsupportedNestedArrayColumn(Int, @pipeline.Target, String)
}

///|
// Inspect the admitted recursive type, not the shape of its runtime payload.
// Each visited contract consumes work; wide objects cannot enqueue unbounded
// children before the caller's budget is checked.
fn array_nested_contract(
  contract : @contract.Contract,
  max_work : Int,
) -> Result[(Bool, Int), ArrayProfileIssue] {
  let pending = [contract]
  let mut used = 0
  while pending.pop() is Some(current) {
    if used >= max_work {
      return Err(BudgetExceeded)
    }
    used += 1
    match current.shape {
      @contract.Array(item, ..) => {
        if item.shape is @contract.Array(_, ..) {
          return Ok((true, used))
        }
        if pending.length() >= max_work - used {
          return Err(BudgetExceeded)
        }
        pending.push(item)
      }
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        if count > max_work - used - pending.length() {
          return Err(BudgetExceeded)
        }
        for index in 0..<count {
          pending.push(@contract.field_at(fields, index).unwrap().contract)
        }
      }
      _ => ()
    }
  }
  Ok((false, used))
}

///|
// Read authoritative node contracts; do not infer a second type from SQL text.
// A STRUCT between arrays is allowed. Opaque JSON contents are not SQL arrays.
fn array_nested_source(
  expression : @typing.TypedExpression,
  max_work : Int,
) -> Result[(@expression.Location?, Int), ArrayProfileIssue] {
  let count = @typing.node_count(expression)
  if count > max_work {
    return Err(BudgetExceeded)
  }
  let mut used = 0
  for index in 0..<count {
    if used >= max_work {
      return Err(BudgetExceeded)
    }
    used += 1
    guard @typing.node_at(expression, index) is Some(node) else {
      return Err(InvalidCheckedProgram)
    }
    let (nested, work) = match
      array_nested_contract(node.contract, max_work - used) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    used += work
    if nested {
      guard @expression.origin(@typing.expression(expression), node.source)
        is Some(location) else {
        return Err(InvalidCheckedProgram)
      }
      return Ok((Some(location), used))
    }
  }
  Ok((None, used))
}

///|
// Aggregation and projection can create a type without an ARRAY expression
// root. Check the ordinary Relation contracts at producer boundaries as well.
fn array_pipeline_profile(
  pipeline : @pipeline.CheckedPipeline,
  max_work : Int,
) -> Result[((@pipeline.Target, String)?, Int), ArrayProfileIssue] {
  let mut used = 0
  let inputs = @pipeline.input_count(pipeline)
  let steps = @pipeline.step_count(pipeline)
  for index in 0..<(inputs + steps) {
    if used >= max_work {
      return Err(BudgetExceeded)
    }
    used += 1
    let target = if index < inputs {
      @pipeline.Input(index)
    } else {
      @pipeline.Step(index - inputs)
    }
    guard @pipeline.carrier_at(pipeline, target) is Some(carrier) else {
      return Err(InvalidCheckedProgram)
    }
    if carrier is @carrier.Relation(rows) {
      for field in 0..<@carrier.field_count(rows) {
        if used >= max_work {
          return Err(BudgetExceeded)
        }
        used += 1
        let field = @carrier.field_at(rows, field).unwrap()
        if field.contract is Some(contract) {
          let (nested, work) = match
            array_nested_contract(contract, max_work - used) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          used += work
          if nested {
            return Ok(
              (Some((target, @schema.reference_name(field.name))), used),
            )
          }
        }
      }
    }
  }
  Ok((None, used))
}

///|
/// Validate source ARRAY types after the ordinary checker has resolved
/// references and parameters. Machine Program input retains its recursive array
/// contract. This check neither evaluates expressions nor creates an Owner.
pub fn check_array_profile(
  program : @check.CheckedProgram,
  max_work~ : Int,
  max_slots~ : Int,
) -> Result[Unit, ArrayProfileIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  let mut slots_left = max_slots
  for unit in 0..<@check.unit_count(program) {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    guard @check.unit_pipeline(program, unit) is Some(pipeline) else {
      return Err(InvalidCheckedProgram)
    }
    let slots = match
      @pipeline.collect_expression_slots(
        pipeline,
        max_work=remaining,
        max_slots=slots_left,
      ) {
      Ok(slots) => slots
      Err(WorkLimit | SlotLimit) => return Err(BudgetExceeded)
      Err(_) => return Err(InvalidCheckedProgram)
    }
    remaining -= @pipeline.expression_slots_work(slots)
    let count = @pipeline.expression_slot_count(slots)
    slots_left -= count
    for index in 0..<count {
      guard @pipeline.expression_slot_at(slots, index) is Some(slot) else {
        return Err(InvalidCheckedProgram)
      }
      let (source, work) = match
        array_nested_source(slot.expression, remaining) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      remaining -= work
      if source is Some(source) {
        return Err(UnsupportedNestedArray(unit, slot.step, source))
      }
    }
    let (column, work) = match array_pipeline_profile(pipeline, remaining) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remaining -= work
    if column is Some((target, name)) {
      return Err(UnsupportedNestedArrayColumn(unit, target, name))
    }
  }
  Ok(())
}
