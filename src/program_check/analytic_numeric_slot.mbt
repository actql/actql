///|
struct AnalyticNumericSlot {
  operation : UnitOperationSource
  slot : @context.AnalyticNumericSlot
  cid : String
}

///|
priv struct AnalyticNumericSlotIdentities {
  units : Array[Array[AnalyticNumericSlot]]
  occurrences : Array[AnalyticNumericSlot?]
}

///|
pub fn analytic_numeric_slot_operation(
  v : AnalyticNumericSlot,
) -> UnitOperationSource {
  v.operation
}

///|
pub fn analytic_numeric_slot_demand(
  v : AnalyticNumericSlot,
) -> @context.AnalyticNumericSlot {
  v.slot
}

///|
pub fn analytic_numeric_slot_cid(v : AnalyticNumericSlot) -> String {
  v.cid
}

///|
pub fn emit_analytic_numeric_slot(
  v : AnalyticNumericSlot,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_analytic_numeric_slot_body(v.operation, v.slot, w)
}

///|
fn emit_analytic_numeric_slot_body(
  operation : UnitOperationSource,
  slot : @context.AnalyticNumericSlot,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "output_name")
  @encode.string_value(w, slot.frame_call.name)
  @encode.key(w, "reduction_profile_cid")
  @encode.string_value(w, @numeric.cid(slot.profile))
  @encode.key(w, "source_ordinal")
  @encode.number_value(w, operation.source_ordinal.to_double())
  @encode.key(w, "unit_definition_cid")
  @encode.string_value(w, operation.unit_definition_cid)
  @encode.key(w, "version")
  @encode.string_value(w, "actql-analytic-numeric-slot/0.1")
  @encode.end_object(w)
}

///|
fn prepare_program_analytic_numeric_slot_identities(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> AnalyticNumericSlotIdentities raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let count = @context.operation_closure_count(closure)
  identity_charge(remaining, count)
  let occurrences = Array::make(count, None)
  let by_source : Map[(Int, Int, String), AnalyticNumericSlot] = Map([])
  guard units.get(0) is Some(first) else { raise ForeignOwner }
  let root = @pipeline.source(first.pipeline)
  let seen : Map[(Int, Int, String), Bool] = Map([])
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(AnalyticExecution(check))) &&
      check.rule is CaptureNumericObservation(slot) else {
      continue
    }
    guard units.get(check.site.stage) is Some(unit) else { raise ForeignOwner }
    if !physical_equal(unit.pipeline, check.site.pipeline) {
      continue
    }
    guard physical_equal(slot.site, check.site) &&
      physical_equal(slot.step, check.step) &&
      slot.input == check.input &&
      unit_operation_source(unit, check.site.pipeline, check.site.step)
      is Some(operation) else {
      raise ForeignOwner
    }
    let name = slot.frame_call.name
    identity_charge(remaining, name.length())
    let key = (check.site.stage, check.site.step, name)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    let writer = identity_writer(remaining)
    emit_analytic_numeric_slot_body(operation, slot, writer) catch {
      e => raise Encoding(e)
    }
    let cid = identity_finish(remaining, writer)
    identity_charge(remaining, 1)
    let retained = AnalyticNumericSlot::{ operation, slot, cid, }
    guard @decode.tree_index(root, @pipeline.source(check.site.pipeline))
      is Some(coordinate) else {
      raise ForeignOwner
    }
    let source_key = (coordinate, check.site.step, name)
    if by_source.contains(source_key) {
      raise ForeignOwner
    }
    by_source[source_key] = retained
    result[check.site.stage].push(retained)
  }
  // Resolve every imported visit to the producer's already-built slot. Arena
  // coordinates are lookup aids only; exact checked owners are still verified.
  for index in 0..<count {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(AnalyticExecution(check))) &&
      check.rule is CaptureNumericObservation(slot) else {
      continue
    }
    let name = slot.frame_call.name
    identity_charge(remaining, name.length())
    guard @decode.tree_index(root, @pipeline.source(check.site.pipeline))
      is Some(coordinate) &&
      by_source.get((coordinate, check.site.step, name)) is Some(retained) &&
      slot.requirement_index == index &&
      physical_equal(retained.slot.step, slot.step) &&
      physical_equal(retained.slot.call, slot.call) &&
      physical_equal(retained.slot.profile, slot.profile) else {
      raise ForeignOwner
    }
    occurrences[index] = Some(retained)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  { units: result, occurrences, }
}

///|
pub fn unit_analytic_numeric_slot_count(
  program : CheckedProgram,
  stage : Int,
) -> Int? {
  program.analytic_numeric_slots.units.get(stage).map(v => v.length())
}

///|
pub fn unit_analytic_numeric_slot_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> AnalyticNumericSlot? {
  program.analytic_numeric_slots.units.get(stage).bind(v => v.get(index))
}

///|
/// Read the producer-owned slot for a requirement in this Program's operation
/// closure, including an imported visit. Non-numeric and invalid indices return None.
pub fn analytic_numeric_slot_for_requirement(
  program : CheckedProgram,
  index : Int,
) -> AnalyticNumericSlot? {
  program.analytic_numeric_slots.occurrences.get(index).bind(v => v)
}
