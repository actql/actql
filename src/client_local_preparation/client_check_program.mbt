///|
/// Nonexecuting observation of the original Program. Existing admission,
/// binding, Source inventory and checking Owners determine every input fact.
/// No checked handle, Run or dispatch permit leaves this reporting bridge.
pub fn client_program_check_program(
  document : String,
  environment : @checked.CheckEnvironment,
  visible_publication : String,
  parameters : String?,
  context_ref : String,
  program_revision : String,
  parameters_revision : String?,
  correlation_ref : String,
  scope : String,
  selector_namespace : ClientCheckSourceSelectorNamespace?,
) -> String {
  client_program_check_program_with_format(
    document, "json", environment, visible_publication, parameters, context_ref,
    program_revision, parameters_revision, correlation_ref, scope, selector_namespace,
  )
}

///|
/// The same checker observes the original JSON or YAML Program. The Host binds
/// its admitted format and exact source bytes into the original check context;
/// this port never serializes one syntax into another or issues a checked Run.
pub fn client_program_check_program_with_format(
  document : String,
  format : String,
  environment : @checked.CheckEnvironment,
  visible_publication : String,
  parameters : String?,
  context_ref : String,
  program_revision : String,
  parameters_revision : String?,
  correlation_ref : String,
  scope : String,
  selector_namespace : ClientCheckSourceSelectorNamespace?,
) -> String {
  let format = match admit_local_program_input(format, None) {
    Ok((format, _)) => format
    Err(_) => return check_failed_json("check_request_invalid", correlation_ref)
  }
  let scope = match check_scope(scope) {
    Some(scope) => scope
    None => return check_failed_json("check_request_invalid", correlation_ref)
  }
  if scope == TemplateOnly && parameters is Some(_) {
    return check_failed_json("check_request_invalid", correlation_ref)
  }
  if selector_namespace is Some(proof) &&
    (
      !physical_equal(proof.range.environment, environment) ||
      proof.context_ref != context_ref ||
      proof.program_revision != program_revision
    ) {
    return check_failed_json("check_context_invalid", correlation_ref)
  }
  let findings : Array[CheckFinding] = []
  let mut pointer = None
  let stop = check_program_findings(
    findings,
    document,
    environment,
    visible_publication,
    parameters,
    value => pointer = value,
    scope,
    selector_namespace,
    format,
  )
  check_outcome_json(findings, stop, context_ref, correlation_ref, {
    scope,
    structured_program: true,
    program_pointer: pointer,
    source_revision: program_revision,
    source_bytes: @utf8.encode(document).length(),
    declarations_revision: Some(program_revision),
    declarations_bytes: 0,
    parameters_revision,
    parameters_bytes: parameters
    .map(body => @utf8.encode(body).length())
    .unwrap_or(0),
  })
}

