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
    let (original, plan) = match
      @publication_host.capture_client_static_pure_explanation_original(
        prepared, compiled, bytes, nodes, depth,
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
      max_work,
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
