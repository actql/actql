///|
// Use the original checked Program and each original lowered Stage owner.
// Normal's fused task geometry says nothing about the Debug split. This
// short-lived probe uses the same remapper and entry guard as real admission.
fn[I] static_debug_entry_probe(
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  max_tasks : Int,
  work : Int,
  original_split? : Bool = false,
) -> Result[(Bool, Int), @resources.PreparationCapacityIssue] {
  let graph = @publication_host.prepared_client_graph(prepared)
  let checked = @strategy.graph_program(graph)
  with_static_debug_graph_probe(
    capacity,
    input,
    @checked.unit_count(checked),
    max_tasks,
    work,
    observed => {
      @publication_host.measure_client_debug_graph_construction(
        checked, max_tasks, work, observed,
      )
    },
    (remaining, boundary_work) => {
      if original_split {
        prove_static_debug_original_operations(graph, boundary_work)
      } else {
        probe_static_debug_graph(
          graph,
          checked,
          @checked.unit_count(checked),
          max_tasks,
          remaining,
          boundary_work,
        )
      }
    },
  )
}

///|
fn[I, P] with_static_debug_graph_probe(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  stages : Int,
  max_tasks : Int,
  work : Int,
  measure : (Ref[Int64]) -> Result[
    (Int64, Int),
    @publication_host.ClientProgramPreparationIssue,
  ],
  probe : (Int, Int64) -> Bool,
) -> Result[(Bool, Int), @resources.PreparationCapacityIssue] {
  if work < 8 || max_tasks < 1 {
    return Ok((false, 0))
  }
  let base = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let controls = @publication_host.client_debug_graph_quotation_control_bytes()
  guard @execution.checked_preparation_add_product(base.0, controls, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(base.1, controls, 1L) is Some(e) else {
    return Ok((false, 0))
  }
  if @resources.reserve_working_preparation_phase(capacity, input, r, e)
    is Err(_) {
    return Ok((false, 0))
  }
  let eligible = {
    let observed = Ref(0L)
    match measure(observed) {
      Err(_) => false
      Ok((bytes, remaining)) => {
        // One forward owner lookup and the final entry check have separate
        // finite work. The remapper gets only the remaining allowance.
        // Measurement already proves the expanded task count fits
        // the node ceiling. Compute a conservative split from the actual
        // observed work (which includes at least one visit per step).
        let boundary_work = 7L * observed.val + stages.to_int64()
        // The borrowed pointer vector coexists with both remapped Graphs.
        // Its Array backing and the fixed entry-observation frames are
        // additional to the compiler's graph construction quote.
        let frame = @execution.preparation_representation_cost({
          record_headers: 12L,
          reference_slots: 16L + 2L * stages.to_int64(),
          scalar_words: 16L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        }).unwrap()
        if boundary_work >= remaining.to_int64() {
          false
        } else if @execution.checked_preparation_add_product(bytes, frame, 1L)
          is Some(scratch) &&
          @execution.checked_preparation_add_product(r, scratch, 1L)
          is Some(peak_r) &&
          @execution.checked_preparation_add_product(e, scratch, 1L)
          is Some(peak_e) &&
          @resources.reserve_working_preparation_phase(
            capacity, input, peak_r, peak_e,
          )
          is Ok(_) {
          probe(
            remaining - boundary_work.to_int(),
            boundary_work - stages.to_int64(),
          )
        } else {
          false
        }
      }
    }
  }
  // All Graph containers and the owner vector have gone out of scope. Keep
  // original compiler/Plan backing and the bounded work spent on this read.
  match
    @resources.reconcile_current_working_preparation_phase(
      capacity,
      input,
      base.0,
      base.1,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => Ok((eligible, work))
  }
}

///|
// The explicit Debug Plan already owns the split graph. Check every original
// forward occurrence once, in the same funded observation as entry eligibility.
fn prove_static_debug_original_operations(
  graph : @strategy.CheckedDAG,
  work : Int64,
) -> Bool {
  let checked = @strategy.graph_program(graph)
  let stages = @checked.unit_count(checked)
  let tasks = @strategy.graph_task_count(graph)
  let extent = 1L +
    stages.to_int64() +
    7L * tasks.to_int64() +
    @strategy.graph_data_count(graph).to_int64() +
    @strategy.graph_control_count(graph).to_int64()
  guard tasks > 0 &&
    @strategy.graph_captured_prefix(graph) == 0 &&
    extent <= work &&
    @strategy.graph_source_free_inputs_complete(graph) else {
    return false
  }
  let mut expected = 0
  for stage in 0..<stages {
    guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
      return false
    }
    let count = @pipeline.step_count(pipeline)
    guard count > 0 && count <= tasks - expected else { return false }
    for step in 0..<count {
      if @strategy.checked_task_control_operation_task(graph, stage, step) !=
        Some(expected) {
        return false
      }
      expected += 1
    }
  }
  expected == tasks
}

