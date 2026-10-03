///|
/// A use of an admitted limit, not an index into a mixed-claim table. Step is
/// the authored ordinal in the named Stage; application is still checked later.
pub(all) enum CapacityUse {
  Sequence(step~ : Int, matches~ : @wire.LimitClaim, output~ : @wire.LimitClaim)
  Join(step~ : Int, output~ : @wire.LimitClaim)
  Traversal(step~ : Int, paths~ : @wire.LimitClaim, output~ : @wire.LimitClaim)
}

///|
/// Definition-level evidence. Repeated imports retain distinct applications
/// of this definition; these inputs do not assert completed observations.
pub(all) struct StageCapacityInput {
  stage : String
  sources : @host.HostSources
  uses : Array[CapacityUse]
}

///|
pub(all) enum CapacityInputsIssue {
  InvalidLimits
  ConflictingInputs
  BudgetExceeded
  UnknownStage(Int)
  DuplicateStage(Int)
  ForeignLimit(Int, Int)
  InvalidStep(Int, Int)
  ForeignProgram
  ForeignPipeline
} derive(Eq, Debug)

///|
struct ProgramCapacityInputs {
  program : @syntax.Program
  materials : Array[CapacityMaterial]
  work : Int
}

///|
priv struct CapacityInputBudget {
  mut capacity_remaining : Int
}

///|
priv suberror CapacityInputStop {
  CapacityInputStop(CapacityInputsIssue)
}

///|
fn capacity_input_spend(
  b : CapacityInputBudget,
  amount : Int,
) -> Unit raise CapacityInputStop {
  if amount > b.capacity_remaining {
    raise CapacityInputStop(BudgetExceeded)
  }
  b.capacity_remaining -= amount
}

///|
fn empty_capacity_input_sources() -> @host.HostSources {
  // Empty inventories have no user data and no hashes or wire admission.
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
}

///|
/// Bind authored Stage selectors to this exact admitted Program. Only input
/// ownership and limit membership are established here, not proof application,
/// completeness, policy acceptance or execution permission. Unspecified Stages
/// have no supplied external claims; ordinary checking must still close them.
pub fn bind_capacity_inputs(
  program : @syntax.Program,
  entries : Array[StageCapacityInput],
  max_work : Int,
) -> Result[ProgramCapacityInputs, CapacityInputsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let b = { capacity_remaining: max_work, }
  try {
    capacity_input_spend(b, 4)
    let count = @syntax.stage_count(program)
    // Reserve the Stage copy, retained slots, and caller entry visits.
    capacity_input_spend(b, count)
    capacity_input_spend(b, count)
    capacity_input_spend(b, entries.length())
    let stages = @syntax.stages(program)
    let names : Map[String, Int] = Map([])
    for index, stage in stages {
      capacity_input_spend(b, stage.id.length())
      capacity_input_spend(b, 1)
      names[stage.id] = index
    }
    let empty = CapacityMaterial::{
      sources: empty_capacity_input_sources(),
      consumers: [],
    }
    let materials = Array::make(count, empty)
    let assigned : Map[Int, Bool] = Map([])
    for entry_index, entry in entries {
      capacity_input_spend(b, entry.stage.length())
      capacity_input_spend(b, 1)
      guard names.get(entry.stage) is Some(stage) else {
        raise CapacityInputStop(UnknownStage(entry_index))
      }
      if assigned.contains(stage) {
        raise CapacityInputStop(DuplicateStage(entry_index))
      }
      assigned[stage] = true
      let mixed = @wire.program_claim_mixed(@host.source_claims(entry.sources))
      let limits : Map[String, (Int, @wire.LimitClaim)] = Map([])
      if mixed is Some(mixed) {
        capacity_input_spend(b, @wire.mixed_limit_count(mixed))
        for index in 0..<@wire.mixed_limit_count(mixed) {
          if @wire.mixed_limit_at(mixed, index) is Some(limit) {
            let cid = @wire.limit_cid(limit)
            capacity_input_spend(b, cid.length())
            limits[cid] = (index, limit)
          }
        }
      }
      capacity_input_spend(b, entry.uses.length())
      let consumers : Array[@capacity.ConsumerRequest] = []
      let body = @syntax.stage_body(stages[stage])
      let mut steps = None
      for field in 0..<@decode.object_length(body).unwrap() {
        capacity_input_spend(b, 1)
        let (name, value) = @decode.field_at(body, field).unwrap()
        capacity_input_spend(b, name.length())
        if name == "steps" {
          steps = @decode.array_length(value)
          break
        }
      }
      let steps = steps.unwrap()
      for use_index, usage in entry.uses {
        let ordinal = fn(
          limit : @wire.LimitClaim,
        ) -> Int raise CapacityInputStop {
          let cid = @wire.limit_cid(limit)
          capacity_input_spend(b, cid.length())
          capacity_input_spend(b, 1)
          guard limits.get(cid) is Some((index, owned)) &&
            physical_equal(limit, owned) else {
            raise CapacityInputStop(ForeignLimit(entry_index, use_index))
          }
          index
        }
        let (step, consumer) : (Int, @capacity.ConsumerRequest) = match usage {
          Sequence(step~, matches~, output~) =>
            (
              step,
              @capacity.Sequence(
                step~,
                matches=ordinal(matches),
                output=ordinal(output),
              ),
            )
          Join(step~, output~) =>
            (step, @capacity.Join(step~, output=ordinal(output)))
          Traversal(step~, paths~, output~) =>
            (
              step,
              @capacity.Traversal(
                step~,
                paths=ordinal(paths),
                output=ordinal(output),
              ),
            )
        }
        if step < 0 || step >= steps {
          raise CapacityInputStop(InvalidStep(entry_index, use_index))
        }
        consumers.push(consumer)
      }
      materials[stage] = { sources: entry.sources, consumers, }
    }
    Ok({ program, materials, work: max_work - b.capacity_remaining, })
  } catch {
    CapacityInputStop(issue) => Err(issue)
  }
}

