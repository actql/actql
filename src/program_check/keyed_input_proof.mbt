///|
struct KeyedInputProof {
  execution : SourceExecution
  source : UnitOperationSource
  proof : ReidentifiedStep
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
    let rows = @capacity.target_membership_rows(binding.producer)
    guard physical_equal(@step_bounds.target_rows_pipeline(rows), unit.pipeline) &&
      @step_bounds.target_rows_target(rows) ==
      @sourceviews.keyed_join_left(binding.join) else {
      raise ForeignOwner
    }
    let (visit, claim, _) = @capacity.target_membership_coordinates(
      binding.producer,
    )
    let key = (binding.stage, visit, claim)
    let original = @step_bounds.target_rows_bound(rows)
    identity_charge(budget, 1)
    let proof = match converted.get(key) {
      Some(proof) => {
        guard physical_equal(proof.original, original) else {
          raise ForeignOwner
        }
        proof
      }
      None => {
        let proof = reidentify_step_graph(units, original, budget, conversion~)
        converted[key] = proof
        proof
      }
    }
    out.push({ execution, source, proof, })
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
pub fn keyed_input_proof_bound(value : KeyedInputProof) -> ReidentifiedStep {
  value.proof
}
