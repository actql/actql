///|
struct PivotNumericSlot {
  operation : UnitOperationSource
  demand : @context.PivotNumericDemand
  name : String
  cid : String
}

///|
// A zero-column numeric pivot still owns a demand. None means a different
// requirement, whereas Some(bundle with no slots) means the empty axis.
struct PivotNumericSlots {
  operation : UnitOperationSource
  demand : @context.PivotNumericDemand
  slots : Array[PivotNumericSlot]
}

///|
priv struct PivotNumericSlotIdentities {
  units : Array[Array[PivotNumericSlot]]
  occurrences : Array[PivotNumericSlots?]
}

///|
pub fn pivot_numeric_slot_operation(
  v : PivotNumericSlot,
) -> UnitOperationSource {
  v.operation
}

///|
pub fn pivot_numeric_slot_demand(
  v : PivotNumericSlot,
) -> @context.PivotNumericDemand {
  v.demand
}

///|
pub fn pivot_numeric_slot_name(v : PivotNumericSlot) -> String {
  v.name
}

///|
pub fn pivot_numeric_slot_cid(v : PivotNumericSlot) -> String {
  v.cid
}

///|
pub fn pivot_numeric_slot_reduction(
  v : PivotNumericSlot,
) -> @numeric.Operation? {
  match @relation.pivot_function(v.demand.pivot) {
    @relation.Sum => Some(@numeric.Sum)
    @relation.Avg => Some(@numeric.Average)
    _ => None
  }
}

///|
pub fn emit_pivot_numeric_slot(
  v : PivotNumericSlot,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_pivot_numeric_slot_body(v.operation, v.demand, v.name, w)
}

///|
fn emit_pivot_numeric_slot_body(
  operation : UnitOperationSource,
  demand : @context.PivotNumericDemand,
  name : String,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "output_name")
  @encode.string_value(w, name)
  @encode.key(w, "reduction_profile_cid")
  @encode.string_value(w, @numeric.cid(demand.profile))
  @encode.key(w, "source_ordinal")
  @encode.number_value(w, operation.source_ordinal.to_double())
  @encode.key(w, "unit_definition_cid")
  @encode.string_value(w, operation.unit_definition_cid)
  @encode.key(w, "version")
  @encode.string_value(w, "actql-pivot-numeric-slot/0.1")
  @encode.end_object(w)
}

///|
fn prepare_program_pivot_numeric_slot_identities(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> PivotNumericSlotIdentities raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let count = @context.operation_closure_count(closure)
  identity_charge(remaining, count)
  let occurrences = Array::make(count, None)
  let by_source : Map[(Int, Int), PivotNumericSlots] = Map([])
  guard units.get(0) is Some(first) else { raise ForeignOwner }
  let root = @pipeline.source(first.pipeline)
  for index in 0..<count {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(PivotExecution(check))) &&
      check.rule is CaptureNumericObservations(demand) else {
      continue
    }
    guard units.get(check.site.stage) is Some(unit) else { raise ForeignOwner }
    if !physical_equal(unit.pipeline, check.site.pipeline) {
      continue
    }
    guard physical_equal(demand.site, check.site) &&
      physical_equal(demand.step, check.step) &&
      physical_equal(demand.pivot, check.pivot) &&
      demand.input == check.input &&
      demand.requirement_index == index &&
      unit_operation_source(unit, check.site.pipeline, check.site.step)
      is Some(operation) &&
      @decode.tree_index(root, @pipeline.source(check.site.pipeline))
      is Some(coordinate) else {
      raise ForeignOwner
    }
    let key = (coordinate, check.site.step)
    if by_source.contains(key) {
      raise ForeignOwner
    }
    identity_charge(remaining, 1)
    let slots = []
    for column in 0..<@context.pivot_numeric_slot_count(demand) {
      identity_charge(remaining, 1)
      let name = @context.pivot_numeric_slot_name_at(demand, column).unwrap()
      identity_charge(remaining, name.length())
      let writer = identity_writer(remaining)
      emit_pivot_numeric_slot_body(operation, demand, name, writer) catch {
        e => raise Encoding(e)
      }
      let cid = identity_finish(remaining, writer)
      identity_charge(remaining, 2)
      let slot = PivotNumericSlot::{ operation, demand, name, cid, }
      slots.push(slot)
      result[check.site.stage].push(slot)
    }
    by_source[key] = { operation, demand, slots, }
  }
  // Imports retain the same bundle, including a valid empty bundle. Coordinates
  // locate it; exact checked objects establish ownership, never a matching CID.
  for index in 0..<count {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(PivotExecution(check))) &&
      check.rule is CaptureNumericObservations(demand) else {
      continue
    }
    guard @decode.tree_index(root, @pipeline.source(check.site.pipeline))
      is Some(coordinate) &&
      by_source.get((coordinate, check.site.step)) is Some(retained) &&
      demand.requirement_index == index &&
      physical_equal(demand.site, check.site) &&
      physical_equal(demand.step, check.step) &&
      physical_equal(demand.pivot, check.pivot) &&
      demand.input == check.input &&
      physical_equal(retained.demand.step, demand.step) &&
      physical_equal(retained.demand.pivot, demand.pivot) &&
      physical_equal(retained.demand.profile, demand.profile) else {
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
pub fn unit_pivot_numeric_slot_count(
  program : CheckedProgram,
  stage : Int,
) -> Int? {
  program.pivot_numeric_slots.units.get(stage).map(v => v.length())
}

///|
pub fn unit_pivot_numeric_slot_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> PivotNumericSlot? {
  program.pivot_numeric_slots.units.get(stage).bind(v => v.get(index))
}

///|
pub fn pivot_numeric_slots_for_requirement(
  program : CheckedProgram,
  index : Int,
) -> PivotNumericSlots? {
  program.pivot_numeric_slots.occurrences.get(index).bind(v => v)
}

///|
pub fn pivot_numeric_slots_operation(
  v : PivotNumericSlots,
) -> UnitOperationSource {
  v.operation
}

///|
pub fn pivot_numeric_slots_demand(
  v : PivotNumericSlots,
) -> @context.PivotNumericDemand {
  v.demand
}

///|
pub fn pivot_numeric_slot_count(v : PivotNumericSlots) -> Int {
  v.slots.length()
}

///|
pub fn pivot_numeric_slot_at(
  v : PivotNumericSlots,
  index : Int,
) -> PivotNumericSlot? {
  v.slots.get(index)
}
