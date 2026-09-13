///|
struct GroupNumericSlot {
  operation : UnitOperationSource
  slot : @context.NumericSlot
  cid : String
}

///|
pub fn group_numeric_slot_operation(
  v : GroupNumericSlot,
) -> UnitOperationSource {
  v.operation
}

///|
pub fn group_numeric_slot_demand(v : GroupNumericSlot) -> @context.NumericSlot {
  v.slot
}

///|
pub fn group_numeric_slot_cid(v : GroupNumericSlot) -> String {
  v.cid
}

///|
pub fn emit_group_numeric_slot(
  v : GroupNumericSlot,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_numeric_slot_body(v.operation, v.slot, w)
}

///|
fn emit_numeric_slot_body(
  operation : UnitOperationSource,
  slot : @context.NumericSlot,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "aggregate_name")
  @encode.string_value(w, @relation.aggregate_name(slot.call))
  @encode.key(w, "reduction_profile_cid")
  @encode.string_value(w, @numeric.cid(slot.profile))
  @encode.key(w, "source_ordinal")
  @encode.number_value(w, operation.source_ordinal.to_double())
  @encode.key(w, "unit_definition_cid")
  @encode.string_value(w, operation.unit_definition_cid)
  @encode.key(w, "version")
  @encode.string_value(w, "actql-group-numeric-slot/0.1")
  @encode.end_object(w)
}

///|
fn prepare_program_numeric_slot_identities(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> Array[Array[GroupNumericSlot]] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let seen : Map[(Int, Int, String), Bool] = Map([])
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(GroupExecution(check))) &&
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
    let name = @relation.aggregate_name(slot.call)
    identity_charge(remaining, name.length())
    let key = (check.site.stage, check.site.step, name)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    let writer = identity_writer(remaining)
    emit_numeric_slot_body(operation, slot, writer) catch {
      e => raise Encoding(e)
    }
    let cid = identity_finish(remaining, writer)
    identity_charge(remaining, 1)
    result[check.site.stage].push({ operation, slot, cid, })
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_group_numeric_slot_count(
  program : CheckedProgram,
  stage : Int,
) -> Int? {
  program.numeric_slots.get(stage).map(v => v.length())
}

///|
pub fn unit_group_numeric_slot_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> GroupNumericSlot? {
  program.numeric_slots.get(stage).bind(v => v.get(index))
}
