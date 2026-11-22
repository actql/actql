///|
// Raw Native files remain original text, including malformed input. They do
// not first pass through submitted-intent admission or a detached JSON tree.
// Preserve the installed structural policy; only raw wire storage follows
// the actual immutable document. This is not an additional Resource grant.
fn request_native_document_limits(
  document : String,
  limits : @syntax.Limits,
) -> @syntax.Limits? {
  let bound = document.length().to_int64() * 4L
  if bound >= 2147483519L {
    return None
  }
  let bytes = Int::max(limits.source.max_input_bytes, bound.to_int())
  Some({
    ..limits,
    source: { ..limits.source, max_input_bytes: bytes, },
    tree: {
      ..limits.tree,
      max_string_bytes: Int::max(limits.tree.max_string_bytes, bytes),
      max_total_string_bytes: Int::max(
        limits.tree.max_total_string_bytes,
        bytes,
      ),
    },
  })
}

///|
fn[I] reserve_request_native_document_read(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  limits : @syntax.Limits,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard request_document_parse_bytes(document, limits) is Some(bytes) else {
    return Err(Policy)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      Err(Capacity(issue))
    }
    Ok(_) => Ok(())
  }
}

///|
/// The ordinary static Native caller's SAME Request. Parameters are admitted
/// first, once; JSON/YAML Program and SQL/Pipe Query retain their original
/// parser/checker failures. No intent, compiler, Run or Plan is issued here.
pub fn[I] prepare_request_native_document_check(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  format : @frontend.Format,
  parameters : String?,
  declarations : String?,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  static_check? : Bool = true,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == Open &&
    !owner.native_parameters_ready &&
    owner.program_json is None &&
    owner.query_syntax is None &&
    request_intent_input_ready(owner) else {
    return Err(Preparation(WrongPhase))
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  let standard = match
    request_default_program_preparation_limits(owner, input) {
    Err(issue) => return Err(issue)
    Ok(limits) => limits
  }
  let limits = match
    request_native_document_limits(document, standard.checking.input) {
    None => return Err(Preparation(Policy))
    Some(value) => value
  }
  if parameters is Some(body) {
    let (source, tree) = @local_preparation.local_parameter_input_limits()
    let selected = match
      request_native_document_limits(body, { source, tree, max_stages: 0, }) {
      None => return Err(Preparation(Policy))
      Some(value) => value
    }
    let selected = { ..selected, tree, }
    match reserve_request_native_document_read(owner, input, body, selected) {
      Err(issue) => return Err(Preparation(issue))
      Ok(_) => ()
    }
    owner.native_parameters = match
      @local_preparation.admit_local_parameter_document(
        body,
        selected.source,
        selected.tree,
      ) {
      Err(issue) => {
        owner.phase = ProgramJsonFailed
        return Err(Preparation(Parameters(issue)))
      }
      Ok(value) => Some(value)
    }
    owner.phase = Open
  }
  owner.native_parameters_ready = true
  if declarations is Some(body) {
    if format != @frontend.Sql && format != @frontend.Text {
      owner.phase = ProgramJsonFailed
      return Err(Preparation(Parameters(@local_preparation.InvalidFormat)))
    }
    let (source, tree) = @source_publication.source_publication_input_limits()
    let selected = match
      request_native_document_limits(body, { source, tree, max_stages: 0, }) {
      None => return Err(Preparation(Policy))
      Some(value) => value
    }
    let selected = { ..selected, tree, }
    match reserve_request_native_document_read(owner, input, body, selected) {
      Err(issue) => return Err(Preparation(issue))
      Ok(_) => ()
    }
    owner.native_query_declarations = match
      @source_publication.admit_query_declarations_document(
        body,
        selected.source,
        selected.tree,
      ) {
      Err(issue) => {
        owner.phase = ProgramJsonFailed
        return Err(Publication(@source_publication.Publication(issue)))
      }
      Ok(value) => Some(value)
    }
    owner.phase = Open
  }
  let program_limits = {
    ..standard,
    checking: { ..standard.checking, input: limits, },
  }
  if format == @frontend.Json || format == @frontend.Yaml {
    match
      prepare_request_document_computation_input(
        owner,
        input,
        document,
        if format == @frontend.Json {
          @syntax.Json
        } else {
          @syntax.Yaml
        },
        limits,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  } else {
    owner.computation_limits = Some(program_limits)
    match
      parse_request_query_syntax(
        owner,
        input,
        document,
        format,
        lexical_work=request_source_lexical_work(document),
      ) {
      Err(issue) => return Err(QuerySyntax(issue))
      Ok(_) => ()
    }
    match
      lower_request_published_query(
        owner,
        input,
        publication,
        environment,
        None,
        public_primary=false,
        binding_limits=Some(request_query_binding_limits(standard.checking)),
      ) {
      Err(issue) => return Err(QueryLowering(issue))
      Ok(_) => ()
    }
  }
  let catalog = match
    @source_publication.prepared_published_query_catalog(
      publication, environment,
    ) {
    Err(issue) => return Err(Publication(issue))
    Ok(value) => value
  }
  let program_limits = match
    request_default_lowered_program_limits(owner, program_limits) {
    Err(issue) => return Err(issue)
    Ok(limits) => limits
  }
  let (program_limits, effect_limits) = request_original_query_check_limits(
    owner,
    program_limits,
    {
      ..@publication_host.client_standard_effect_computation_limits(),
      program: program_limits,
    },
  )
  let checked = prepare_request_original_computation_check_owned(
    owner,
    input,
    environment,
    catalog,
    [],
    program_limits,
    effect_limits,
  )
  match checked {
    Err(Preparation(ProgramCheck(issue))) if static_check => {
      let diagnostic = match issue {
        Check(cause)
        | Catalog(@checked.Check(cause))
        | EffectInput(@checked.Computation(cause)) =>
          Some(@checked.construction_failure_diagnostic(cause))
        SourceRegistration(@checked.RegistrationConstruction(cause)) =>
          Some(@checked.construction_failure_diagnostic(cause))
        SourceRegistration(@checked.ContextInput(cause))
        | TopologyEntry(cause) =>
          Some(@checked.source_context_diagnostic(cause))
        _ => None
      }
      if diagnostic is Some(diagnostic) &&
        owner.program_check is Some(child) &&
        !child.busy &&
        child.work is None &&
        child.arguments is Some(_) {
        // Retain the SAME typed early checker refusal. No remaining semantic
        // work, compiled candidate, completion or physical ACK is invented.
        let outcome = @checked.original_check_diagnostic_outcome(diagnostic)
        child.check_outcome = Some(outcome)
        child.phase = PreparationRejected
        return Err(CheckOutcome(outcome))
      }
      checked
    }
    Ok(_) if static_check =>
      prepare_request_static_effect_check(owner, input, publication)
    _ => checked
  }
}

///|
// Stop at the existing complete static Mapping closure. Reuse the SAME
// already checked candidate and the existing full compilation envelope before
// entry, but call no lowerer/compiler, Plan, provider or Run constructor.
fn[I] prepare_request_static_effect_check(
  owner : ClientRequestPreparation[I],
  input : I,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.arguments is Some(arguments) else {
    return Err(Preparation(ForeignOriginal))
  }
  guard child.effect_limits is Some(limits) else { return Ok(()) }
  guard child.effect_candidate is Some(candidate) &&
    child.check_data is Some(data) &&
    (child.phase == SemanticCheckComplete || child.phase == CompilationQuoted) else {
    return Err(Preparation(WrongPhase))
  }
  let selected = match child.static_effect_check {
    Some(selected) => {
      if !physical_equal(selected.publication, publication) {
        return Err(Preparation(ForeignOriginal))
      }
      selected
    }
    None => {
      // This retained input/result record is in the initial 168-byte packet,
      // before any fallible variable-data grow or static constructor.
      let selected : ClientStaticEffectCheckData = {
        publication,
        result: None,
      }
      child.static_effect_check = Some(selected)
      selected
    }
  }
  if selected.result is Some(result) {
    return result
      .map(_ => ())
      .map_err(issue => Preparation(ProgramCheck(EffectCompilation(issue))))
  }
  owner.phase = Selecting
  child.busy = true
  preparation_module_call(
    () => {
      let checked = @checked.effect_computation_checked_program(candidate)
      match
        reserve_program_compilation_quote(
          child,
          input,
          checked,
          data,
          limits.program,
        ) {
        Err(issue) => return Err(Preparation(ProgramCheck(issue)))
        Ok(_) => ()
      }
      guard owner.phase == Selecting &&
        child.busy &&
        child.phase == CompilationQuoted &&
        owner.input is Some(current_input) &&
        physical_equal(current_input, input) &&
        owner.program_check is Some(current_child) &&
        physical_equal(current_child, child) &&
        child.arguments is Some(current_arguments) &&
        physical_equal(current_arguments, arguments) &&
        child.effect_candidate is Some(current) &&
        physical_equal(current, candidate) &&
        child.static_effect_check is Some(current_selected) &&
        physical_equal(current_selected, selected) else {
        return Err(Preparation(ForeignOriginal))
      }
      // This is the identical prefix of the existing Effect compiler. Its
      // finite Mapping/static limits remain unchanged; no unavailable binding
      // work is fabricated from a maximum, and no LowerAndGraph work is run.
      let result = match
        @environment.check_mapping_contract_shapes(
          @checked.effect_computation_environment(candidate),
          limits.mapping,
          limits.max_mapping_work,
        ) {
        Err(issue) =>
          Err(@publication_host.ClientEffectComputationIssue::Mapping(issue))
        Ok(mappings) =>
          @checked.close_effect_computation_static(
            candidate,
            mappings,
            limits.effects,
          ).map_err(issue => {
            @publication_host.ClientEffectComputationIssue::Static(issue)
          })
      }
      selected.result = Some(result)
      result
      .map(_ => ())
      .map_err(issue => Preparation(ProgramCheck(EffectCompilation(issue))))
    },
    () => {
      child.busy = false
      if owner.phase == Selecting {
        owner.phase = ProgramCheck
      }
    },
  )
}

///|
/// The report/Plan writer is a distinct, existing output lifetime on the SAME
/// static Request. Keep its debit through the original physical retirement.
/// This grants no Run, Source acquisition or permission.
pub fn[I] reserve_request_native_static_observation(
  owner : ClientRequestPreparation[I],
  input : I,
  publication : String,
  label_units : Int64,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.phase != Selecting &&
    owner.phase != Closed &&
    owner.phase != Retiring else {
    return Err(ForeignOriginal)
  }
  guard request_check_observation_inventory_bytes(publication, 4L, label_units)
    is Some(bytes) else {
    return Err(Policy)
  }
  let phase = owner.phase
  owner.phase = Selecting
  let result : Result[Unit, ClientRequestPreparationIssue] = preparation_module_call(
    () => {
      let (r, e) = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      let r = @execution.checked_preparation_add_product(r, bytes, 1L).unwrap_or(
        -1L,
      )
      let e = @execution.checked_preparation_add_product(e, bytes, 1L).unwrap_or(
        -1L,
      )
      if r < 0L || e < 0L {
        return Err(Policy)
      }
      @resources.reserve_working_preparation_phase(owner.capacity, input, r, e).map_err(issue => {
          ClientRequestPreparationIssue::Capacity(issue)
        },
      )
    },
    () => owner.phase = phase,
  )
  result
}

///|
/// Produce the existing static Plan view from this SAME checked compiler.
/// This selects no module/provider/Engine, publishes no Run and performs no
/// input check again. The compiler/Plan construction debit remains held on
/// the original Request until its actual parent acknowledges retirement.
pub fn[I] request_native_static_plan_view(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  manifests : @publication_host.ClientCompilationManifests,
) -> Result[String, ClientRequestTerminalIssue] {
  match
    finish_request_checked_computation(owner, input, environment, publication) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  request_prepared_static_plan_view(owner, input, manifests, 65536, 8192, 64)
}

///|
/// Read the same already-checked compiler on its existing Request capacity.
/// No semantic checker, invocation, provider or executable body is entered.
/// The caller's read bounds can tighten the original finite issuer policy.
pub fn[I] request_prepared_static_plan_view(
  owner : ClientRequestPreparation[I],
  input : I,
  manifests : @publication_host.ClientCompilationManifests,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> Result[String, ClientRequestTerminalIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(Preparation(Policy))
  }
  let bytes = Int::min(max_bytes, 65536)
  let nodes = Int::min(max_nodes, 8192)
  let depth = Int::min(max_depth, 64)
  let kind : ClientRequestComputationKind = if owner.phase == EffectPlanReserved &&
    owner.compiled_effect is Some(_) &&
    owner.effect_plan is None {
    // The original Plan-input borrow can prepare its metadata-only Model
    // graphs on this SAME capacity. It has not constructed an executable body.
    guard owner.input is Some(original) && physical_equal(original, input) else {
      return Err(Preparation(ForeignOriginal))
    }
    Effect
  } else {
    match request_prepared_computation_kind(owner, input) {
      Err(issue) => return Err(Preparation(issue))
      Ok(value) => value
    }
  }
  if kind == Pure && !infers.is_empty() {
    return Err(Preparation(ForeignOriginal))
  }
  let data = match owner.program_data {
    None => return Err(Preparation(WrongPhase))
    Some(value) => value
  }
  let phase = owner.phase
  owner.phase = Selecting
  let result : Result[String, ClientRequestTerminalIssue] = preparation_module_call(
    () => {
      let reserved = match kind {
        Pure =>
          reserve_native_static_plan_capacity(
            owner.program_capacity.unwrap(),
            input,
            data,
            @publication_host.prepared_client_graph(
              owner.compiled_program.unwrap(),
            ),
            bytes,
            nodes,
            depth,
          )
        Effect =>
          reserve_native_static_plan_capacity(
            owner.effect_capacity.unwrap(),
            input,
            data,
            @strategy.checked_effect_computation_graph(
              @publication_host.prepared_client_effect_computation_graph(
                owner.compiled_effect.unwrap(),
              ),
            ),
            bytes,
            nodes,
            depth,
          )
      }
      match reserved {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      match kind {
        Pure => {
          let prepared = owner.compiled_program.unwrap()
          if @publication_host.prepared_client_acquisition_count(prepared) != 0 {
            return Err(Preparation(Policy))
          }
          let compiled = match
            @publication_host.issue_prepared_client_task_compilation(
              prepared,
              manifests,
              @publication_host.prepared_client_values_sequence_limits(prepared),
              1000,
              1000,
              bytes,
              nodes,
              depth,
            ) {
            Err(_) => return Err(Preparation(Policy))
            Ok(value) => value
          }
          @publication_host.client_task_static_plan_view(
            prepared,
            compiled,
            bytes,
            nodes,
            depth,
            inspect_installed=false,
          ).map_err(_ => Preparation(Policy))
        }
        Effect => {
          let prepared = owner.compiled_effect.unwrap()
          // The actual compiler checks every acquired route and the nominal
          // Model occurrence/Graph binding. A captured prefix is not itself a
          // reason to reject a legal static Plan; no acquisition is executed.
          let compiled = match
            issue_request_static_effect_plan_compilation(
              prepared,
              manifests,
              (bytes, nodes, depth),
              infers,
            ) {
            Err(_) => return Err(Preparation(Policy))
            Ok(value) => value
          }
          @publication_host.client_effectful_static_plan_view(
            prepared, compiled, bytes, nodes, depth,
          ).map_err(_ => Preparation(Policy))
        }
      }
    },
    () => owner.phase = phase,
  )
  result
}

///|
fn[I, P] reserve_native_static_plan_capacity(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  data : @checked.ParsedCheckDataEstimate,
  graph : @strategy.CheckedDAG,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard installed_text_bound_views_layout(graph) is Some(text_bound_views) else {
    return Err(Policy)
  }
  let (r, e) = match
    original_request_plan_construction_quote(
      capacity,
      input,
      data,
      text_bound_views~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Static Plan output uses its existing writer policy, separate from the
  // check-report writer. Back that one actual output before its constructor.
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(output) &&
    @execution.checked_preparation_add_product(r, output, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, output, 1L) is Some(e) else {
    return Err(Policy)
  }
  @resources.reserve_working_preparation_phase(capacity, input, r, e).map_err(issue => {
    ClientRequestPreparationIssue::Capacity(issue)
  })
}

///|
// Both static readers issue the same compiler Plan. The metadata-only Model
// originals belong to the checked Effect; the compiler verifies identity and
// scope. Its singleton and composed branches have distinct inputs.
fn issue_request_static_effect_plan_compilation(
  prepared : @publication_host.PreparedClientEffectComputation,
  manifests : @publication_host.ClientCompilationManifests,
  limits : (Int, Int, Int),
  infers : Array[@publication_host.ClientInferPlanGraph],
) -> Result[
  @publication_host.ClientEffectCompilation,
  ClientRequestPreparationIssue,
] {
  let (bytes, nodes, depth) = limits
  @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    bytes,
    nodes,
    depth,
    infer=if infers.length() == 1 { Some(infers[0]) } else { None },
    infers=if infers.length() == 1 { [] } else { infers },
  ).map_err(_ => Policy)
}
