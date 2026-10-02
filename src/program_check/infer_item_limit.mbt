///|
/// Owned item-capacity material for an existing checked Infer occurrence.
/// It does not admit model dependencies, egress, attempts or a runnable Plan.
pub struct InferItemLimit {
  owner : CheckedProgram
  unit : Int
  source : UnitOperationSource
  infer : @evidence.CheckedInfer
  limit : @wire.LimitClaim
  witnesses : Array[@wire.WireWitness]
  proofs : Array[ReidentifiedStep]
  guard_value : Int64?
}

///|
pub fn infer_item_limit_matches(
  value : InferItemLimit,
  owner : CheckedProgram,
  unit : Int,
  step : Int,
) -> Bool {
  physical_equal(value.owner, owner) &&
  value.unit == unit &&
  value.source.source_ordinal == step
}

///|
pub fn infer_item_limit_claim(value : InferItemLimit) -> @wire.LimitClaim {
  value.limit
}

///|
pub fn infer_item_limit_maximum(value : InferItemLimit) -> Int64 {
  @derivation.minimum_value(@wire.limit_minimum(value.limit))
}

///|
pub fn infer_item_limit_witness_count(value : InferItemLimit) -> Int {
  value.witnesses.length()
}

///|
pub fn infer_item_limit_witness_at(
  value : InferItemLimit,
  index : Int,
) -> @wire.WireWitness? {
  value.witnesses.get(index)
}

///|
pub fn infer_item_limit_proof_count(value : InferItemLimit) -> Int {
  value.proofs.length()
}

///|
pub fn infer_item_limit_proof_at(
  value : InferItemLimit,
  index : Int,
) -> ReidentifiedStep? {
  value.proofs.get(index)
}

///|
fn infer_bound_guard(
  infer : @evidence.CheckedInfer,
  values : @parameters.BoundValues?,
  budget : IdentityBudget,
) -> Int64? raise UnitBuildFailure {
  guard @evidence.infer_max_items_guard(infer) is Some(authored) else {
    return None
  }
  identity_charge(budget, 1)
  match @relation.count_value(authored) {
    Literal(value) => Some(value)
    Parameter(name) => {
      identity_charge(budget, name.length())
      guard values is Some(values) &&
        @relation.count_value_parameters(authored) is Some(declarations) &&
        physical_equal(@parameters.bound_declarations(values), declarations) else {
        raise ForeignOwner
      }
      for index in 0..<@parameters.bound_value_count(values) {
        identity_charge(budget, 1)
        let bound = @parameters.bound_value_at(values, index).unwrap()
        identity_charge(budget, bound.name.length())
        if bound.name == name {
          guard bound.value.value is @value.Number(number) &&
            number >= 1 &&
            number <= 9007199254740991.0 &&
            number.to_int64().to_double() == number else {
            raise ForeignOwner
          }
          return Some(number.to_int64())
        }
      }
      raise ForeignOwner
    }
  }
}

///|
fn infer_contract_item_witness(
  task : @environment.ModelTaskContract,
  budget : IdentityBudget,
) -> @wire.WireWitness? raise UnitBuildFailure {
  guard @environment.model_task_max_items(task) is Some(maximum) else {
    return None
  }
  let contract_cid = @environment.model_task_identity(task).2
  let emit = fn(
    writer : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(writer)
      @encode.key(writer, "dependencies")
      @encode.begin_array(writer)
      @encode.string_value(writer, contract_cid)
      @encode.end_array(writer)
      @encode.key(writer, "derivation")
      @encode.begin_object(writer)
      @encode.key(writer, "op")
      @encode.string_value(writer, "source")
      @encode.end_object(writer)
      @encode.key(writer, "law_id")
      @encode.string_value(writer, "actql.contract.model-task-items")
      @encode.key(writer, "role")
      @encode.string_value(writer, "contract_ceiling")
      @encode.key(writer, "source")
      @encode.begin_object(writer)
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, contract_cid)
      @encode.key(writer, "field")
      @encode.string_value(writer, "max_items")
      @encode.key(writer, "kind")
      @encode.string_value(writer, "contract")
      @encode.end_object(writer)
      @encode.key(writer, "unit")
      @encode.string_value(writer, "distinct_keys")
      @encode.key(writer, "value")
      @encode.number_value(writer, maximum.to_double())
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-bound-witness/0.1")
      if cid is Some(cid) {
        @encode.key(writer, "witness_cid")
        @encode.string_value(writer, cid)
      }
      @encode.end_object(writer)
    } catch {
      error => raise Encoding(error)
    }
  }
  let writer = identity_writer(budget)
  emit(writer, None)
  let cid = identity_finish(budget, writer)
  let bytes = publication_metadata(writer => emit(writer, Some(cid)), budget)
  identity_charge(budget, bytes.length())
  match
    @wire.admit(bytes, cid, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: budget.depth,
    }) {
    Ok(value) => Some(value)
    Err(issue) => raise PublicationWire(issue)
  }
}

