///|
/// Nonexecuting observation of the original Program. Existing admission,
/// binding, Source inventory and checking Owners determine every input fact.
/// No checked handle, Run or dispatch permit leaves this reporting bridge.
#export_name("clientProgramCheckProgram")
pub fn client_program_check_program(
  document : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  parameters : String?,
  context_ref : String,
  program_revision : String,
  parameters_revision : String?,
  correlation_ref : String,
  scope : String,
) -> String {
  let scope = match check_scope(scope) {
    Some(scope) => scope
    None => return check_failed_json("check_request_invalid", correlation_ref)
  }
  if scope == TemplateOnly && parameters is Some(_) {
    return check_failed_json("check_request_invalid", correlation_ref)
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
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  parameters : String?,
  locate : (String?) -> Unit,
  scope : @program_check.CheckScope,
) -> CheckStop {
  let limits = client_program_standard_limits().checking
  let supplied = match client_program_input("json", parameters) {
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
  let program = match @stage_syntax.parse(document, limits.input, format=Json) {
    Ok(program) => program
    Err(_) => {
      // Classification remains the common checker's decision. Reuse its
      // document entry only when admission did not produce an owned Program.
      guard @program_check.check_document(
          document,
          environment,
          supplied,
          limits,
          format=Json,
        )
        is Rejected(diagnostic) else {
        return Failed("check_internal")
      }
      return check_program_diagnostic(
        findings, diagnostic, document, supplied, parameters, locate,
      )
    }
  }
  let root = @decode.open_object(@stage_syntax.program_body(program)).unwrap()
  let declarations_node = @decode.lookup(root, "params")
  let declarations = match
    @parameter_binding.read_declarations(declarations_node, {
      max_parameters: 1024,
      max_nodes: 8192,
      max_depth: 64,
      max_text_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => {
      guard @program_check.check_parsed(program, environment, supplied, limits)
        is Rejected(diagnostic) else {
        return Failed("check_internal")
      }
      return check_program_diagnostic(
        findings, diagnostic, document, supplied, parameters, locate,
      )
    }
  }
  // Declaration-owned requirements are independent of private resolution.
  // Presence is read from the supplied object, so an explicit null is never
  // turned into an absent binding. This does not validate supplied values.
  check_missing_value_findings(findings, declarations, supplied, scope)
  let mut binding_invalid = false
  match
    @parameter_binding.bind(declarations, supplied, {
      max_nodes: 8192,
      max_depth: 64,
      max_text_bytes: 65536,
    }) {
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
  let source = match
    @stage_parameters.prepare(program, {
      max_parameters: 1024,
      max_nodes: 8192,
      max_depth: 64,
      max_text_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Failed("check_internal")
  }
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
      guard @program_check.check_parsed(program, environment, supplied, limits)
        is Rejected(diagnostic) else {
        return Failed("check_internal")
      }
      // An invalid authored Source declaration is proven without the Catalog.
      return check_program_diagnostic(
        findings, diagnostic, document, supplied, parameters, locate,
      )
    }
  }
  let publication = source_publication_cursor(visible_publication) catch {
    _ => return Failed("check_context_invalid")
  }
  let _ = client_source_context(environment, visible_publication, None) catch {
    ClientSourceStop(Limit) => {
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
    if !visible {
      has_hidden_dependency = true
    }
  }
  // Local reference shorthand requires separately owned publication evidence.
  // Its private installation must not be inferred from a semantic rejection.
  for stage in @stage_syntax.stages(program) {
    if @stage_syntax.stage_table_input_count(stage) > 0 {
      has_hidden_dependency = true
    }
    let body = @decode.open_object(@stage_syntax.stage_body(stage)).unwrap()
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
    if @program_check.check_parsed(program, environment, supplied, limits)
      is Rejected(diagnostic) &&
      @program_check.diagnostic_cause(diagnostic)
      is Source(UnsupportedBindings(_) | UnsupportedEffects(_)) {
      let _ = check_program_diagnostic(
        findings, diagnostic, document, supplied, parameters, locate,
      )
    }
    findings.push(Unresolved("source_resolution"))
    return Report
  }
  if binding_invalid {
    return Report
  }
  let outcome : CheckProjection = match scope {
    BoundInput =>
      Bound(@program_check.check_parsed(program, environment, supplied, limits))
    TemplateOnly =>
      match
        @program_check.check_parsed_scoped(
          program,
          environment,
          TemplateOnly,
          None,
          limits,
        ) {
        TemplateOnly(Verified(checked)) =>
          return check_template_public_stop(findings, checked)
        TemplateOnly(Rejected(diagnostic)) => TemplateDiagnostic(diagnostic)
        TemplateOnly(Unresolved(frontier)) => {
          let diagnostic = @program_check.template_frontier_diagnostic(frontier).unwrap()
          if @program_check.diagnostic_category(diagnostic) == MissingInput {
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
      for index in 0..<@program_check.input_request_count(requests) {
        match @program_check.input_request_at(requests, index).unwrap().kind {
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
    Bound(Rejected(diagnostic)) | TemplateDiagnostic(diagnostic) =>
      check_program_diagnostic(
        findings, diagnostic, document, supplied, parameters, locate,
      )
  }
}

///|
fn check_program_diagnostic(
  findings : Array[CheckFinding],
  diagnostic : @program_check.CheckDiagnostic,
  document : String,
  supplied : @decode.Cursor?,
  parameters : String?,
  locate : (String?) -> Unit,
) -> CheckStop {
  let mut original_pointer = None
  if @program_check.diagnostic_origin(diagnostic) is Some(ProgramDocument) &&
    @program_check.diagnostic_location(diagnostic) is Some(location) &&
    @program_check.diagnostic_location_path(location) is Some(path) {
    original_pointer = check_program_original_pointer(document, path)
  }
  match @program_check.diagnostic_category(diagnostic) {
    InvalidInput => {
      locate(original_pointer)
      let cause = @program_check.diagnostic_cause(diagnostic)
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
        Program(_) => Some("invalid_structure")
        _ => None
      }
      if cause is Source(Declarations(Declarations(issue))) &&
        client_program_input("json", Some(document)) is Ok((_, Some(body))) &&
        @decode.open_object(body) is Ok(object) &&
        @decode.lookup(object, "params") is Some(params) {
        let location = @program_check.diagnostic_location(diagnostic)
        if location is Some(location) &&
          @program_check.diagnostic_location_path(location) is Some(path) &&
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
            Some(
              "/params/" +
              declaration.name
              .replace_all(old="~", new="~0")
              .replace_all(old="/", new="~1"),
            ),
          ),
        )
        return Report
      }
      findings.push(
        if structure is Some(issue) {
          ProgramStructureViolation(issue)
        } else {
          check_program_finding(diagnostic, None, supplied, parameters, None)
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
) -> String? {
  guard path.length() <= 65 &&
    client_program_input("json", Some(document)) is Ok((_, Some(root))) else {
    return None
  }
  for length = path.length(); length >= 0; length = length - 1 {
    let parent = path[:length].to_owned()
    if check_original_pointer(document, root, parent) is Some(pointer) {
      return Some(pointer)
    }
  }
  None
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
