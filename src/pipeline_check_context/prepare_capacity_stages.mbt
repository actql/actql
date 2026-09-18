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
  Inputs(CapacityInputsIssue)
  Values(Int, ValuesCapacityIssue)
  RowCapacity(RowCapacityIssue)
  ResolvedJoinLimits(Int, @host.ResolvedLimitIssue)
  MissingJoinCeiling(Int)
  StageCount
  VisitCount(Int)
  BudgetExceeded
  Bindings(Int, Int, @step_bounds.Issue)
  Guards(Int, Int, @pipeline.Issue)
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
  prepare_local_stage_contexts_owned(
    prepared,
    materials,
    selected_policy,
    limits,
    capacity_count_bindings(@stage_results.local_source_values(prepared)),
    proof_owners~,
    input_owners~,
  )
}

///|
fn prepare_local_stage_contexts_owned(
  prepared : @stage_results.PreparedLocalSource,
  materials : Array[Array[CapacityMaterial]],
  selected_policy : @policy.Policy,
  limits : CapacityStageLimits,
  count_bindings : CapacityCountBindings,
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
  let (base_work, base_text) = match
    capacity_preparation_base(prepared, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
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
  let inferred_owners : Array[Array[(Int, Int, Int)]] = []
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
    if visits > (limits.max_work - base_work - extra_work - coverage_work) / 3 {
      return Err(BudgetExceeded)
    }
    extra_work += visits * 3
    let entries : Array[@capacity.ApplicationCoverage?] = Array::make(
      visits,
      None,
    )
    let ends = Array::make(visits, visits)
    let registrations : Array[(Int, Int, Int)] = []
    // Contextual closure retains a preorder tree, including repeated imports.
    // Reverse traversal prepares every child occurrence before its consumer.
    for visit = visits - 1; visit >= 0; visit = visit - 1 {
      let pipeline = @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(orders, visit).unwrap(),
      )
      let inputs = @pipeline.input_count(pipeline)
      if inputs > limits.max_work - base_work - extra_work - coverage_work {
        return Err(BudgetExceeded)
      }
      extra_work += inputs
      let mut end = visit + 1
      for input in 0..<inputs {
        if @pipeline.input_producer(pipeline, input) is Some(_) {
          end = ends[end]
        }
      }
      ends[visit] = end
      let material = materials[stage][visit]
      let claims = @wire.program_claim_arithmetic(
        @host.source_claims(material.sources),
      )
      let claim_count = @wire.claim_count(claims)
      let producers : Array[@step_bounds.Applications] = []
      let producer_graphs : Array[@capacity.GraphInputs] = []
      let dependency_end = if claim_count == 0 { visit + 1 } else { end }
      if dependency_end - visit - 1 >
        limits.max_work - base_work - extra_work - coverage_work {
        return Err(BudgetExceeded)
      }
      extra_work += dependency_end - visit - 1
      for producer in (visit + 1)..<dependency_end {
        if extra_work == limits.max_work - base_work - coverage_work {
          return Err(BudgetExceeded)
        }
        extra_work += 1
        producer_graphs.push(
          @capacity.source_coverage_graph(
            @capacity.application_coverage_sources(entries[producer].unwrap()),
          ),
        )
        producers.push(
          @capacity.source_coverage_program(
            @capacity.application_coverage_sources(entries[producer].unwrap()),
          ),
        )
      }
      if claim_count > limits.max_work - base_work - extra_work - coverage_work {
        return Err(BudgetExceeded)
      }
      extra_work += claim_count
      let (bindings, binding_work, binding_text) = match
        capacity_count_binding(
          count_bindings,
          pipeline,
          limits.max_work - base_work - extra_work - coverage_work,
          limits.max_text_bytes - base_text - extra_text,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Bindings(stage, visit, issue))
      }
      extra_work += binding_work
      extra_text += binding_text
      if material.consumers.length() >
        limits.max_work - base_work - extra_work - coverage_work {
        return Err(BudgetExceeded)
      }
      extra_work += material.consumers.length()
      let mut needs_guards = false
      for request in material.consumers {
        if request is @capacity.Sequence(step~, ..) &&
          @pipeline.step_at(pipeline, step) is Some(checked) &&
          checked.operation is @pipeline.Sequence(operation) &&
          (
            @relation.sequence_per_key_guard(operation) is Some(_) ||
            @relation.sequence_output_guard(operation) is Some(_)
          ) {
          needs_guards = true
        }
        if request is @capacity.Traversal(step~, ..) &&
          @pipeline.step_at(pipeline, step) is Some(checked) &&
          checked.operation is @pipeline.Traverse(checked=operation, ..) &&
          @graph.traverse_output_guard(operation) is Some(_) {
          needs_guards = true
        }
        if request is @capacity.Traversal(step~, ..) &&
          @pipeline.step_at(pipeline, step) is Some(checked) &&
          checked.operation is @pipeline.Shortest(checked=operation, ..) &&
          @graph.shortest_output_guard(operation) is Some(_) {
          needs_guards = true
        }
        if request is @capacity.Components(step~, ..) &&
          @pipeline.step_at(pipeline, step) is Some(checked) &&
          checked.operation is @pipeline.Graph(operation) &&
          @graph.options(operation)
          is @graph.ComponentOptions(_, max_output_rows=Some(_)) {
          needs_guards = true
        }
        if request is @capacity.Join(step~, ..) &&
          @pipeline.step_at(pipeline, step) is Some(checked) {
          let authored = match checked.operation {
            @pipeline.Join(checked=operation, ..) =>
              @join.output_guard(operation) is Some(_)
            @pipeline.CrossJoin(checked=operation, ..) =>
              @join.cross_output_guard(operation) is Some(_)
            @pipeline.IntervalJoin(checked=operation, ..) =>
              @join.interval_output_guard(operation) is Some(_)
            _ => false
          }
          if authored {
            needs_guards = true
          }
        }
      }
      let guards = if needs_guards {
        let occurrences = match
          @pipeline.collect_author_guards(
            pipeline,
            max_work=limits.max_work - base_work - extra_work - coverage_work,
            max_text_bytes=limits.max_text_bytes - base_text - extra_text,
          ) {
          Ok(v) => v
          Err(e) => return Err(Guards(stage, visit, e))
        }
        let used = @pipeline.author_guards_usage(occurrences)
        extra_work += used.0
        extra_text += used.1
        let bound = match
          @pipeline.bind_author_guards(
            occurrences,
            bindings.map(v => @step_bounds.parameter_values(v)),
            max_work=limits.max_work - base_work - extra_work - coverage_work,
            max_text_bytes=limits.max_text_bytes - base_text - extra_text,
          ) {
          Ok(v) => v
          Err(e) => return Err(Guards(stage, visit, e))
        }
        let used = @pipeline.bound_guard_usage(bound)
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
          guards~,
          producers~,
          producer_graphs~,
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
      input_work += @step_bounds.application_input_work(program)
      operand_work += @step_bounds.application_operand_work(program)
      for index in 0..<claim_count {
        if @step_bounds.application_at(program, index) is Some(bound) {
          if !physical_equal(@step_bounds.checked_pipeline(bound), pipeline) {
            let cid = @wire.cid(
              @wire.program_proof_witness(@step_bounds.checked_proof(bound)),
            )
            for producer in (visit + 1)..<end {
              if extra_work == limits.max_work - base_work - coverage_work {
                return Err(BudgetExceeded)
              }
              extra_work += 1
              let table = producers[producer - visit - 1]
              let arithmetic = @wire.program_claim_arithmetic(
                @step_bounds.application_claims(table),
              )
              if @wire.claim_index(arithmetic, cid) is Some(claim) &&
                @step_bounds.application_at(table, claim) is Some(candidate) &&
                physical_equal(candidate, bound) &&
                physical_equal(
                  @step_bounds.checked_pipeline(bound),
                  @pipeline.contextual_orders_pipeline(
                    @pipeline.contextual_closure_at(orders, producer).unwrap(),
                  ),
                ) {
                registrations.push((visit, index, producer))
                break
              }
            }
          }
        }
      }
      entries[visit] = Some(coverage)
    }
    applications.push(entries.map(v => v.unwrap()))
    inferred_owners.push(registrations)
  }
  match
    check_prepared_local_stages(
      prepared,
      applications,
      selected_policy,
      max_work=limits.max_work - extra_work,
      max_text_bytes=limits.max_text_bytes - extra_text,
      proof_owners=Some(proof_owners.unwrap_or(inferred_owners)),
      input_owners~,
    ) {
    Ok(v) => Ok({ ..v, work: v.work + extra_work, text: v.text + extra_text, })
    Err(e) => Err(Stages(e))
  }
}

///|
// One definition of the already prepared prefix. Generation and expansion
// reserve it before doing new work; final integration includes it exactly once.
fn capacity_preparation_base(
  prepared : @stage_results.PreparedLocalSource,
  limits : CapacityStageLimits,
) -> Result[(Int, Int), CapacityStageIssue] {
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
  Ok(
    (base.work + result_work, base.direct_text_bytes + result_usage.text_bytes),
  )
}
