///|
/// Source-specific requirements on future data, not completed observations.
pub enum InputCompletenessBinding {
  Local(@context.LocalInputRequirement)
  Source(SourceExecution)
  Imported(BuiltResultInterface, @pipeline.ProducedInput)
}

///|
pub struct InputCompletenessRequirement {
  unit : UnitCompletenessRequirement
  binding : InputCompletenessBinding
}

///|
/// True only for an input fulfilled by the checked Program's supplied data.
/// Source acquisition and imported Result bindings remain distinct.
pub fn input_completeness_is_supplied(
  value : InputCompletenessRequirement,
) -> Bool {
  value.binding is Local(_)
}

///|
fn prepare_input_completeness(
  units : Array[BuiltUnit],
  budget : IdentityBudget,
) -> Array[Array[InputCompletenessRequirement]] raise UnitBuildFailure {
  identity_charge(budget, units.length())
  let bindings : Array[Array[InputCompletenessBinding?]] = []
  for unit in units {
    let count = @pipeline.input_count(unit.pipeline)
    identity_charge(budget, count)
    bindings.push(Array::make(count, None))
  }
  let put = fn(
    stage : Int,
    name : String,
    binding : InputCompletenessBinding,
  ) raise UnitBuildFailure {
    identity_charge(budget, name.length() + 1)
    guard units.get(stage) is Some(unit) &&
      @pipeline.lookup(unit.pipeline, name) is Some(@pipeline.Input(index)) else {
      raise ForeignOwner
    }
    if bindings[stage][index] is Some(_) {
      raise ForeignOwner
    }
    bindings[stage][index] = Some(binding)
  }
  if units.get(0) is Some(first) {
    let count = @context.local_input_closure_count(first.local_inputs)
    identity_charge(budget, count)
    for i in 0..<count {
      let check = @context.local_input_closure_at(first.local_inputs, i).unwrap()
      if check.kind == @context.RawBinding {
        let subject = check.subject
        guard units.get(subject.stage) is Some(unit) &&
          physical_equal(subject.pipeline, unit.pipeline) &&
          @pipeline.lookup(unit.pipeline, subject.name) == Some(subject.target) else {
          raise ForeignOwner
        }
        put(subject.stage, subject.name, Local(subject))
      }
    }
    identity_charge(budget, first.source_execution.length())
    for check in first.source_execution {
      if check.kind is CarrierResponse {
        guard units.get(check.subject.stage) is Some(unit) &&
          physical_equal(
            check.subject.owner,
            @context.core_contract_identity(unit.contract_inventory),
          ) else {
          raise ForeignOwner
        }
        put(
          check.subject.stage,
          @sourceviews.declaration(check.subject.source).input_name,
          Source(check),
        )
      }
    }
  }
  for stage, unit in units {
    identity_charge(budget, unit.interfaces.length())
    for interface in unit.interfaces {
      identity_charge(budget, interface.input_name.length())
      guard @pipeline.lookup(unit.pipeline, interface.input_name)
        is Some(@pipeline.Input(index)) &&
        @pipeline.input_producer(unit.pipeline, index) is Some(producer) else {
        raise UnresolvedProducer
      }
      let mut found = false
      for prior in 0..<stage {
        identity_charge(budget, 1)
        if physical_equal(
            units[prior].pipeline,
            @pipeline.producer_pipeline(producer),
          ) {
          if found ||
            units[prior].definition_cid !=
            interface.producer_unit_definition_cid {
            raise ForeignOwner
          }
          found = true
        }
      }
      if !found {
        raise UnresolvedProducer
      }
      put(stage, interface.input_name, Imported(interface, producer))
    }
  }
  let result = []
  for stage, unit in units {
    identity_charge(budget, bindings[stage].length())
    let entries = []
    for index, binding in bindings[stage] {
      guard binding is Some(binding) else { raise UnresolvedProducer }
      entries.push({
        unit: {
          unit_definition_cid: unit.definition_cid,
          requirement: @pipeline.completeness_requirement(
            unit.pipeline,
            Input(index),
          ).unwrap(),
        },
        binding,
      })
    }
    result.push(entries)
  }
  result
}

///|
/// Indexed by the checked pipeline's input position, not Catalog or request order.
pub fn unit_input_completeness(
  program : CheckedProgram,
  stage : Int,
  input : Int,
) -> InputCompletenessRequirement? {
  program.input_completeness.get(stage).bind(values => values.get(input))
}
