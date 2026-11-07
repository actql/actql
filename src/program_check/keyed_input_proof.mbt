///|
struct KeyedInputProof {
  execution : SourceExecution
  source : UnitOperationSource
  proof : ReidentifiedStep?
  acquired : ReidentifiedSourceInput?
}

///|
// Acquisition input bounds keep their original producer Unit, which can differ
// from the join's Unit. This does not attest to completed provider execution.
fn prepare_keyed_input_proofs(
  units : Array[BuiltUnit],
  checks : Array[SourceExecution],
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> Array[KeyedInputProof] raise UnitBuildFailure {
  let out = []
  // Coordinates are local to the already audited Stage closure. Repeated
  // acquisitions retain separate entries but share the exact converted proof.
  let converted : Map[(Int, Int, Int), ReidentifiedStep] = Map([])
  let acquired : Map[(Int, Int, Int), ReidentifiedSourceInput] = Map([])
  let session = match conversion {
    Some(session) => session
    None => proof_conversion(units, budget)
  }
  for execution in checks {
    identity_charge(budget, 1)
    guard execution.kind is KeyedRequest(binding) else { continue }
    guard units.get(binding.stage) is Some(unit) &&
      physical_equal(
        execution.subject.owner,
        @context.core_contract_identity(unit.contract_inventory),
      ) &&
      @context.program_identity_stage_at(execution.subject.owner, binding.stage)
      is Some(stage) &&
      physical_equal(stage, unit.source) else {
      raise ForeignOwner
    }
    let step = @sourceviews.keyed_join_step(binding.join)
    guard unit_operation_source(unit, unit.pipeline, step) is Some(source) &&
      @pipeline.step_at(unit.pipeline, step).unwrap().operation
      is @pipeline.Join(checked~, ..) &&
      physical_equal(checked, @sourceviews.keyed_join_operation(binding.join)) else {
      raise ForeignOwner
    }
    guard binding.producer is Some(membership) else {
      guard keyed_execution_producer_matches(
        binding.bounds,
        binding.index,
        binding.join,
        None,
      ) else {
        raise ForeignOwner
      }
      // The exact Unit operation and checked join are the runtime obligation.
      // No capacity signature or reidentified estimate is fabricated.
      out.push({ execution, source, proof: None, acquired: None, })
      continue
    }
    let rows = @capacity.target_membership_rows(membership)
    guard physical_equal(@step_bounds.target_rows_pipeline(rows), unit.pipeline) &&
      @step_bounds.target_rows_target(rows) ==
      @sourceviews.keyed_join_left(binding.join) else {
      raise ForeignOwner
    }
    if @step_bounds.target_rows_source(rows) is Some(original) {
      guard @capacity.target_membership_input_coordinates(membership)
        is Some((visit, input)) &&
        input == @step_bounds.source_input_rows_index(original) &&
        @capacity.target_membership_coordinates(membership) is None else {
        raise ForeignOwner
      }
      let key = (binding.stage, visit, input)
      identity_charge(budget, 1)
      let retained = match acquired.get(key) {
        Some(retained) => {
          guard physical_equal(retained.original, original) else {
            raise ForeignOwner
          }
          retained
        }
        None => {
          let producer = proof_conversion_owner(
            session,
            @step_bounds.source_input_rows_pipeline(original),
            budget,
          )
          let retained = reidentify_source_input(producer, original, budget)
          acquired[key] = retained
          retained
        }
      }
      out.push({ execution, source, proof: None, acquired: Some(retained), })
      continue
    }
    guard @capacity.target_membership_coordinates(membership)
      is Some((visit, claim, _)) else {
      raise UnconvertedProofInput
    }
    let key = (binding.stage, visit, claim)
    let original = require_step_target_rows(rows)
    identity_charge(budget, 1)
    let proof = match converted.get(key) {
      Some(proof) => {
        guard physical_equal(proof.original, original) else {
          raise ForeignOwner
        }
        proof
      }
      None => {
        let proof = reidentify_step_graph(
          units,
          original,
          budget,
          conversion=Some(session),
        )
        converted[key] = proof
        proof
      }
    }
    out.push({ execution, source, proof: Some(proof), acquired: None, })
  }
  out
}

///|
pub fn keyed_input_proof_count(program : CheckedProgram) -> Int {
  program.keyed_input_proofs.length()
}

///|
pub fn keyed_input_proof_at(
  program : CheckedProgram,
  index : Int,
) -> KeyedInputProof? {
  program.keyed_input_proofs.get(index)
}

///|
pub fn keyed_input_proof_execution(value : KeyedInputProof) -> SourceExecution {
  value.execution
}

///|
pub fn keyed_input_proof_source(value : KeyedInputProof) -> UnitOperationSource {
  value.source
}

///|
pub fn keyed_input_proof_bound(value : KeyedInputProof) -> ReidentifiedStep? {
  value.proof
}

///|
pub fn keyed_input_proof_acquired(
  value : KeyedInputProof,
) -> ReidentifiedSourceInput? {
  value.acquired
}

///|
/// The branch without a static estimate retains the exact original execution
/// and left target. Known estimates also require runtime resource admission;
/// this accessor identifies only the branch without a signed count proof.
pub fn keyed_input_runtime_admission(
  value : KeyedInputProof,
) -> KeyedExecution? {
  match value.execution.kind {
    KeyedRequest(binding) if binding.producer is None => Some(binding)
    _ => None
  }
}

///|
pub fn keyed_execution_requirement(
  value : KeyedExecution,
) -> @sourceviews.LookupRequirement {
  value.requirement
}
