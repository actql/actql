///|
/// Admitted source material and unchecked consumer coordinates for one visit.
/// The owning pipeline and Parameter bindings are selected by preparation.
pub(all) struct CapacityMaterial {
  sources : @host.HostSources
  consumers : Array[@capacity.ConsumerRequest]
}

///|
pub(all) struct CapacityStageLimits {
  max_work : Int
  max_text_bytes : Int
  max_name_bytes : Int
  max_input_work : Int
  max_operand_work : Int
} derive(Eq, Debug)

///|
pub enum CapacityStageIssue {
  InvalidLimits
  StageCount
  VisitCount(Int)
  BudgetExceeded
  Bindings(Int, Int, @step_bounds.Issue)
  Capacity(Int, Int, @capacity.PreparationIssue)
  Stages(PreparedStagesIssue)
}

///|
/// Prepare capacity and integrate all Local Stage contexts from source-owned
/// publication orders. No caller-assembled coverage or substitute bindings are
/// accepted. Prior wire/Host admission and complete Program closure are separate.
pub fn prepare_local_stage_contexts(
  prepared : @stage_results.PreparedLocalSource,
  materials : Array[Array[CapacityMaterial]],
  selected_policy : @policy.Policy,
  limits : CapacityStageLimits,
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
) -> Result[StageContexts, CapacityStageIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_name_bytes < 0 ||
    limits.max_input_work < 0 ||
    limits.max_operand_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @stages.stage_count(@stage_results.local_source_source(prepared))
  if materials.length() != count ||
    (proof_owners is Some(v) && v.length() != count) ||
    (input_owners is Some(v) && v.length() != count) {
    return Err(StageCount)
  }
  let operations = @stage_results.local_source_operations(prepared)
  let base = @stages.bindings_usage(operations)
  let result_usage = @stage_results.usage(
    @stage_results.local_source_results(prepared),
  )
  let result_work = result_usage.work -
    @stages.operations_usage(@stages.bound_operations(operations)).work
  if base.work > limits.max_work ||
    result_work > limits.max_work - base.work ||
    base.direct_text_bytes > limits.max_text_bytes ||
    result_usage.text_bytes > limits.max_text_bytes - base.direct_text_bytes {
    return Err(BudgetExceeded)
  }
  let base_work = base.work + result_work
  let base_text = base.direct_text_bytes + result_usage.text_bytes
  if count > limits.max_work - base_work {
    return Err(BudgetExceeded)
  }
  // Coverage cost is already retained by check_prepared_local_stages. Only
  // gathering, binding preparation and usage reads are added outside that path.
  let mut extra_work = count
  let mut extra_text = 0
  let mut coverage_work = 0
  let mut names = 0
  let mut input_work = 0
  let mut operand_work = 0
  let applications : Array[Array[@capacity.ApplicationCoverage]] = []
  for stage in 0..<count {
    let port = @stage_results.wiring_stage_at(
      @stage_results.local_source_wiring(prepared),
      stage,
    ).unwrap()
    let orders = @results.checked_producer_orders(
      @results.ports_orders(@stage_results.stage_port_publications(port)),
    )
    let visits = @pipeline.contextual_closure_count(orders)
    if materials[stage].length() != visits {
      return Err(VisitCount(stage))
    }
    if visits > limits.max_work - base_work - extra_work - coverage_work {
      return Err(BudgetExceeded)
    }
    extra_work += visits
    let entries : Array[@capacity.ApplicationCoverage] = []
    for visit in 0..<visits {
      let pipeline = @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(orders, visit).unwrap(),
      )
      let material = materials[stage][visit]
      let claims = @wire.program_claim_arithmetic(
        @host.source_claims(material.sources),
      )
      let claim_count = @wire.claim_count(claims)
      if claim_count > limits.max_work - base_work - extra_work - coverage_work {
        return Err(BudgetExceeded)
      }
      extra_work += claim_count
      let bindings = if @pipeline.parameters(pipeline) is Some(_) {
        let bound = match
          @step_bounds.bind_parameters(
            pipeline,
            @stage_results.local_source_values(prepared),
            max_work=limits.max_work - base_work - extra_work - coverage_work,
            max_text_bytes=limits.max_text_bytes - base_text - extra_text,
          ) {
          Ok(v) => v
          Err(e) => return Err(Bindings(stage, visit, e))
        }
        let used = @step_bounds.binding_usage(bound)
        extra_work += used.0
        extra_text += used.1
        Some(bound)
      } else {
        None
      }
      let name_cap = Int::min(
        limits.max_name_bytes - names,
        limits.max_text_bytes - base_text - extra_text,
      )
      let coverage = match
        @capacity.prepare_application_coverage(
          pipeline,
          material.sources,
          selected_policy,
          material.consumers,
          {
            max_work: limits.max_work - base_work - extra_work - coverage_work,
            max_name_bytes: name_cap,
            max_input_work: limits.max_input_work - input_work,
            max_operand_work: limits.max_operand_work - operand_work,
          },
          bindings~,
        ) {
        Ok(v) => v
        Err(e) => return Err(Capacity(stage, visit, e))
      }
      coverage_work += @capacity.application_coverage_work(coverage)
      let sources = @capacity.application_coverage_sources(coverage)
      let graph = @capacity.source_coverage_graph(sources)
      let name_bytes = @capacity.usage(graph).1
      names += name_bytes
      extra_text += name_bytes
      let program = @capacity.source_coverage_program(sources)
      for index in 0..<claim_count {
        if @step_bounds.application_at(program, index) is Some(bound) {
          input_work += @step_bounds.input_work(bound)
          operand_work += @step_bounds.operand_work(bound)
        }
      }
      entries.push(coverage)
    }
    applications.push(entries)
  }
  match
    check_prepared_local_stages(
      prepared,
      applications,
      selected_policy,
      max_work=limits.max_work - extra_work,
      max_text_bytes=limits.max_text_bytes - extra_text,
      proof_owners~,
      input_owners~,
    ) {
    Ok(v) => Ok({ ..v, work: v.work + extra_work, text: v.text + extra_text, })
    Err(e) => Err(Stages(e))
  }
}