///|
pub fn capacity_inputs_work(inputs : ProgramCapacityInputs) -> Int {
  inputs.work
}

///|
fn expand_capacity_inputs(
  prepared : @stage_results.PreparedLocalSource,
  inputs : ProgramCapacityInputs,
  max_work : Int,
) -> Result[(Array[Array[CapacityMaterial]], Int), CapacityInputsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let b = { capacity_remaining: max_work, }
  try {
    capacity_input_spend(b, 1)
    let source = @stage_results.local_source_source(prepared)
    if !physical_equal(@stages.program(source), inputs.program) {
      raise CapacityInputStop(ForeignProgram)
    }
    let count = @stages.stage_count(source)
    capacity_input_spend(b, count)
    let wiring = @stage_results.local_source_wiring(prepared)
    // Source offsets are lookup buckets only. Every use checks the exact
    // pipeline owner. No CID or source coordinate substitutes for ownership.
    let owners : Map[Int, Array[(@pipeline.CheckedPipeline, CapacityMaterial)]] = Map([],
    )
    for stage in 0..<count {
      let port = @stage_results.wiring_stage_at(wiring, stage).unwrap()
      let orders = @results.checked_producer_orders(
        @results.ports_orders(@stage_results.stage_port_publications(port)),
      )
      let pipeline = @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(orders, 0).unwrap(),
      )
      let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
      match owners.get(key) {
        Some(bucket) => bucket.push((pipeline, inputs.materials[stage]))
        None => owners[key] = [(pipeline, inputs.materials[stage])]
      }
    }
    capacity_input_spend(b, count)
    let materials : Array[Array[CapacityMaterial]] = []
    for stage in 0..<count {
      let port = @stage_results.wiring_stage_at(wiring, stage).unwrap()
      let orders = @results.checked_producer_orders(
        @results.ports_orders(@stage_results.stage_port_publications(port)),
      )
      let visits = @pipeline.contextual_closure_count(orders)
      capacity_input_spend(b, visits)
      let entries : Array[CapacityMaterial] = []
      for visit in 0..<visits {
        let pipeline = @pipeline.contextual_orders_pipeline(
          @pipeline.contextual_closure_at(orders, visit).unwrap(),
        )
        let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
        let mut matched = None
        if owners.get(key) is Some(bucket) {
          for (owner, material) in bucket {
            capacity_input_spend(b, 1)
            if physical_equal(pipeline, owner) {
              matched = Some(material)
              break
            }
          }
        }
        guard matched is Some(material) else {
          raise CapacityInputStop(ForeignPipeline)
        }
        entries.push(material)
      }
      materials.push(entries)
    }
    Ok((materials, max_work - b.capacity_remaining))
  } catch {
    CapacityInputStop(issue) => Err(issue)
  }
}

