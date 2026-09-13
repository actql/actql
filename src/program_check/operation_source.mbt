///|
// Verify the mapping before exposing any source ordinal. Imported prerequisite
// visits do not become authored operations of this Unit.
fn unit_source_pipeline(
  identity : @context.ProgramSourceIdentity,
  stage : Int,
  budget : IdentityBudget,
) -> @pipeline.CheckedPipeline raise UnitBuildFailure {
  guard @context.program_identity_producer_count(identity, stage) is Some(count) else {
    raise ForeignOwner
  }
  identity_charge(budget, count)
  let mut selected : @pipeline.CheckedPipeline? = None
  for visit in 0..<count {
    if @context.program_identity_producer_is_local(identity, stage, visit) !=
      Some(true) {
      continue
    }
    let pipeline = @context.program_identity_producer_at(identity, stage, visit).unwrap()
    match selected {
      None => selected = Some(pipeline)
      Some(previous) =>
        if !physical_equal(previous, pipeline) {
          raise ForeignOwner
        }
    }
  }
  guard selected is Some(pipeline) else { raise ForeignOwner }
  let source = @pipeline.source(pipeline)
  let steps = @pipeline.step_count(pipeline)
  if @decode.array_length(source) != Some(steps) {
    raise ForeignOwner
  }
  identity_charge(budget, steps)
  for index in 0..<steps {
    let checked = @pipeline.step_at(pipeline, index).unwrap()
    let authored = @decode.element_at(source, index).unwrap()
    guard @decode.tree_index(authored, checked.source) is Some(actual) &&
      @decode.tree_index(authored, authored) == Some(actual) else {
      raise ForeignOwner
    }
  }
  pipeline
}

///|
// A source location with its semantic owner, not a new wire proof or a hash of
// an internal index. Persistent proof emission must use its normative preimage.
pub struct UnitOperationSource {
  unit_definition_cid : String
  stage : @context.StageSourceIdentity
  pipeline : @pipeline.CheckedPipeline
  source_ordinal : Int
  source : @decode.Cursor
}

///|
fn unit_operation_source(
  unit : BuiltUnit,
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
) -> UnitOperationSource? {
  if !physical_equal(unit.pipeline, pipeline) {
    return None
  }
  @pipeline.step_at(pipeline, index).map(step => {
    unit_definition_cid: unit.definition_cid,
    stage: unit.source,
    pipeline,
    source_ordinal: index,
    source: step.source,
  })
}

///|
fn unit_operation_subject(
  source : UnitOperationSource,
  budget : IdentityBudget,
) -> String raise UnitBuildFailure {
  identity_charge(budget, source.unit_definition_cid.length())
  identity_charge(budget, 32)
  "unit:" +
  source.unit_definition_cid +
  "#/steps/" +
  source.source_ordinal.to_string()
}