///|
/// Derive the existing item-limit candidates from their actual checked owners.
/// Applicable row proofs bound distinct keys, but are not observations of the
/// input count; runtime key admission and the atomic pre-dispatch check remain.
pub fn prepare_infer_item_limit(
  program : CheckedProgram,
  unit : Int,
  index : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> InferItemLimit raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  identity_charge(budget, 1)
  guard program.units.get(unit) is Some(selected) &&
    unit_operation_source(selected, selected.pipeline, index) is Some(source) &&
    @pipeline.step_at(selected.pipeline, index) is Some(step) &&
    step.operation is @pipeline.CheckedOperation::Infer(infer) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @pipeline.input_occurrence_at(step, 0) is Some(input) else {
    raise ForeignOwner
  }
  let stages = @context.wired_stage_contexts(
    @context.reconciled_wiring(
      @context.policy_context(checked_selected_policy(program)),
    ),
  )
  guard @context.stage_context_at(stages, unit) is Some(context) else {
    raise ForeignOwner
  }
  let capacity = @context.checked_capacity(@context.parameter_context(context))
  let policy = @capacity.application_closure_policy(capacity)
  guard @policy.ceiling(policy, "max_infer_items") is Some(ceiling) else {
    raise ForeignOwner
  }
  let orders = @capacity.application_closure_orders(capacity)
  let mut consumer_visit = -1
  for visit in 0..<@pipeline.contextual_closure_count(orders) {
    identity_charge(budget, 1)
    if physical_equal(
        @pipeline.contextual_orders_pipeline(
          @pipeline.contextual_closure_at(orders, visit).unwrap(),
        ),
        selected.pipeline,
      ) {
      if consumer_visit >= 0 {
        raise ForeignOwner
      }
      consumer_visit = visit
    }
  }
  guard consumer_visit >= 0 &&
    @pipeline.bound_guard_closure_at(
      @capacity.application_closure_guards(capacity),
      consumer_visit,
    )
    is Some(guards) else {
    raise ForeignOwner
  }
  let guard_value = infer_bound_guard(
    infer,
    @pipeline.bound_guard_bindings(guards),
    budget,
  )
  let host = publication_host(ceiling, budget)
  let bytes = publication_metadata(
    writer => @host.emit(host, writer) catch { error => raise Encoding(error) },
    budget,
  )
  identity_charge(budget, bytes.length())
  let host_witness = match
    @wire.admit(bytes, @host.cid(host), {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) => raise PublicationWire(issue)
  }
  let candidates : Array[(String, @wire.WireWitness)] = [
    (@wire.cid(host_witness), host_witness),
  ]
  let mut maximum = @wire.value(host_witness)
  if infer_contract_item_witness(@evidence.infer_model_task(infer), budget)
    is Some(witness) {
    candidates.push((@wire.cid(witness), witness))
    maximum = Int64::min(maximum, @wire.value(witness))
  }
  let subject = unit_operation_subject(source, budget)
  let proofs : Array[ReidentifiedStep] = []
  let conversion = Some(proof_conversion(program.units, budget))
  for visit in 0..<@pipeline.contextual_closure_count(orders) {
    identity_charge(budget, 1)
    let applications = @capacity.source_coverage_program(
      @capacity.application_coverage_sources(
        @capacity.application_closure_at(capacity, visit).unwrap(),
      ),
    )
    let claims = @wire.program_claim_arithmetic(
      @step_bounds.application_claims(applications),
    )
    for claim in 0..<@wire.claim_count(claims) {
      identity_charge(budget, 1)
      guard @step_bounds.application_at(applications, claim) is Some(bound) else {
        continue
      }
      let (rows, used) = @step_bounds.check_target_rows_usage(
        selected.pipeline,
        input.target,
        bound,
        budget.work,
      )
      identity_charge(budget, used)
      match rows {
        Ok(rows) => {
          match
            @capacity.bind_producer_target_membership(
              capacity, rows, consumer_visit, visit, claim,
            ) {
            Ok(_) => ()
            Err(_) => raise ForeignOwner
          }
          let proof = reidentify_step_graph(
            program.units,
            bound,
            budget,
            conversion~,
          )
          let input_witness = @wire.program_proof_witness(proof.proof)
          let key_proof = emit_source_bound_claim(
            Some(@wire.cid(input_witness)),
            subject,
            "actql.bound.infer-distinct-keys",
            "distinct_keys",
            @wire.value(input_witness),
            None,
            budget,
          )
          let witness = @wire.program_proof_witness(key_proof)
          proofs.push(proof)
          candidates.push((@wire.cid(witness), witness))
          maximum = Int64::min(maximum, @wire.value(witness))
        }
        Err(WrongUnit | UnrelatedBound | MissingProducer) => ()
        Err(WorkLimit) => raise BudgetExceeded
        Err(_) => raise ForeignOwner
      }
    }
  }
  if guard_value is Some(value) {
    let witness = emit_unit_guard_witness(
      source.unit_definition_cid,
      "$.steps[" + index.to_string() + "].infer.max_items",
      "actql.guard.infer-items",
      "distinct_keys",
      value,
      budget,
    )
    candidates.push((@wire.cid(witness), witness))
  }
  let limit = assemble_aggregate_limit_claim(
    subject,
    candidates,
    proofs,
    guard_value,
    Some(maximum),
    guard_value.map(value => Int64::min(maximum, value)).unwrap_or(maximum),
    "distinct_keys",
    budget,
  )
  let witnesses = []
  let claims = @wire.limit_claims(limit)
  identity_charge(budget, @wire.claim_count(claims))
  for claim in 0..<@wire.claim_count(claims) {
    witnesses.push(@wire.claim_at(claims, claim).unwrap())
  }
  {
    owner: program,
    unit,
    source,
    infer,
    limit,
    witnesses,
    proofs,
    guard_value,
  }
}