///|
/// Expand definition evidence across actual checked producer occurrences, then
/// apply the same capacity checks as source preparation. The binder's prior
/// work is not charged again; this call charges its own expansion work.
pub fn prepare_local_stage_contexts_from_inputs(
  prepared : @stage_results.PreparedLocalSource,
  inputs : ProgramCapacityInputs,
  selected_policy : @policy.Policy,
  limits : CapacityStageLimits,
  derived_capacity_limits? : @wire.Limits? = None,
  sourceviews? : @sourceviews.PipelineInputs? = None,
) -> Result[StageContexts, CapacityStageIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_name_bytes < 0 ||
    limits.max_input_work < 0 ||
    limits.max_operand_work < 0 {
    return Err(InvalidLimits)
  }
  let count_bindings = capacity_count_bindings(
    @stage_results.local_source_values(prepared),
  )
  if !physical_equal(
      @stages.program(@stage_results.local_source_source(prepared)),
      inputs.program,
    ) {
    return Err(Inputs(ForeignProgram))
  }
  let (base_work, base_text) = match
    capacity_preparation_base(prepared, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if sourceviews is Some(views) {
    let source = @source_inputs.source(
      @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
    )
    if !physical_equal(@stages.program(source), inputs.program) {
      return Err(Inputs(ForeignProgram))
    }
    guard @stage_results.wiring_local_environment(
        @stage_results.local_source_wiring(prepared),
      )
      is Some(local_environment) &&
      physical_equal(
        @sourceviews.pipeline_environment(views),
        @local_inputs.program_environment(local_environment),
      ) else {
      return Err(Inputs(ForeignPipeline))
    }
  }
  let generated = match derived_capacity_limits {
    Some(metadata) =>
      match
        derive_program_capacity(
          prepared,
          inputs,
          limits.max_work - base_work,
          metadata,
          limits.max_input_work,
          limits.max_operand_work,
          count_bindings,
          limits.max_text_bytes - base_text,
          sourceviews,
          selected_policy,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    None => None
  }
  let (inputs, generated_work, generated_bytes, generated_nodes, values_claims) = match
    generated {
    Some(value) =>
      (value.inputs, value.work, value.bytes, value.nodes, Some(value.claims))
    None => (inputs, 0, 0, 0, None)
  }
  let (generated_input_work, generated_operand_work) = match generated {
    Some(value) => (value.input_work, value.operand_work)
    None => (0, 0)
  }
  let generated_text = match generated {
    Some(value) => value.text
    None => 0
  }
  let (materials, work) = match
    expand_capacity_inputs(
      prepared,
      inputs,
      limits.max_work - base_work - generated_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Inputs(issue))
  }
  match
    prepare_local_stage_contexts_owned(
      prepared,
      materials,
      selected_policy,
      {
        ..limits,
        max_work: limits.max_work - work - generated_work,
        max_text_bytes: limits.max_text_bytes - generated_text,
        max_input_work: limits.max_input_work - generated_input_work,
        max_operand_work: limits.max_operand_work - generated_operand_work,
      },
      count_bindings,
    ) {
    Ok(value) =>
      Ok({
        ..value,
        work: value.work + work + generated_work,
        text: value.text + generated_text,
        generated_bytes,
        generated_nodes,
        values_claims,
      })
    Err(issue) => Err(issue)
  }
}