///|
fn probe_static_debug_graph(
  graph : @strategy.CheckedDAG,
  checked : @checked.CheckedProgram,
  stages : Int,
  max_tasks : Int,
  work : Int,
  boundary_work : Int64,
) -> Bool {
  let owners = []
  for stage in 0..<stages {
    guard @strategy.graph_stage_operation_task(graph, stage, 0) is Some(task) &&
      @strategy.graph_task_owner(graph, task) is Some(owner) else {
      return false
    }
    owners.push(owner)
  }
  match
    @strategy.prepare_checked_debug_dag(
      checked,
      owners,
      max_tasks,
      work,
      source_free_root=true,
    ) {
    Err(_) => false
    Ok(debug) => {
      let extent = 1L +
        6L * @strategy.graph_task_count(debug).to_int64() +
        @strategy.graph_data_count(debug).to_int64() +
        @strategy.graph_control_count(debug).to_int64()
      extent <= boundary_work &&
      @strategy.graph_source_free_inputs_complete(debug) &&
      @strategy.checked_task_control_entry_boundary_issue(debug) is None
    }
  }
}

///|
fn[I, T] with_request_static_pure_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  limits : (Int, Int, Int),
  max_work : Int,
  project : (
    @resources.PreparationCapacity[I, @publication_host.PreparedClientProgram],
    @publication_host.PreparedClientProgram,
    () -> Bool,
    (Int, Int, Int),
  ) -> Result[T, ClientRequestStaticContextIssue],
) -> Result[T, ClientRequestStaticContextIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  let phase = owner.phase
  guard (
      phase == ProgramCompiled ||
      phase == ProgramPlanReserved ||
      phase == ModelPlanReserved
    ) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_capacity is Some(capacity) &&
    !owner.program_body_attempted else {
    return Err(Preparation(WrongPhase))
  }
  let (bytes, nodes, depth) = limits
  if bytes < 1 || nodes < 1 || depth < 1 || max_work < 1 {
    return Err(Preparation(Policy))
  }
  owner.phase = Selecting
  let original_current = () => {
    owner.phase == Selecting &&
    owner.input is Some(held) &&
    physical_equal(held, input) &&
    owner.program_capacity is Some(working) &&
    physical_equal(working, capacity) &&
    owner.compiled_program is Some(checked) &&
    physical_equal(checked, prepared)
  }
  preparation_module_call(
    () => {
      let result = project(
        capacity,
        prepared,
        original_current,
        (Int::min(bytes, 65536), Int::min(nodes, 8192), Int::min(depth, 64)),
      )
      guard result is Ok(value) else { return result }
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => Err(Preparation(Capacity(issue)))
        Ok(_) =>
          if original_current() {
            Ok(value)
          } else {
            Err(Preparation(ForeignOriginal))
          }
      }
    },
    () => if owner.phase == Selecting { owner.phase = phase },
  )
}

