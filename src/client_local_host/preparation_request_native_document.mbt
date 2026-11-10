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
  let standard = @publication_host.client_standard_program_preparation_limits()
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
    match parse_request_query_syntax(owner, input, document, format) {
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
  let program_limits = {
    ..standard,
    checking: { ..standard.checking, input: limits, },
  }
  let catalog = match
    @source_publication.prepared_published_query_catalog(
      publication, environment,
    ) {
    Err(issue) => return Err(Publication(issue))
    Ok(value) => value
  }
  let checked = prepare_request_original_computation_check_owned(
    owner,
    input,
    environment,
    catalog,
    [],
    program_limits,
    {
      ..@publication_host.client_standard_effect_computation_limits(),
      program: program_limits,
    },
    static_check~,
  )
  match checked {
    Err(Preparation(ProgramCheck(issue))) if static_check => {
      let diagnostic = match issue {
        Check(cause) | Catalog(@checked.Check(cause)) =>
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
    _ => checked
  }
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
  let kind = match
    finish_request_checked_computation(owner, input, environment, publication) {
    Err(issue) => return Err(issue)
    Ok(value) => value
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
          )
        Effect =>
          reserve_native_static_plan_capacity(
            owner.effect_capacity.unwrap(),
            input,
            data,
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
              65536,
              8192,
              64,
            ) {
            Err(_) => return Err(Preparation(Policy))
            Ok(value) => value
          }
          @publication_host.client_task_static_plan_view(
            prepared,
            compiled,
            65536,
            8192,
            64,
            inspect_installed=false,
          ).map_err(_ => Preparation(Policy))
        }
        Effect => {
          let prepared = owner.compiled_effect.unwrap()
          if @strategy.graph_captured_prefix(
              @strategy.checked_effect_computation_graph(
                @publication_host.prepared_client_effect_computation_graph(
                  prepared,
                ),
              ),
            ) !=
            0 {
            return Err(Preparation(Policy))
          }
          let compiled = match
            @publication_host.issue_prepared_client_effect_compilation(
              prepared,
              manifests,
              @publication_host.client_standard_values_sequence_limits(),
              1000,
              1000,
              65536,
              8192,
              64,
            ) {
            Err(_) => return Err(Preparation(Policy))
            Ok(value) => value
          }
          @publication_host.client_effectful_static_plan_view(
            prepared, compiled, 65536, 8192, 64,
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
) -> Result[Unit, ClientRequestPreparationIssue] {
  let (r, e) = match
    original_request_plan_construction_quote(capacity, input, data) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Static Plan output uses its existing writer policy, separate from the
  // check-report writer. Back that one actual output before its constructor.
  guard @encode.text_writer_construction_inventory(65536, 8192, 64)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + 65536L,
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