///|
fn check_program_findings(
  findings : Array[CheckFinding],
  document : String,
  environment : @checked.CheckEnvironment,
  visible_publication : String,
  parameters : String?,
  locate : (String?) -> Unit,
  scope : @checked.CheckScope,
  selector_namespace : ClientCheckSourceSelectorNamespace?,
  format : @syntax.Format,
) -> CheckStop {
  let limits = @host.client_standard_program_preparation_limits().checking
  let supplied = match admit_local_program_input("json", parameters) {
    Ok((_, supplied)) => supplied
    Err(SuppliedSyntax(issue)) => {
      findings.push(
        if check_parse_budget(issue.issue) {
          Limit("analysis_budget_exhausted")
        } else {
          SuppliedParseViolation(None)
        },
      )
      return Report
    }
    Err(SuppliedAdmission(issue)) => {
      findings.push(
        if issue.kind is BudgetExceeded {
          Limit("analysis_budget_exhausted")
        } else {
          SuppliedViolation(None)
        },
      )
      return Report
    }
    Err(_) => return Failed("check_internal")
  }
  let program = match @syntax.parse(document, limits.input, format~) {
    Ok(program) => program
    Err(_) => {
      // Classification remains the common checker's decision. Reuse its
      // document entry only when admission did not produce an owned Program.
      guard @checked.check_document(
          document,
          environment,
          supplied,
          limits,
          format~,
        )
        is Rejected(diagnostic) else {
        return Failed("check_internal")
      }
      return check_program_diagnostic(
        findings,
        diagnostic,
        document,
        supplied,
        parameters,
        locate,
        format~,
      )
    }
  }
  let source = match
    @stage_parameters.prepare(program, {
      max_parameters: 1024,
      max_nodes: 8192,
      max_depth: 64,
      max_text_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => {
      guard @checked.check_parsed(program, environment, supplied, limits)
        is Rejected(diagnostic) else {
        return Failed("check_internal")
      }
      return check_program_diagnostic(
        findings,
        diagnostic,
        document,
        supplied,
        parameters,
        locate,
        format~,
        original_body=Some(@syntax.program_body(program)),
      )
    }
  }
  let declarations = @stage_parameters.declarations(source)
  // Declaration-owned requirements are independent of private resolution.
  // Presence is read from the supplied object, so an explicit null is never
  // turned into an absent binding. This does not validate supplied values.
  check_missing_value_findings(findings, declarations, supplied, scope)
  let mut binding_invalid = false
  let (source, binding) = @stage_parameters.prepare_bindings(source, supplied, {
    max_nodes: 8192,
    max_depth: 64,
    max_text_bytes: 65536,
  })
  match binding {
    Ok(_) => ()
    Err(issue) =>
      match check_binding_fault(issue) {
        Invalid => {
          findings.push(
            check_supplied_type_finding(
              issue, declarations, supplied, parameters,
            ),
          )
          binding_invalid = true
        }
        Budget => {
          findings.push(Limit("analysis_budget_exhausted"))
          binding_invalid = true
        }
        Internal => return Failed("check_internal")
      }
  }
  // Inventory belongs to the existing Source Owner. It is admitted before
  // consulting installed contracts; absent and denied names share one public
  // unresolved boundary. No protected cursor, count or expected type escapes.
  let inputs = match
    @sourceview_input.collect(source, {
      max_work: 1000000,
      max_order_keys: 1024,
    }) {
    Ok(value) => value
    Err(WorkLimit | OrderLimit) => {
      findings.push(Limit("analysis_budget_exhausted"))
      return Report
    }
    Err(_) => {
      guard @checked.check_parsed(
          program,
          environment,
          supplied,
          limits,
          source_preparation=Some(source),
        )
        is Rejected(diagnostic) else {
        return Failed("check_internal")
      }
      // An invalid authored Source declaration is proven without the Catalog.
      return check_program_diagnostic(
        findings,
        diagnostic,
        document,
        supplied,
        parameters,
        locate,
        format~,
        original_body=Some(@syntax.program_body(program)),
      )
    }
  }
  let publication = source_publication_cursor(visible_publication) catch {
    _ => return Failed("check_context_invalid")
  }
  let _ = check_published_context(environment, visible_publication, None) catch {
    CheckPublicationStop(Limit) => {
      findings.push(Limit("analysis_budget_exhausted"))
      return Report
    }
    _ => return Failed("check_context_invalid")
  }
  guard @decode.open_object(publication) is Ok(publication_object) &&
    @decode.lookup(publication_object, "aliases") is Some(aliases_node) &&
    @decode.elements(aliases_node) is Ok(aliases) else {
    return Failed("check_context_invalid")
  }
  // Absence concerns installed selector registration, never Provider Resource
  // existence. Only the actual resolver's failure witness under the complete
  // unfiltered Catalog may close this obligation for the original declaration.
  let mut unregistered : @sourceview_input.Declaration? = None
  if selector_namespace is Some(proof) {
    match
      @acquisition.resolve(inputs, proof.range.catalog, {
        max_work: 1000000,
        max_inputs: 1024,
        max_views: 1024,
      }) {
      Ok(_) => ()
      Err(issue) => {
        if issue.kind is (WorkLimit | InputLimit | ViewLimit) {
          findings.push(Limit("analysis_budget_exhausted"))
          return Report
        }
        if @acquisition.unresolved_selector_declaration(
            issue,
            inputs,
            proof.range.catalog,
          )
          is Some(declaration) &&
          issue.source is Some(cursor) {
          unregistered = Some(declaration)
          findings.push(
            SourceSelectorUnregistered(
              proof.name,
              declaration,
              check_program_original_pointer(
                document,
                @decode.cursor_path(cursor),
                format~,
                original_body=Some(@syntax.program_body(program)),
              ),
            ),
          )
        }
      }
    }
  }
  let mut has_hidden_dependency = false
  for index in 0..<@sourceview_input.count(inputs) {
    let input = @sourceview_input.at(inputs, index).unwrap()
    let visible = input.view is Some(view) &&
      aliases.any(entry => {
        check_program_public_text(entry, "sourceRef") ==
        Some(
          "connector://" + input.connector + "/" + input.resource + "#" + view,
        )
      })
    if !visible &&
      !(unregistered is Some(declaration) && physical_equal(declaration, input)) {
      has_hidden_dependency = true
    }
  }
  // Local reference shorthand requires separately owned publication evidence.
  // Its private installation must not be inferred from a semantic rejection.
  for stage in @syntax.stages(program) {
    if @syntax.stage_table_input_count(stage) > 0 {
      has_hidden_dependency = true
    }
    let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
    let stage_inputs = @decode.required(body, "inputs").unwrap()
    for index in 0..<@decode.object_length(stage_inputs).unwrap() {
      let (_, input) = @decode.field_at(stage_inputs, index).unwrap()
      if @decode.view(input) is TextValue(_) {
        has_hidden_dependency = true
      }
    }
  }
  if has_hidden_dependency {
    // The common checker audits unsupported authored declarations before
    // consulting Sources. Preserve that independent limitation as well.
    if @checked.check_parsed(
        program,
        environment,
        supplied,
        limits,
        source_preparation=Some(source),
      )
      is Rejected(diagnostic) &&
      @checked.diagnostic_cause(diagnostic)
      is Source(UnsupportedBindings(_) | UnsupportedEffects(_)) {
      let _ = check_program_diagnostic(
        findings,
        diagnostic,
        document,
        supplied,
        parameters,
        locate,
        format~,
        original_body=Some(@syntax.program_body(program)),
      )
    }
    findings.push(Unresolved("source_resolution"))
    return Report
  }
  if binding_invalid || unregistered is Some(_) {
    return Report
  }
  let outcome : CheckProjection = match scope {
    BoundInput =>
      Bound(
        @checked.check_parsed(
          program,
          environment,
          supplied,
          limits,
          source_preparation=Some(source),
        ),
      )
    TemplateOnly =>
      match
        @checked.check_parsed_scoped(
          program,
          environment,
          TemplateOnly,
          None,
          limits,
          source_preparation=Some(source),
        ) {
        TemplateOnly(Verified(checked)) =>
          return check_template_public_stop(findings, checked)
        TemplateOnly(Rejected(diagnostic)) => TemplateDiagnostic(diagnostic)
        TemplateOnly(Unresolved(frontier)) => {
          let diagnostic = @checked.template_frontier_diagnostic(frontier).unwrap()
          if @checked.diagnostic_category(diagnostic) == MissingInput {
            check_missing_input_findings(findings, diagnostic, scope)
            return Report
          }
          TemplateDiagnostic(diagnostic)
        }
        _ => return Failed("check_internal")
      }
  }
  match outcome {
    Bound(Checked(_)) => Report
    Bound(NeedsInputs(requests)) => {
      for index in 0..<@checked.input_request_count(requests) {
        match @checked.input_request_at(requests, index).unwrap().kind {
          ParameterValue(_) => () // Already retained from the admitted declarations.
          HostCapacityPolicy => {
            findings.push(CapacityPolicyRequired)
            findings.push(Limit("checking_context_missing"))
          }
          NumericReductionProfile(_) => {
            findings.push(NumericProfileRequired)
            findings.push(Limit("checking_context_missing"))
          }
          _ => findings.push(Limit("bound_values_missing"))
        }
      }
      Report
    }
    Bound(Rejected(diagnostic)) | TemplateDiagnostic(diagnostic) => {
      // The pure checker deliberately rejects Effects. As for authored text,
      // observe the exact admitted Program through the existing static Effect
      // closure, only after audience-visible Source obligations are resolved.
      // No Run, approval, physical grant or dispatch is issued by this check.
      if scope == BoundInput &&
        @checked.diagnostic_cause(diagnostic) is Source(UnsupportedEffects(_)) {
        match
          @host.prepare_parsed_client_effect_computation(
            program,
            environment,
            supplied,
            [],
            @host.client_standard_effect_computation_limits(),
          ) {
          Ok(_) => return Report
          // Keep the limitation on any failed static closure. It must never
          // turn an unclosed Command or Mapping into a verified report.
          Err(_) => ()
        }
      }
      check_program_diagnostic(
        findings,
        diagnostic,
        document,
        supplied,
        parameters,
        locate,
        format~,
        original_body=Some(@syntax.program_body(program)),
      )
    }
  }
}

///|
fn check_program_diagnostic(
  findings : Array[CheckFinding],
  diagnostic : @checked.CheckDiagnostic,
  document : String,
  supplied : @decode.Cursor?,
  parameters : String?,
  locate : (String?) -> Unit,
  format? : @syntax.Format = Json,
  original_body? : @decode.Cursor? = None,
  retained_program? : @syntax.Program? = None,
) -> CheckStop {
  let mut original_pointer = None
  if retained_program is None &&
    @checked.diagnostic_origin(diagnostic) is Some(ProgramDocument) &&
    @checked.diagnostic_location(diagnostic) is Some(location) &&
    @checked.diagnostic_location_path(location) is Some(path) {
    original_pointer = check_program_original_pointer(
      document,
      path,
      format~,
      original_body~,
    )
  }
  match @checked.diagnostic_category(diagnostic) {
    InvalidInput => {
      locate(original_pointer)
      let cause = @checked.diagnostic_cause(diagnostic)
      let structure = match cause {
        Program(Decode(issue)) =>
          Some(
            match issue.kind {
              MissingField => "missing_field"
              WrongType => "wrong_type"
              UnexpectedNull => "unexpected_null"
              _ => "invalid_structure"
            },
          )
        Source(Registration(Declarations(Decode(issue)))) =>
          Some(
            match issue.kind {
              MissingField => "missing_field"
              WrongType => "wrong_type"
              UnexpectedNull => "unexpected_null"
              _ => "invalid_structure"
            },
          )
        Source(Registration(Declarations(InvalidValue(_) | InvalidMetadata(_)))) =>
          Some("invalid_structure")
        Program(_) => Some("invalid_structure")
        _ => None
      }
      if cause is Source(Declarations(Declarations(issue))) &&
        (match retained_program {
          Some(program) => Some(@syntax.program_body(program))
          None => check_program_document_cursor(document, format, original_body)
        })
        is Some(body) &&
        @decode.open_object(body) is Ok(object) &&
        @decode.lookup(object, "params") is Some(params) {
        let location = @checked.diagnostic_location(diagnostic)
        if location is Some(location) &&
          @checked.diagnostic_location_path(location) is Some(path) &&
          path.get(0) is Some(Key("params")) {
          let relative = path[1:].to_owned()
          findings.push(
            check_default_type_finding(
              issue, params, relative, original_pointer,
            ).unwrap_or(DeclarationViolation(original_pointer)),
          )
        } else {
          findings.push(DeclarationViolation(original_pointer))
        }
        return Report
      }
      if cause
        is Source(Identity(References(Usage(UnusedParameter(declaration))))) &&
        declaration.name.length() <= 256 {
        findings.push(
          UnusedParameter(
            declaration.name,
            if retained_program is Some(_) {
              None
            } else {
              Some(
                "/params/" +
                declaration.name
                .replace_all(old="~", new="~0")
                .replace_all(old="/", new="~1"),
              )
            },
          ),
        )
        return Report
      }
      findings.push(
        if structure is Some(issue) {
          ProgramStructureViolation(issue)
        } else {
          check_program_finding(
            diagnostic,
            None,
            supplied,
            parameters,
            None,
            program=retained_program,
          )
        },
      )
    }
    UnsupportedImplementation =>
      findings.push(ProgramLimit("implementation_limit", original_pointer))
    CompileLimit =>
      findings.push(ProgramLimit("analysis_budget_exhausted", original_pointer))
    MissingInput =>
      check_missing_input_findings(findings, diagnostic, BoundInput)
    UnclassifiedFailure => findings.push(Limit("check_unclassified"))
    InvalidConfiguration => return Failed("check_context_invalid")
  }
  Report
}

///|
/// Recover only the Owner's proven path. Missing members locate their existing
/// enclosing node, never a fabricated null value or a generated text position.
fn check_program_original_pointer(
  document : String,
  path : Array[@decode.PathSegment],
  format? : @syntax.Format = Json,
  original_body? : @decode.Cursor? = None,
) -> String? {
  guard path.length() <= 65 &&
    check_program_document_cursor(document, format, original_body) is Some(root) else {
    return None
  }
  for length = path.length(); length >= 0; length = length - 1 {
    let parent = path[:length].to_owned()
    if check_original_pointer(document, root, parent, format~) is Some(pointer) {
      return Some(pointer)
    }
  }
  None
}

///|
/// Keep the legacy JSON diagnostic admission unchanged. YAML findings use the
/// original parsed Program when available; a failed envelope may only borrow a
/// bounded tree from the same original source, never a reconstructed document.
fn check_program_document_cursor(
  document : String,
  format : @syntax.Format,
  original_body : @decode.Cursor?,
) -> @decode.Cursor? {
  if format == Json {
    return match admit_local_program_input("json", Some(document)) {
      Ok((_, body)) => body
      Err(_) => None
    }
  }
  if original_body is Some(_) {
    return original_body
  }
  guard @source.parse_yaml_bytes(@utf8.encode(document), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    })
    is Ok(parsed) else {
    return None
  }
  @decode.admit(parsed, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).to_option()
}

///|
fn check_program_public_text(
  cursor : @decode.Cursor,
  field : String,
) -> String? {
  guard @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, field) is Some(value) else {
    return None
  }
  @decode.text(value).to_option()
}