///|
fn[I] prepare_static_pure_explanation_facets(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  limits : (Int, Int, Int),
  max_work : Int,
  infers : Array[@publication_host.ClientInferPlanGraph],
  reserve_js_delivery : Bool,
  debug_entry_installed? : Bool = false,
) -> Result[
  ClientRequestStaticEffectExplanation,
  ClientRequestStaticContextIssue,
] {
  guard owner.program_data is Some(data) else {
    return Err(Preparation(WrongPhase))
  }
  // A static visitor can select only the exact graphs already admitted
  // under this Request, in their original order.
  let supplied_models = infers.length()
  if supplied_models > max_work {
    return Err(Context(WorkLimit))
  }
  match owner.program_domain_compilation_inputs {
    Some(RequestModelGraph(_, _, _, graph)) =>
      if supplied_models != 1 || !physical_equal(graph, infers[0]) {
        return Err(Preparation(ForeignOriginal))
      }
    Some(RequestModelGraphs(_, _, _, graphs)) => {
      if graphs.length() != supplied_models {
        return Err(Preparation(ForeignOriginal))
      }
      for index, graph in graphs {
        if !physical_equal(graph, infers[index]) {
          return Err(Preparation(ForeignOriginal))
        }
      }
    }
    _ =>
      if supplied_models != 0 || owner.phase == ModelPlanReserved {
        return Err(Preparation(ForeignOriginal))
      }
  }
  with_request_static_pure_explanation(owner, input, limits, max_work, (
    capacity,
    prepared,
    current,
    bounded,
  ) => {
    let (bytes, nodes, depth) = bounded
    let graph = @publication_host.prepared_client_graph(prepared)
    match
      reserve_native_static_plan_capacity(
        capacity, input, data, graph, bytes, nodes, depth,
      ) {
      Err(issue) => return Err(Preparation(issue))
      Ok(_) => ()
    }
    // Plan emission has its own writer reservation. Account for its
    // coexisting typed validation, Map and opaque projection record.
    guard explanation_read_codec_cost("plan_view", bytes, nodes, depth)
      is Some(codec) &&
      @encode.measuring_writer_construction_extent(15, 3) is Some(measure) &&
      @execution.preparation_representation_cost(
        static_plan_quote_units(
          measure.record_headers + 16L,
          measure.reference_slots + 38L,
          measure.scalar_words + 24L,
        ),
      )
      is Some(held) &&
      @execution.checked_preparation_add_product(codec, held, 1L)
      is Some(overlap) &&
      @execution.checked_preparation_add_product(
        overlap,
        client_static_plan_quote_construction_bytes(),
        1L,
      )
      is Some(entry) else {
      return Err(Preparation(Policy))
    }
    match reserve_static_context_construction(capacity, input, entry) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard current() else { return Err(Preparation(ForeignOriginal)) }
    let compiled = if owner.program_compilation is Some(original) {
      original
    } else {
      let sequence = @publication_host.prepared_client_values_sequence_limits(
        prepared,
      )
      let issued = match infers.length() {
        0 =>
          @publication_host.issue_prepared_client_task_compilation(
            prepared, manifests, sequence, 1000, 1000, bytes, nodes, depth,
          )
        1 =>
          @publication_host.issue_prepared_client_infer_compilation(
            prepared,
            infers[0],
            manifests,
            1000,
            1000,
            bytes,
            nodes,
            depth,
          )
        _ =>
          @publication_host.issue_prepared_client_multi_infer_compilation(
            prepared, infers, manifests, sequence, 1000, 1000, bytes, nodes, depth,
          )
      }
      match issued {
        Err(_) => return Err(Preparation(Policy))
        Ok(value) => @publication_host.Tasks(value)
      }
    }
    let (debug_entry, probe_work) = if debug_entry_installed &&
      infers.is_empty() &&
      max_work > 1 {
      match
        static_debug_entry_probe(capacity, input, prepared, nodes, max_work / 4) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(value) => value
      }
    } else {
      (false, 0)
    }
    let (original, plan) = match
      @publication_host.capture_client_static_pure_explanation_original(
        prepared,
        compiled,
        bytes,
        nodes,
        depth,
        debug_entry~,
      ) {
      Err(issue) => return Err(Context(issue))
      Ok(value) => value
    }
    let projection = PureProjection(original)
    construct_static_explanation_facets_working(
      capacity,
      input,
      projection,
      plan,
      current,
      bounded,
      max_work - probe_work,
      limits.0,
      reserve_js_delivery,
    )
  })
}

///|
/// Dispatch structural Explain using only the compiler selection retained by
/// this Request. The selected owner performs its own working-phase check.
pub fn[I] request_prepared_static_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  infers : Array[@publication_host.ClientInferPlanGraph],
  debug_entry_installed? : Bool = false,
  effect_debug_entry_installed? : Bool = false,
) -> Result[
  ClientRequestStaticEffectExplanation,
  ClientRequestStaticContextIssue,
] {
  if owner.compiled_effect is Some(_) {
    request_prepared_static_effect_explanation(
      owner,
      input,
      manifests,
      max_bytes,
      max_nodes,
      max_depth,
      max_work,
      infers~,
      debug_entry_installed=effect_debug_entry_installed,
    )
  } else {
    prepare_static_pure_explanation_facets(
      owner,
      input,
      manifests,
      (max_bytes, max_nodes, max_depth),
      max_work,
      infers,
      true,
      debug_entry_installed~,
    )
  }
}

///|
/// Native uses the same bounded envelope and renderer for either compiler.
pub fn[I] request_prepared_static_pure_explanation_output(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
  language : @publication_host.ClientExplanationLanguage?,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> Result[String, ClientRequestStaticContextIssue] {
  if max_bytes < 1 {
    return Err(Preparation(Policy))
  }
  let facets = match
    prepare_static_pure_explanation_facets(
      owner,
      input,
      manifests,
      (65536, max_nodes, max_depth),
      max_work,
      infers,
      false,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  with_request_static_pure_explanation(
    owner,
    input,
    (max_bytes, max_nodes, max_depth),
    max_work,
    (capacity, _, current, bounded) => {
      finish_request_static_explanation_output(
        capacity, input, facets, current, bounded, language,
      )
    },
  )
}
