///|
/// One-use consumer ledger over exact managed receiving views. This measures
/// top-level logical values, not physical bytes, row-array JSON or a CID.
/// Missing evidence requests ordinary ordered measurement, never a fabricated
/// first violation. No expression demand or execution is discharged here.
struct ManagedProducerMeasurement {
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  bindings : Array[Ref[Unit]]
  live : Array[() -> Bool]
  budget : FixedInputGuardBudget
  initial : FixedInputGuardMeasureLimits
  max_rows : Int
  max_value_bytes : Int
  identity : Ref[Bool]
  mut open : Bool
}

///|
/// Logical usage charged to this consumer ledger so far. This is not physical
/// work performed or permission to use unavailable material.
pub fn managed_producer_measurement_usage(
  producer : ManagedProducerMeasurement,
) -> (Int, Int, Int) {
  (
    producer.initial.max_work - producer.budget.work,
    producer.initial.max_bytes - producer.budget.bytes,
    producer.initial.max_nodes - producer.budget.nodes,
  )
}

///|
/// Finite exact-view/projection/copy rule. Successful per-column subtotals and
/// maxima were recorded during original admission, not re-read from data here.
/// Duplicate selected columns count twice; names do not affect value byte size.
pub fn[T] prepare_reused_managed_producer_measurement(
  inputs : Array[ManagedProducerRead[T]],
  target : @pipeline.Target,
  max_rows~ : Int,
  max_value_bytes~ : Int,
  limits : FixedInputGuardMeasureLimits,
  max_metadata_work : Int,
) -> Result[ManagedProducerMeasurement, FixedInputGuardIssue] {
  if max_rows < 0 ||
    max_value_bytes < 0 ||
    max_metadata_work < 0 ||
    limits.max_work < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if inputs.is_empty() {
    return Err(ForeignInput)
  }
  if inputs.length() > max_metadata_work {
    return Err(InputRepresentationRequired(0))
  }
  let mut remaining = max_metadata_work - inputs.length()
  let owner = inputs[0].receiver
  let prepared = @lower.bound_preparation(owner)
  if inputs.length() != @lower.preparation_input_count(prepared) {
    return Err(ForeignInput)
  }
  guard target is Step(index) &&
    index == @lower.node_count(prepared) - 1 &&
    @lower.preparation_schema_at(prepared, target) is Some(_) else {
    return Err(MissingOutput)
  }
  let budget : FixedInputGuardBudget = {
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  let live = []
  let bindings = []
  for index, input in inputs {
    if !physical_equal(input.receiver, owner) ||
      input.input_index != index ||
      !managed_producer_read_available(input) {
      return Err(ForeignInput)
    }
    let receipt = input.output.material.receipt
    if receipt.rows > max_rows {
      return Err(InputRows)
    }
    if input.columns.length() > remaining {
      return Err(InputRepresentationRequired(index))
    }
    remaining -= input.columns.length()
    // A summary proving failure may lack the contract's first diagnostic
    // location. Return to ordered measurement without publishing partial credit.
    if receipt.rows > budget.work ||
      (receipt.rows > 0 && receipt.measured_depth > budget.depth) {
      return Err(InputRepresentationRequired(index))
    }
    budget.work -= receipt.rows
    for column in input.columns {
      guard receipt.column_usage.get(column) is Some((bytes, nodes)) &&
        receipt.column_maxima.get(column) is Some(maximum) else {
        return Err(InputRepresentationRequired(index))
      }
      if maximum > max_value_bytes ||
        receipt.rows > budget.work ||
        bytes > budget.bytes ||
        nodes > budget.nodes {
        return Err(InputRepresentationRequired(index))
      }
      budget.work -= receipt.rows
      budget.bytes -= bytes
      budget.nodes -= nodes
    }
    bindings.push(input.identity)
    live.push(fn() { managed_producer_read_available(input) })
  }
  if live.any(check => !check()) {
    return Err(ForeignInput)
  }
  Ok({
    owner,
    target,
    bindings,
    live,
    budget,
    initial: limits,
    max_rows,
    max_value_bytes,
    identity: Ref(false),
    open: true,
  })
}

///|
/// Transfer the same remaining input ledger to output, once. The caller must
/// still enforce expression/root demands and other admitted execution duties.
pub fn prepare_reused_managed_output_values(
  producer : ManagedProducerMeasurement,
  values : ValueLimits,
) -> Result[ManagedOutputValues, ManagedOutputValueIssue] {
  if !producer.open ||
    producer.identity.val ||
    producer.live.any(check => !check()) {
    return Err(Guard(ForeignInput))
  }
  let stream = match
    prepare_managed_output_values(
      producer.owner,
      producer.target,
      producer.max_rows,
      values,
      producer.max_value_bytes,
      {
        max_work: producer.budget.work,
        max_bytes: producer.budget.bytes,
        max_nodes: producer.budget.nodes,
        max_depth: producer.budget.depth,
      },
    ) {
    Ok(stream) => stream
    Err(issue) => return Err(issue)
  }
  producer.open = false
  Ok({
    ..stream,
    managed_producer: Some(producer),
    measurement: producer.budget,
  })
}

///|
pub fn[T] managed_producer_measurement_matches_inputs(
  producer : ManagedProducerMeasurement,
  inputs : Array[ManagedProducerRead[T]],
) -> Bool {
  if inputs.length() != producer.bindings.length() {
    return false
  }
  for index, input in inputs {
    if !physical_equal(input.identity, producer.bindings[index]) ||
      !managed_producer_read_available(input) {
      return false
    }
  }
  true
}

///|
pub fn managed_output_value_managed_measurement_matches(
  receipt : ManagedOutputValueReceipt,
  producer : ManagedProducerMeasurement,
) -> Bool {
  receipt.managed_measurement is Some((identity, _)) &&
  physical_equal(identity, producer.identity) &&
  identity.val &&
  !producer.open &&
  producer.live.all(check => check())
}

///|
pub fn managed_output_value_managed_measurement_usage(
  receipt : ManagedOutputValueReceipt,
) -> (Int, Int, Int)? {
  receipt.managed_measurement.map(pair => pair.1)
}
