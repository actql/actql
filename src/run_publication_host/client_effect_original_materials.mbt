///|
/// Project materials directly from the original checked preparation and Run.
/// No caller-supplied Program, parameters or check environment can replace
/// those Owners. This does not reconstruct a preparation, extend lifetime,
/// create authorization or establish cross-process normalization custody.
pub fn issue_prepared_client_effect_run_materials(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request? : ClientRequestIdentity? = None,
  normalization? : ClientEffectNormalization? = None,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let prepared = client_effect_compilation_owner(allowed.compilation)
  match bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  let normalization_wire = match normalization {
    None => None
    Some(original) =>
      match prepared_client_effect_normalization_evidence(prepared, original) {
        Ok(value) => Some(@publication.run_evidence_value_json(value))
        Err(issue) => return Err(Normalization(issue))
      }
  }
  let request_wire = match request {
    None => None
    Some(value) => {
      match prepared_client_effect_request_scope(prepared, value) {
        Ok(_) => ()
        Err(issue) => return Err(Request(issue))
      }
      if client_request_input_cid(value) !=
        source_free_caller_input_intent_cid() {
        return Err(Request(IdentityMismatch))
      }
      match client_request_identity_record_wire(value) {
        Ok(wire) => Some(wire)
        Err(issue) => return Err(Request(issue))
      }
    }
  }
  let (program, parameters, environment) = try {
    let source_writer = @encode.writer(65536, 8192, 64)
    @syntax.emit_program_source(prepared.source, source_writer)
    let program = @encode.finish(source_writer)
    let parameters = match prepared.supplied {
      None => None
      Some(value) => {
        let writer = @encode.writer(65536, 8192, 64)
        @syntax.emit_admitted_source_value(value, writer)
        Some(@encode.finish(writer))
      }
    }
    let environment_writer = @encode.writer(65536, 4096, 64)
    @environment.emit(
      @checked.effect_program_static_environment(prepared.candidate),
      environment_writer,
    )
    (program, parameters, @encode.finish(environment_writer))
  } catch {
    _ => return Err(Input(MaterialsMalformed))
  }
  encode_client_run_materials_body(
    allowed.admission,
    definition,
    prepared_client_effect_computation_environment_cid(prepared),
    environment,
    program,
    parameters,
    request_wire~,
    normalization_wire~,
  ).map_err(fn(issue) { ClientEffectRunMaterialsIssue::Input(issue) })
}
