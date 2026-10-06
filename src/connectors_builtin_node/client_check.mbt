///|
/// Public check of authored source against the Host's audience-visible alias
/// publication. Absent and inaccessible aliases are both left out of that
/// publication by the Host, so checking never sees the difference. This is the
/// one projection that builds `actql-check-outcome/0.1`; private causes,
/// supplied values and Host metadata never reach it.
priv enum CheckFinding {
  // A disclosable proven violation of the caller's own input.
  Violation(String)
  SyntaxViolation(Int, Int)
  LexicalViolation(String, (Int, Int)?)
  ExpressionViolation(String, (Int, Int)?)
  FrameViolation
  ExpressionTypeViolation(String)
  OperationScalarViolation(String, String, (String, String)?)
  GraphViolation(String, String)
  TypeViolation(String, String, String, String?)
  DefaultTypeViolation(String, String, String, String?)
  JsonInputViolation(String, String, String?)
  SuppliedParseViolation(String?)
  SuppliedViolation(String?)
  DeclarationViolation(String?)
  ConstraintViolation(String, String, String?)
  UndeclaredParameter(String, (Int, Int)?)
  UnusedParameter(String, String?)
  RequiredValue(@parameter_binding.Declaration, String)
  // An obligation that cannot be discharged from disclosable evidence.
  Unresolved(String)
  // An allowed construct or budget the checker could not close.
  Limit(String)
  FunctionLimit((Int, Int)?)
}

///|
priv enum CheckStop {
  Report
  Failed(String)
}

///|
let check_outcome_version = "actql-check-outcome/0.1"

///|
/// Check one source document for the public `check` operation. `context_ref`
/// is the Host-issued opaque reference to the audience-bound scope and
/// context; the verdict is never serialized without it.
#export_name("clientProgramCheckSource")
pub fn client_program_check_source(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  declarations : String?,
  parameters : String?,
  context_ref : String,
  source_revision : String,
  declarations_revision : String?,
  parameters_revision : String?,
  correlation_ref : String,
) -> String {
  let findings : Array[CheckFinding] = []
  let stop = check_source_findings(
    findings, document, format, environment, visible_publication, declarations, parameters,
  )
  check_outcome_json(findings, stop, context_ref, correlation_ref, {
    source_revision,
    source_bytes: @utf8.encode(document).length(),
    declarations_revision,
    declarations_bytes: declarations
    .map(body => @utf8.encode(body).length())
    .unwrap_or(0),
    parameters_revision,
    parameters_bytes: parameters
    .map(body => @utf8.encode(body).length())
    .unwrap_or(0),
  })
}

///|
/// The checking context itself is not disclosable to this audience. No
/// verdict, report, scope or context field is serialized.
#export_name("clientProgramCheckUnavailable")
pub fn client_program_check_unavailable(correlation_ref : String) -> String {
  try {
    let writer = @encode.writer(1024, 16, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "correlation_ref")
    @encode.string_value(writer, correlation_ref)
    @encode.key(writer, "outcome")
    @encode.string_value(writer, "unavailable")
    @encode.key(writer, "problem")
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, "check_unavailable")
    @encode.end_object(writer)
    @encode.key(writer, "reason_schema_cid")
    @encode.string_value(writer, check_reason_schema_cid)
    @encode.key(writer, "outcome_schema_cid")
    @encode.string_value(writer, check_outcome_schema_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("CheckUnavailableEncoding")
  }
}

///|
/// The compiler contracts a check applies, for the Host's context binding:
/// the grammar and barrier contract manifests and the compiler version.
#export_name("clientProgramCheckCompilerIdentity")
pub fn client_program_check_compiler_identity() -> String {
  "{\"barrier_contract_manifest_cid\":\"" +
  @check_environment.compiler_barrier_contract_manifest_cid() +
  "\",\"compiler_version\":\"" +
  @check_environment.compiler_version_token() +
  "\",\"grammar_manifest_cid\":\"" +
  @check_environment.compiler_grammar_manifest_cid() +
  "\"}"
}

///|
fn check_source_findings(
  findings : Array[CheckFinding],
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  declarations : String?,
  parameters : String?,
) -> CheckStop {
  let selected = match @source_frontend.select_format(format) {
    Ok(Text) => @source_frontend.Text
    Ok(Sql) => @source_frontend.Sql
    _ => return Failed("check_format_unsupported")
  }
  // The caller's declaration document is admitted here, with the limits of
  // source preparation, so that its budget is told apart from an invalid
  // declaration before the shared context is built.
  match declarations {
    Some(body) =>
      match check_declarations(body) {
        Ok(_) => ()
        Err({ kind: Budget, .. }) => {
          findings.push(Limit("analysis_budget_exhausted"))
          // Declarations are unavailable, but syntax is independent of them.
          // Reuse the frontend's bounded parser without inventing a context
          // or attempting name resolution against unadmitted declarations.
          match @source_frontend.parse_query(document, selected) {
            Ok(_) => ()
            Err(QuerySyntax(diagnostic)) =>
              if check_syntax_budget(diagnostic.issue) {
                ()
              } else {
                findings.push(check_syntax_finding(diagnostic))
              }
            Err(WrongQueryForm) =>
              findings.push(Violation("query_syntax_invalid"))
            Err(_) => return Failed("check_internal")
          }
          return Report
        }
        Err({ kind: Invalid, pointer, finding, }) => {
          if finding is Some(finding) {
            findings.push(finding)
          } else {
            findings.push(DeclarationViolation(pointer))
          }
          return Report
        }
        Err({ kind: Internal, .. }) => return Failed("check_internal")
      }
    None => ()
  }
  let context = client_source_context(
    environment, visible_publication, declarations,
  ) catch {
    // Admitted above with the same limits.
    ClientSourceStop(Declarations) => return Failed("check_internal")
    // Host installation metadata: not the caller's input.
    ClientSourceStop(_) => return Failed("check_context_invalid")
  }
  // Supplied values are bound against the caller's declarations before and
  // independently of relation resolution: an inaccessible source must not
  // hide a definite supplied-value violation. A budget of this check is a
  // limit, never a violation of the caller's input.
  let (supplied, supplied_admitted) = match
    client_program_input("json", parameters) {
    Ok((_, supplied)) => (supplied, true)
    Err(SuppliedSyntax(error)) => {
      let issue = error.issue
      findings.push(
        if check_parse_budget(issue) {
          Limit("analysis_budget_exhausted")
        } else {
          check_json_parse_finding(
            "parameters",
            issue,
            if parameters is Some(body) {
              check_parse_original_pointer(body, error, {
                max_input_bytes: 65536,
                max_nodes: 8192,
                max_depth: 64,
              })
            } else {
              None
            },
          )
        },
      )
      (None, false)
    }
    Err(SuppliedAdmission(issue)) => {
      findings.push(
        if issue.kind is BudgetExceeded {
          Limit("analysis_budget_exhausted")
        } else {
          Violation("supplied_parameters_invalid")
        },
      )
      (None, false)
    }
    Err(_) => return Failed("check_internal")
  }
  let mut explanation_bindings : @parameter_binding.BoundValues? = None
  if supplied_admitted {
    // Omitted declarations admit the binder's empty set; an authored empty
    // declaration map was rejected above and must not be substituted here.
    let declared = match context.parameter_declarations {
      Some(declared) => declared
      None =>
        match
          @parameter_binding.read_declarations(None, {
            max_parameters: 1024,
            max_nodes: 8192,
            max_depth: 64,
            max_text_bytes: 65536,
          }) {
          Ok(declared) => declared
          Err(_) => return Failed("check_internal")
        }
    }
    match
      @parameter_binding.bind(declared, supplied, {
        max_nodes: 8192,
        max_depth: 64,
        max_text_bytes: 65536,
      }) {
      Ok(NeedsBindings(missing)) => {
        findings.push(Limit("bound_values_missing"))
        for index in 0..<@parameter_binding.missing_count(missing) {
          let declaration = @parameter_binding.missing_at(missing, index).unwrap()
          if declaration.name.length() <= 256 &&
            check_declaration_type(declaration) is Some(expected) {
            findings.push(RequiredValue(declaration, expected))
          }
        }
      }
      Ok(Ready(bound)) => explanation_bindings = Some(bound)
      Err(issue) =>
        match check_binding_fault(issue) {
          Budget => findings.push(Limit("analysis_budget_exhausted"))
          Invalid =>
            findings.push(
              check_supplied_type_finding(issue, declared, supplied, parameters),
            )
          Internal => return Failed("check_internal")
        }
    }
  }
  let lowered = match
    @source_frontend.lower(document, selected, Some(context)) {
    Ok(value) => value
    Err(issue) => {
      match issue {
        QuerySyntax(diagnostic) =>
          if check_syntax_budget(diagnostic.issue) {
            findings.push(Limit("analysis_budget_exhausted"))
          } else {
            findings.push(check_syntax_finding(diagnostic))
          }
        WrongQueryForm => findings.push(Violation("query_syntax_invalid"))
        // Absent and inaccessible relations are both missing from the
        // audience-visible publication; neither is a proven violation.
        QueryLowering(UnknownRelation) =>
          findings.push(Unresolved("source_resolution"))
        QueryLowering(
          UnsupportedProjection
          | UnsupportedGrouping
          | UnsupportedAggregate
          | UnsupportedHaving
          | UnsupportedOrdering
          | UnsupportedAnalytic
          | UnsupportedSet
          | UnsupportedJoin
          | UnsupportedCte
          | UnsupportedGraph
          | UnsupportedInfer
          | UnsupportedNearest
          | UnsupportedResult
          | UnsupportedEffect
        ) => findings.push(Limit("implementation_limit"))
        // Resolved against visible relations only: a disclosable fact.
        QueryLowering(
          AmbiguousRelation
          | UnknownColumn
          | AmbiguousColumn
          | DuplicateOutput
        ) => findings.push(Violation("query_invalid"))
        // Expression lowering wraps the same construction owner and its
        // budgets. The wrapper cannot turn its own limit into bad input.
        QueryLowering(
          Expression(
            {
              issue: WorkLimit
              | Construction(
                InputLimit
                | NodeLimit
                | DepthLimit
                | StringLimit
                | OriginLimit
                | OutputLimit
                | Admission({ kind: BudgetExceeded, .. })
              )
              | Admission(
                {
                  kind: BudgetExceeded
                  | Decode(BudgetExceeded)
                  | Text(
                    CapacityExceeded
                    | TreeAdmission(BudgetExceeded)
                    | Lexical(ByteLimit | TokenLimit)
                  ),
                  ..
                }
              ),
              ..
            }
          )
        ) => findings.push(Limit("analysis_budget_exhausted"))
        // Other failures of generated construction/admission and invalid
        // lowering limits belong to the checker, not to the author.
        QueryLowering(
          Expression(
            { issue: InvalidLimits | Construction(_) | Admission(_), .. }
          )
        ) => return Failed("check_internal")
        // This lowerer issue conflates unknown names with unsupported forms.
        // Without a distinct input violation it cannot justify author blame.
        QueryLowering(Expression({ issue: UnsupportedFunction, origin, })) =>
          findings.push(FunctionLimit(check_authored_range(origin)))
        QueryLowering(
          Expression(
            { issue: UnknownReference | InvalidArguments | InvalidNumber, .. }
          )
        ) => findings.push(check_query_finding(issue))
        // Host query context, not the caller's input.
        QueryLowering(InvalidContext) => return Failed("check_context_invalid")
        // A construction budget of this check: undetermined, never invalid.
        QueryLowering(
          Construction(
            InputLimit
            | NodeLimit
            | DepthLimit
            | StringLimit
            | OriginLimit
            | OutputLimit
            | Admission({ kind: BudgetExceeded, .. })
          )
          | Admission(
            Structure(StageLimit, ..)
            | RetentionLimit(_, ..)
            | Decode({ kind: BudgetExceeded, .. })
          )
        ) => findings.push(Limit("analysis_budget_exhausted"))
        // The Program built from accepted source: never blamed on the author.
        QueryLowering(Construction(_) | Admission(_))
        | InvalidFormat
        | MissingQueryContext
        | Encoding => return Failed("check_internal")
      }
      return Report
    }
  }
  if findings
    .iter()
    .any(finding => {
      finding
      is (Violation(_)
      | SyntaxViolation(_, _)
      | LexicalViolation(_, _)
      | ExpressionViolation(_, _)
      | FrameViolation
      | ExpressionTypeViolation(_)
      | OperationScalarViolation(_, _, _)
      | GraphViolation(_, _)
      | TypeViolation(_, _, _, _)
      | DefaultTypeViolation(_, _, _, _)
      | JsonInputViolation(_, _, _)
      | SuppliedParseViolation(_)
      | SuppliedViolation(_)
      | DeclarationViolation(_)
      | ConstraintViolation(_, _, _)
      | UndeclaredParameter(_, _))
    }) {
    return Report
  }
  // Syntax/lowering still contributed independent findings, but an
  // unadmitted supplied map cannot be replaced by absent values to narrow scope.
  if !supplied_admitted {
    return Report
  }
  guard lowered.program is Some(program) else {
    return Failed("check_internal")
  }
  // Use the same admitted checker owner without serializing and reparsing
  // generated JSON. Authored provenance stays owned by the submitted input.
  match
    @program_check.check_parsed(
      program,
      environment,
      supplied,
      client_program_standard_limits().checking,
    ) {
    Checked(_) => ()
    NeedsInputs(_) => findings.push(Limit("bound_values_missing"))
    Rejected(diagnostic) =>
      match @program_check.diagnostic_category(diagnostic) {
        InvalidInput =>
          if @program_check.diagnostic_undeclared_parameter(diagnostic)
            is Some(name) &&
            name.length() <= 256 {
            let range = match @program_check.diagnostic_location(diagnostic) {
              Some(location) =>
                match @program_check.diagnostic_location_position(location) {
                  Source(span) => Some((span.start_byte, span.end_byte))
                  _ => None
                }
              None => None
            }
            findings.push(UndeclaredParameter(name, range))
          } else if check_unused_parameter_finding(
              diagnostic,
              context.parameter_declarations,
            )
            is Some(finding) {
            findings.push(finding)
          } else {
            findings.push(
              check_program_finding(
                diagnostic, explanation_bindings, supplied, parameters, declarations,
              ),
            )
          }
        MissingInput => findings.push(Limit("bound_values_missing"))
        UnsupportedImplementation =>
          findings.push(Limit("implementation_limit"))
        CompileLimit => findings.push(Limit("analysis_budget_exhausted"))
        UnclassifiedFailure => findings.push(Limit("check_unclassified"))
        InvalidConfiguration => return Failed("check_context_invalid")
      }
  }
  Report
}

///|
/// Why one stage did not admit the caller's input.
priv enum CheckInputFault {
  // This check's own budget, not a fact about the input.
  Budget
  // A disclosable violation of the caller's own input.
  Invalid
  // The check itself is misconfigured.
  Internal
}

///|
/// Only closed JSON issue families are public; no member name or input value.
fn check_json_parse_finding(
  document : String,
  issue : @source.ParseIssue,
  pointer : String?,
) -> CheckFinding {
  let kind = match issue {
    InvalidUtf8 | InvalidUtf16 | InvalidUnicodeEscape => Some("invalid_unicode")
    UnexpectedEnd => Some("unexpected_end")
    UnexpectedToken => Some("unexpected_token")
    InvalidString => Some("invalid_string")
    InvalidEscape => Some("invalid_escape")
    InvalidNumber => Some("invalid_number")
    NumberOutOfRange => Some("number_out_of_range")
    NegativeZero => Some("negative_zero")
    ExpectedColon => Some("expected_colon")
    ExpectedArraySeparator => Some("expected_array_separator")
    ExpectedObjectSeparator => Some("expected_object_separator")
    DuplicateKey(_) => Some("duplicate_key")
    TrailingContent => Some("trailing_content")
    _ => None
  }
  match kind {
    Some(kind) => JsonInputViolation(document, kind, pointer)
    None =>
      if document == "parameter_declarations" {
        DeclarationViolation(pointer)
      } else {
        SuppliedParseViolation(pointer)
      }
  }
}

///|
fn check_parse_budget(issue : @source.ParseIssue) -> Bool {
  issue is (InputLimit | NodeLimit | DepthLimit)
}

///|
/// Source admission has its own byte budget, before any token is scanned.
/// Both parser paths use its typed failure, never a syntax message.
fn check_syntax_budget(issue : @query_syntax.Issue) -> Bool {
  issue is (Limit(_) | Source(@source_origin.InputLimit))
}

///|
fn check_decode_fault(issue : @decode.Issue) -> CheckInputFault {
  match issue.kind {
    BudgetExceeded => Budget
    InvalidLimits => Internal
    _ => Invalid
  }
}

///|
fn check_binding_fault(issue : @parameter_binding.Issue) -> CheckInputFault {
  match issue {
    BindingInput(_, issue) => check_binding_fault(issue)
    Decode(issue) | Contract(Decode(issue)) | Value(Decode(issue)) =>
      check_decode_fault(issue)
    Contract(ContractIssue(BudgetExceeded, ..))
    | Value(ValueIssue(BudgetExceeded, ..))
    | ParameterIssue(BudgetExceeded | ParameterLimit, ..) => Budget
    InvalidLimits
    | Contract(InvalidLimits)
    | Value(ValueIssue(InvalidLimits, ..))
    | ParameterIssue(InvalidLimits, ..) => Internal
    Contract(ContractIssue(_, ..))
    | Value(ValueIssue(_, ..))
    | ParameterIssue(_, ..) => Invalid
  }
}

///|
/// Keep admission classification separate from an owned declaration location.
priv struct CheckDeclarationFault {
  kind : CheckInputFault
  pointer : String?
  finding : CheckFinding?
}

///|
/// Admit the caller's declaration document with the limits of source
/// preparation, keeping budget and violation apart.
fn check_declarations(
  body : String,
) -> Result[@parameter_binding.Declarations, CheckDeclarationFault] {
  let node = match
    @source.parse_json_bytes(@utf8.encode(body), {
      max_input_bytes: 1048576,
      max_nodes: 16384,
      max_depth: 32,
    }) {
    Ok(node) => node
    Err(error) => {
      let issue = error.issue
      let pointer = if check_parse_budget(issue) {
        None
      } else {
        check_parse_original_pointer(body, error, {
          max_input_bytes: 1048576,
          max_nodes: 16384,
          max_depth: 32,
        })
      }
      return Err({
        kind: if check_parse_budget(issue) {
          Budget
        } else {
          Invalid
        },
        // The parser owns this original structural path, not a SQL range.
        // A preflight/unknown path stays absent; budgets produce no violation.
        pointer,
        finding: if check_parse_budget(issue) {
          None
        } else {
          Some(
            check_json_parse_finding("parameter_declarations", issue, pointer),
          )
        },
      })
    }
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes: 16384,
      max_depth: 32,
      max_string_bytes: 65536,
      max_total_string_bytes: 1048576,
    }) {
    Ok(cursor) => cursor
    Err(issue) =>
      return Err({
        kind: check_decode_fault(issue),
        pointer: None,
        finding: None,
      })
  }
  match
    @parameter_binding.read_declarations(Some(cursor), {
      max_parameters: 1024,
      max_nodes: 8192,
      max_depth: 64,
      max_text_bytes: 65536,
    }) {
    Ok(declared) => Ok(declared)
    Err(issue) => {
      let kind = check_binding_fault(issue)
      let path = match issue {
        Decode({ path, .. })
        | Contract(Decode({ path, .. }))
        | Value(Decode({ path, .. })) => Some(path)
        Contract(ContractIssue(_, path~, ..))
        | Value(ValueIssue(_, path~, ..))
        | ParameterIssue(_, path~, ..) => Some(path)
        _ => None
      }
      // The declaration reader owns these paths. A missing member or an
      // unadmitted node cannot acquire a location in the submitted document.
      let pointer = if kind is Invalid &&
        path is Some(path) &&
        check_supplied_cursor(cursor, path) is Some(_) {
        check_original_pointer(body, cursor, path)
      } else {
        None
      }
      let finding = if kind is Invalid && path is Some(path) {
        check_default_type_finding(issue, cursor, path, pointer)
      } else {
        None
      }
      Err({ kind, pointer, finding, })
    }
  }
}

///|
/// Project an existing scalar rejection, without rechecking the supplied value.
/// The first admitted binder retains whether this call supplied the value or
/// selected its default. Internal requirement indexes are never input positions.
fn check_operation_scalar_finding(
  diagnostic : @program_check.CheckDiagnostic,
  bindings : @parameter_binding.BoundValues?,
  supplied : @decode.Cursor?,
  parameters : String?,
  declarations : String?,
) -> CheckFinding? {
  guard @program_check.diagnostic_cause(diagnostic)
    is Closure(Operations(Scalars(InvalidValue(_, demand)))) else {
    return None
  }
  let name = match demand {
    SafeInteger(name, ..)
    | Fraction(name)
    | Finite(name)
    | Duration(name)
    | Milliseconds(name, ..)
    | Timestamp(name) => name
  }
  guard name.length() <= 256 else { return None }
  let domain = match demand {
    SafeInteger(_, minimum=1L) => Some("positive_safe_integer")
    SafeInteger(_, minimum=0L) => Some("nonnegative_safe_integer")
    SafeInteger(_, ..) => None
    Fraction(_) => Some("unit_fraction")
    Finite(_) => Some("finite_number")
    Duration(_) => Some("duration")
    Milliseconds(_, signed=false) => Some("positive_milliseconds")
    Milliseconds(_, signed=true) => Some("signed_milliseconds")
    Timestamp(_) => Some("timestamp")
  }
  guard domain is Some(domain) else { return None }
  guard bindings is Some(bound) else { return None }
  let mut original_parameter = None
  for index in 0..<@parameter_binding.bound_value_count(bound) {
    let parameter = @parameter_binding.bound_value_at(bound, index).unwrap()
    if parameter.name == name {
      original_parameter = Some(parameter)
      break
    }
  }
  // A generated or differently scoped name is not a caller-owned parameter.
  guard original_parameter is Some(parameter) else { return None }
  let mut location = None
  match parameter.origin {
    Supplied =>
      if supplied is Some(cursor) &&
        parameters is Some(body) &&
        check_supplied_cursor(cursor, [@source.Key(name)]) is Some(_) &&
        check_original_pointer(body, cursor, [@source.Key(name)])
        is Some(pointer) {
        location = Some(("parameters", pointer))
      }
    Default =>
      if declarations is Some(body) {
        let original = @parameter_binding.bound_declarations(bound)
        for declaration in @parameter_binding.declarations(original) {
          if declaration.name != name {
            continue
          }
          let cursor = @parameter_binding.declaration_source(declaration)
          let path = @decode.cursor_path(cursor)
          if path.length() == 1 &&
            path[0] is @source.Key(key) &&
            key == name &&
            check_supplied_cursor(cursor, [@source.Key("default")]) is Some(_) &&
            check_original_pointer(body, cursor, [@source.Key("default")])
            is Some(relative) &&
            check_supplied_pointer(path) is Some(prefix) {
            location = Some(("parameter_declarations", prefix + relative))
          }
          break
        }
      }
  }
  Some(OperationScalarViolation(name, domain, location))
}

///|
fn check_program_finding(
  diagnostic : @program_check.CheckDiagnostic,
  bindings : @parameter_binding.BoundValues?,
  supplied : @decode.Cursor?,
  parameters : String?,
  declarations : String?,
) -> CheckFinding {
  if check_operation_scalar_finding(
      diagnostic, bindings, supplied, parameters, declarations,
    )
    is Some(finding) {
    return finding
  }
  if @program_check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) &&
    issue.kind is Operation(Expression(TypeMismatch(expected))) &&
    ["number", "boolean", "string"].contains(expected) {
    // These are the checker's closed required-type tags, not formatted messages.
    // The flattened location has no authored/generated kind, so omit SQL bytes.
    return ExpressionTypeViolation(expected)
  }
  if @program_check.diagnostic_cause(diagnostic)
    is Closure(Operations(Frames(InvalidFrame(_)))) {
    // The existing closure Owner proves the bound frame violation. Its
    // requirement index is not an authored span or a public input pointer.
    return FrameViolation
  }
  if @program_check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) &&
    issue.path.length() >= 6 &&
    issue.path[0] is Key("stages") &&
    issue.path[1] is Index(_) &&
    issue.path[2] is Key("steps") &&
    issue.path[3] is Index(_) &&
    issue.path[4] is Key("subgraph") &&
    issue.path[5] is Key("nodes") &&
    issue.kind is (InvalidBody | GraphMatch(Structure(InvalidBody))) {
    // The current Graph owner proves this selector violation. Its generated
    // Program path is not an authored text span and is never published as one.
    return GraphViolation("subgraph", "invalid_node_selector")
  }
  if @program_check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) &&
    issue.kind is Operation(ExpectedBoolean) {
    // The existing Relation checker proves the Boolean predicate requirement.
    // Its span lacks authored/generated origin kind, so no SQL range is guessed.
    return ExpressionViolation("expected_boolean", None)
  }
  if @program_check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) &&
    issue.path.length() == 6 &&
    issue.path[0] is Key("stages") &&
    issue.path[1] is Index(_) &&
    issue.path[2] is Key("steps") &&
    issue.path[3] is Index(_) &&
    issue.path[4] is Key("components") {
    match (issue.kind, issue.path[5]) {
      (Graph(InvalidBody), Key("kind")) =>
        return GraphViolation("components", "invalid_kind")
      (Graph(InvalidCount), Key("max_output_rows")) =>
        return GraphViolation("components", "invalid_output_rows")
      _ => ()
    }
  }
  Violation("program_invalid")
}

///|
/// Usage is decided by the common checker. Lowering copies declarations into
/// generated Program cursors, so locations must come from this call's original
/// admitted declaration owner rather than the rejected copy's Program path.
fn check_unused_parameter_finding(
  diagnostic : @program_check.CheckDiagnostic,
  original : @parameter_binding.Declarations?,
) -> CheckFinding? {
  guard @program_check.diagnostic_cause(diagnostic)
    is Source(Identity(References(Usage(UnusedParameter(rejected))))) &&
    rejected.name.length() <= 256 &&
    original is Some(original) else {
    return None
  }
  for declaration in @parameter_binding.declarations(original) {
    if declaration.name == rejected.name {
      let path = @decode.cursor_path(
        @parameter_binding.declaration_source(declaration),
      )
      // Declaration names are admitted ASCII identifiers. Only the original
      // standalone map's owned member path can acquire a structured location.
      let pointer = if path.length() == 1 &&
        path[0] is Key(name) &&
        name == declaration.name {
        check_supplied_pointer(path)
      } else {
        None
      }
      return Some(UnusedParameter(declaration.name, pointer))
    }
  }
  None
}

///|
/// Public verdict from disclosable evidence only.
fn check_verdict(findings : Array[CheckFinding]) -> String {
  if findings
    .iter()
    .any(finding => {
      finding
      is (Violation(_)
      | SyntaxViolation(_, _)
      | LexicalViolation(_, _)
      | ExpressionViolation(_, _)
      | FrameViolation
      | ExpressionTypeViolation(_)
      | OperationScalarViolation(_, _, _)
      | GraphViolation(_, _)
      | TypeViolation(_, _, _, _)
      | DefaultTypeViolation(_, _, _, _)
      | JsonInputViolation(_, _, _)
      | SuppliedParseViolation(_)
      | SuppliedViolation(_)
      | DeclarationViolation(_)
      | ConstraintViolation(_, _, _)
      | UndeclaredParameter(_, _)
      | UnusedParameter(_, _))
    }) {
    "invalid"
  } else if findings.is_empty() {
    "verified"
  } else {
    "undetermined"
  }
}

///|
fn check_codes(
  findings : Array[CheckFinding],
  select : (CheckFinding) -> String?,
) -> Array[String] {
  let codes : Array[String] = []
  for finding in findings {
    match select(finding) {
      Some(code) => if !codes.contains(code) { codes.push(code) }
      None => ()
    }
  }
  codes.sort()
  codes
}

///|
fn write_check_report(
  writer : @encode.Writer,
  findings : Array[CheckFinding],
  context_ref : String,
  verdict : String,
  documents : CheckDocuments,
  requirement_limit : Int,
) -> Unit raise @encode.EncodeFailure {
  let violations = check_codes(findings, finding => {
    match finding {
      Violation(code) => Some(code)
      SyntaxViolation(_, _) => Some("query_syntax_invalid")
      LexicalViolation(_, _) => Some("query_lexical_invalid")
      ExpressionViolation(_, _) => Some("query_expression_invalid")
      FrameViolation => Some("query_frame_invalid")
      ExpressionTypeViolation(_) => Some("expression_type_mismatch")
      OperationScalarViolation(_, _, _) => Some("operation_parameter_invalid")
      GraphViolation(_, _) => Some("graph_operation_invalid")
      TypeViolation(_, _, _, _) => Some("supplied_value_type_mismatch")
      DefaultTypeViolation(_, _, _, _) =>
        Some("parameter_default_type_mismatch")
      JsonInputViolation(_, _, _) => Some("binding_json_invalid")
      SuppliedParseViolation(_) => Some("supplied_parameters_invalid")
      SuppliedViolation(_) => Some("supplied_value_invalid")
      DeclarationViolation(_) => Some("parameter_declarations_invalid")
      ConstraintViolation(_, _, _) =>
        Some("supplied_value_constraint_violation")
      UndeclaredParameter(_, _) => Some("parameter_undeclared")
      UnusedParameter(_, _) => Some("parameter_unused")
      _ => None
    }
  })
  let unresolved = check_codes(findings, finding => {
    match finding {
      Unresolved(boundary) => Some(boundary)
      _ => None
    }
  })
  let limits = check_codes(findings, finding => {
    match finding {
      Limit(code) => Some(code)
      FunctionLimit(_) => Some("implementation_limit")
      _ => None
    }
  })
  @encode.begin_object(writer)
  @encode.key(writer, "context_ref")
  @encode.string_value(writer, context_ref)
  @encode.key(writer, "coverage")
  @encode.begin_object(writer)
  @encode.key(writer, "limits")
  @encode.begin_array(writer)
  for code in limits {
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, code)
    if code == "implementation_limit" {
      for finding in findings {
        if finding is FunctionLimit(range) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "issue")
          @encode.string_value(writer, "function_lowering_unresolved")
          @encode.end_object(writer)
          if range is Some((start, end)) {
            write_check_text_location(
              writer,
              documents.source_revision,
              start,
              end,
            )
          }
          break
        }
      }
    }
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "unresolved")
  @encode.begin_array(writer)
  for boundary in unresolved {
    @encode.begin_object(writer)
    @encode.key(writer, "boundary")
    @encode.string_value(writer, boundary)
    @encode.key(writer, "reason")
    @encode.string_value(writer, "unresolved_protected")
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.key(writer, "inputs")
  @encode.begin_array(writer)
  write_check_document(
    writer,
    "source",
    documents.source_revision,
    "text",
    documents.source_bytes,
  )
  if documents.declarations_revision is Some(revision) {
    write_check_document(
      writer,
      "parameter_declarations",
      revision,
      "structured",
      documents.declarations_bytes,
    )
  }
  if documents.parameters_revision is Some(revision) {
    write_check_document(
      writer,
      "parameters",
      revision,
      "structured",
      documents.parameters_bytes,
    )
  }
  @encode.end_array(writer)
  let mut required_count = 0
  for finding in findings {
    if finding is RequiredValue(_, _) {
      required_count = required_count + 1
    }
  }
  if required_count > requirement_limit {
    // Only already-public input obligations determine this bounded summary.
    // Never expose an omitted count or replace protected coverage with it.
    @encode.key(writer, "omissions")
    @encode.begin_object(writer)
    @encode.key(writer, "requirements")
    @encode.bool_value(writer, true)
    @encode.end_object(writer)
  }
  @encode.key(writer, "reasons")
  @encode.begin_array(writer)
  for code in violations {
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, code)
    if code == "query_lexical_invalid" {
      for finding in findings {
        if finding is LexicalViolation(issue, range) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "issue")
          @encode.string_value(writer, issue)
          @encode.end_object(writer)
          if range is Some((start, end)) {
            write_check_text_location(
              writer,
              documents.source_revision,
              start,
              end,
            )
            if issue == "unterminated_comment" {
              // The existing lexical issue concerns the original input.
              write_check_comment_fix(writer, documents)
            }
          }
          break
        }
      }
    }
    if code == "query_expression_invalid" {
      for finding in findings {
        if finding is ExpressionViolation(issue, range) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "issue")
          @encode.string_value(writer, issue)
          @encode.end_object(writer)
          if range is Some((start, end)) {
            write_check_text_location(
              writer,
              documents.source_revision,
              start,
              end,
            )
          }
          break
        }
      }
    }
    if code == "query_frame_invalid" {
      @encode.key(writer, "facts")
      @encode.begin_object(writer)
      @encode.key(writer, "issue")
      @encode.string_value(writer, "invalid_bounds")
      @encode.end_object(writer)
    }
    if code == "graph_operation_invalid" {
      for finding in findings {
        if finding is GraphViolation(operation, issue) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "issue")
          @encode.string_value(writer, issue)
          @encode.key(writer, "operation")
          @encode.string_value(writer, operation)
          @encode.end_object(writer)
          // The checker-facing span does not retain authored origin kind
          // or argument precision. Do not publish it as an exact input range.
          break
        }
      }
    }
    if code == "parameter_undeclared" {
      for finding in findings {
        if finding is UndeclaredParameter(name, range) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "parameter")
          @encode.string_value(writer, name)
          @encode.end_object(writer)
          if range is Some((start, end)) {
            write_check_text_location(
              writer,
              documents.source_revision,
              start,
              end,
            )
          }
          break
        }
      }
    }
    if code == "parameter_unused" {
      for finding in findings {
        if finding is UnusedParameter(name, pointer) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "parameter")
          @encode.string_value(writer, name)
          @encode.end_object(writer)
          if documents.declarations_revision is Some(revision) &&
            pointer is Some(pointer) {
            write_check_structured_location(
              writer, "parameter_declarations", revision, pointer,
            )
          }
          break
        }
      }
    }
    if code == "supplied_value_type_mismatch" ||
      code == "parameter_default_type_mismatch" {
      for finding in findings {
        let details = match (code, finding) {
          (
            "supplied_value_type_mismatch",
            TypeViolation(name, expected, actual, pointer),
          ) =>
            Some(
              (
                name,
                expected,
                actual,
                pointer,
                "parameters",
                documents.parameters_revision,
              ),
            )
          (
            "parameter_default_type_mismatch",
            DefaultTypeViolation(name, expected, actual, pointer),
          ) =>
            Some(
              (
                name,
                expected,
                actual,
                pointer,
                "parameter_declarations",
                documents.declarations_revision,
              ),
            )
          _ => None
        }
        if details
          is Some((name, expected, actual, pointer, document_id, revision)) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "actual_type")
          @encode.string_value(writer, actual)
          @encode.key(writer, "expected_type")
          @encode.string_value(writer, expected)
          @encode.key(writer, "parameter")
          @encode.string_value(writer, name)
          @encode.end_object(writer)
          if revision is Some(revision) && pointer is Some(pointer) {
            write_check_structured_location(
              writer, document_id, revision, pointer,
            )
          }
          break
        }
      }
    }
    if code == "binding_json_invalid" {
      for finding in findings {
        if finding is JsonInputViolation(document, issue, pointer) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "document")
          @encode.string_value(writer, document)
          @encode.key(writer, "issue")
          @encode.string_value(writer, issue)
          @encode.end_object(writer)
          let revision = if document == "parameter_declarations" {
            documents.declarations_revision
          } else {
            documents.parameters_revision
          }
          if revision is Some(revision) && pointer is Some(pointer) {
            write_check_structured_location(writer, document, revision, pointer)
          }
          break
        }
      }
    }
    if code == "supplied_parameters_invalid" {
      for finding in findings {
        if finding is SuppliedParseViolation(Some(pointer)) &&
          documents.parameters_revision is Some(revision) {
          write_check_structured_location(
            writer, "parameters", revision, pointer,
          )
          break
        }
      }
    }
    if code == "supplied_value_invalid" {
      for finding in findings {
        if finding is SuppliedViolation(pointer) {
          if documents.parameters_revision is Some(revision) &&
            pointer is Some(pointer) {
            write_check_structured_location(
              writer, "parameters", revision, pointer,
            )
          }
          break
        }
      }
    }
    if code == "parameter_declarations_invalid" {
      for finding in findings {
        if finding is DeclarationViolation(Some(pointer)) &&
          documents.declarations_revision is Some(revision) {
          write_check_structured_location(
            writer, "parameter_declarations", revision, pointer,
          )
          break
        }
      }
    }
    if code == "expression_type_mismatch" {
      for finding in findings {
        if finding is ExpressionTypeViolation(expected) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "expected_type")
          @encode.string_value(writer, expected)
          @encode.end_object(writer)
          break
        }
      }
    }
    if code == "operation_parameter_invalid" {
      for finding in findings {
        if finding is OperationScalarViolation(name, domain, location) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "domain")
          @encode.string_value(writer, domain)
          @encode.key(writer, "parameter")
          @encode.string_value(writer, name)
          @encode.end_object(writer)
          if location is Some((document_id, pointer)) {
            let revision = if document_id == "parameters" {
              documents.parameters_revision
            } else {
              documents.declarations_revision
            }
            if revision is Some(revision) {
              write_check_structured_location(
                writer, document_id, revision, pointer,
              )
            }
          }
          break
        }
      }
    }
    if code == "supplied_value_constraint_violation" {
      for finding in findings {
        if finding is ConstraintViolation(name, constraint, pointer) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "constraint")
          @encode.string_value(writer, constraint)
          @encode.key(writer, "parameter")
          @encode.string_value(writer, name)
          @encode.end_object(writer)
          if documents.parameters_revision is Some(revision) &&
            pointer is Some(pointer) {
            write_check_structured_location(
              writer, "parameters", revision, pointer,
            )
          }
          break
        }
      }
    }
    if code == "query_syntax_invalid" {
      for finding in findings {
        if finding is SyntaxViolation(start, end) {
          write_check_text_location(
            writer,
            documents.source_revision,
            start,
            end,
          )
          break
        }
      }
    }
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "requirements")
  @encode.begin_array(writer)
  let mut written_requirements = 0
  for finding in findings {
    if written_requirements >= requirement_limit {
      continue
    }
    if finding is RequiredValue(declaration, expected) {
      let name = declaration.name
      written_requirements = written_requirements + 1
      @encode.begin_object(writer)
      @encode.key(writer, "code")
      @encode.string_value(writer, "parameter_value_required")
      @encode.key(writer, "facts")
      @encode.begin_object(writer)
      @encode.key(writer, "admission")
      write_check_parameter_admission(writer, declaration.parameter_type)
      @encode.key(writer, "expected_type")
      @encode.string_value(writer, expected)
      @encode.key(writer, "parameter")
      @encode.string_value(writer, name)
      @encode.end_object(writer)
      if documents.declarations_revision is Some(revision) {
        write_check_structured_location(
          writer,
          "parameter_declarations",
          revision,
          "/" + name,
        )
      }
      @encode.end_object(writer)
    }
  }
  @encode.end_array(writer)
  @encode.key(writer, "scope")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "bound_input")
  @encode.end_object(writer)
  @encode.key(writer, "verdict")
  @encode.string_value(writer, verdict)
  @encode.end_object(writer)
}

///|
/// Report enumeration has its own bounded budget. Keep the complete findings
/// for verdict/scope/coverage and retry only encoding a smaller public prefix.
/// At most nine reserved encoding attempts occur; analysis is never repeated.
fn check_outcome_json(
  findings : Array[CheckFinding],
  stop : CheckStop,
  context_ref : String,
  correlation_ref : String,
  documents : CheckDocuments,
) -> String {
  let mut requirement_limit = 128
  for attempt = 0; attempt < 9; attempt = attempt + 1 {
    match
      check_outcome_attempt(
        findings, stop, context_ref, correlation_ref, documents, requirement_limit,
      ) {
      Some(value) => return value
      None => requirement_limit = requirement_limit / 2
    }
  }
  check_failed_json("check_report_unbounded", correlation_ref)
}

///|
fn check_outcome_attempt(
  findings : Array[CheckFinding],
  stop : CheckStop,
  context_ref : String,
  correlation_ref : String,
  documents : CheckDocuments,
  requirement_limit : Int,
) -> String? {
  try {
    let writer = @encode.writer(65536, 4096, 16)
    @encode.begin_object(writer)
    match stop {
      Report => {
        @encode.key(writer, "outcome")
        @encode.string_value(writer, "completed")
        @encode.key(writer, "report")
        write_check_report(
          writer,
          findings,
          context_ref,
          check_verdict(findings),
          documents,
          requirement_limit,
        )
      }
      Failed(problem) => {
        @encode.key(writer, "correlation_ref")
        @encode.string_value(writer, correlation_ref)
        @encode.key(writer, "outcome")
        @encode.string_value(writer, "failed")
        // A partial report is only ever invalid, never verified or a guess.
        if check_verdict(findings) == "invalid" {
          @encode.key(writer, "partial_report")
          write_check_report(
            writer, findings, context_ref, "invalid", documents, requirement_limit,
          )
        }
        @encode.key(writer, "problem")
        @encode.begin_object(writer)
        @encode.key(writer, "code")
        @encode.string_value(writer, problem)
        @encode.end_object(writer)
      }
    }
    @encode.key(writer, "reason_schema_cid")
    @encode.string_value(writer, check_reason_schema_cid)
    @encode.key(writer, "outcome_schema_cid")
    @encode.string_value(writer, check_outcome_schema_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
/// A separately bounded Problem envelope survives report-budget exhaustion.
/// The correlation reference was allocated by the Host for this attempt.
fn check_failed_json(problem : String, correlation_ref : String) -> String {
  try {
    let writer = @encode.writer(1024, 16, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "correlation_ref")
    @encode.string_value(writer, correlation_ref)
    @encode.key(writer, "outcome")
    @encode.string_value(writer, "failed")
    @encode.key(writer, "problem")
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, problem)
    @encode.end_object(writer)
    @encode.key(writer, "reason_schema_cid")
    @encode.string_value(writer, check_reason_schema_cid)
    @encode.key(writer, "outcome_schema_cid")
    @encode.string_value(writer, check_outcome_schema_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("CheckFailedEncoding")
  }
}

///|
priv struct CheckDocuments {
  source_revision : String
  source_bytes : Int
  declarations_revision : String?
  declarations_bytes : Int
  parameters_revision : String?
  parameters_bytes : Int
}

///|
fn write_check_comment_fix(
  writer : @encode.Writer,
  documents : CheckDocuments,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "fixes")
  @encode.begin_array(writer)
  @encode.begin_object(writer)
  @encode.key(writer, "code")
  @encode.string_value(writer, "close_block_comment")
  @encode.key(writer, "applicability")
  @encode.string_value(writer, "requires_review")
  @encode.key(writer, "risk")
  @encode.string_value(writer, "syntax_structure")
  @encode.key(writer, "target")
  @encode.begin_object(writer)
  @encode.key(writer, "document_id")
  @encode.string_value(writer, "source")
  @encode.key(writer, "revision")
  @encode.string_value(writer, documents.source_revision)
  @encode.end_object(writer)
  @encode.key(writer, "edits")
  @encode.begin_array(writer)
  @encode.begin_object(writer)
  @encode.key(writer, "start_byte")
  @encode.number_value(writer, documents.source_bytes.to_double())
  @encode.key(writer, "end_byte")
  @encode.number_value(writer, documents.source_bytes.to_double())
  @encode.key(writer, "replacement")
  @encode.string_value(writer, "*/")
  @encode.end_object(writer)
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.end_array(writer)
}

///|
fn check_syntax_finding(diagnostic : @query_syntax.Diagnostic) -> CheckFinding {
  // Only the parser's typed lexical issue is projected. Syntax(String) remains
  // generic; messages are neither classification evidence nor public facts.
  if diagnostic.issue is Lexical(issue) {
    let code = match issue {
      UnexpectedEnd => "unexpected_end"
      UnexpectedToken => "unexpected_token"
      InvalidEscape => "invalid_escape"
      InvalidScalar => "invalid_scalar"
      EmptyIdentifier => "empty_identifier"
      UnterminatedComment => "unterminated_comment"
      InvalidNumber => "invalid_number"
      InvalidParameter => "invalid_parameter"
    }
    let range = diagnostic.span.map(span => (span.start_byte, span.end_byte))
    return LexicalViolation(code, range)
  }
  match diagnostic.span {
    Some(span) => SyntaxViolation(span.start_byte, span.end_byte)
    None => Violation("query_syntax_invalid")
  }
}

///|
/// Use only the existing lowerer's owned authored range. Unknown/generated
/// origins remain unlocated; no matching or parsing of diagnostic text.
fn check_authored_range(origin : @source_origin.Origin?) -> (Int, Int)? {
  match origin {
    Some(origin) if @source_origin.kind(origin) == @source_origin.Authored =>
      Some(
        (
          @source_origin.start(origin).byte_offset,
          @source_origin.end(origin).byte_offset,
        ),
      )
    _ => None
  }
}

///|
/// Project existing typed expression issues and owned authored origins. No
/// protected Source-resolution issue or generated origin acquires a location.
fn check_query_finding(issue : @source_frontend.Issue) -> CheckFinding {
  if issue is QueryLowering(Expression(diagnostic)) {
    let code = match diagnostic.issue {
      UnknownReference => Some("unknown_reference")
      InvalidArguments => Some("invalid_arguments")
      InvalidNumber => Some("invalid_number")
      _ => None
    }
    if code is Some(code) {
      let range = check_authored_range(diagnostic.origin)
      return ExpressionViolation(code, range)
    }
  }
  Violation("query_invalid")
}

///|
fn write_check_document(
  writer : @encode.Writer,
  document_id : String,
  revision : String,
  kind : String,
  bytes : Int,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "byte_length")
  @encode.number_value(writer, bytes.to_double())
  @encode.key(writer, "document_id")
  @encode.string_value(writer, document_id)
  @encode.key(writer, "kind")
  @encode.string_value(writer, kind)
  @encode.key(writer, "revision")
  @encode.string_value(writer, revision)
  @encode.end_object(writer)
}

///|
fn check_declaration_type(
  declaration : @parameter_binding.Declaration,
) -> String? {
  check_type_name(@parameter_binding.declaration_source(declaration))
}

///|
fn check_type_name(source : @decode.Cursor) -> String? {
  match @decode.open_object(source) {
    Ok(object) =>
      match @decode.lookup(object, "type") {
        Some(cursor) =>
          match @decode.text(cursor) {
            Ok(kind) => Some(kind)
            Err(_) => None
          }
        None => None
      }
    Err(_) => None
  }
}

///|
/// RFC 6901 encoding of an owned input path. Oversized paths are omitted rather
/// than truncated; no source spelling is normalized to construct a location.
fn check_supplied_pointer(path : Array[@decode.PathSegment]) -> String? {
  guard path.length() <= 65 else { return None }
  let mut pointer = ""
  for segment in path {
    let token = match segment {
      @source.Key(name) =>
        name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
      @source.Index(index) => {
        guard index >= 0 else { return None }
        index.to_string()
      }
    }
    guard pointer.length() + token.length() + 1 <= 4096 else { return None }
    pointer += "/" + token
  }
  Some(pointer)
}

///|
/// Canonical parser paths contain admitted keys. Reuse the existing preserving
/// reader solely for original-path material after an authoritative failure.
/// A different failure, budget or unknown path cannot supply a location.
fn check_parse_original_pointer(
  body : String,
  original : @source.ParseError,
  limits : @source.ParseLimits,
) -> String? {
  guard !check_parse_budget(original.issue) && original.path is Some(_) else {
    return None
  }
  match
    @source.parse_json_bytes_preserving(
      @utf8.encode(body),
      limits,
      source_path=original.source_path,
    ) {
    Err(preserved) => {
      guard preserved.issue == original.issue &&
        preserved.location == original.location else {
        return None
      }
      preserved.path.bind(check_supplied_pointer)
    }
    Ok(_) => None
  }
}

///|
/// Binder paths use admitted keys, which may have been normalized by the
/// input reader. Recover each owned key from its retained source span with
/// the existing preserving JSON reader; this explains a proven finding and
/// does not change binding, admission or the caller's original document.
fn check_original_pointer(
  body : String,
  root : @decode.Cursor,
  path : Array[@decode.PathSegment],
) -> String? {
  guard path.length() <= 65 else { return None }
  let bytes = @utf8.encode(body)
  let original : Array[@decode.PathSegment] = []
  let mut cursor = root
  let mut remaining = 65536
  for segment in path {
    match segment {
      @source.Key(key) => {
        guard @decode.open_object(cursor) is Ok(object) &&
          @decode.lookup(object, key) is Some(child) &&
          @decode.cursor_key_span(child) is Some(span) else {
          return None
        }
        guard span.start_byte >= 0 &&
          span.end_byte > span.start_byte &&
          span.end_byte <= bytes.length() &&
          span.end_byte - span.start_byte <= remaining else {
          return None
        }
        remaining -= span.end_byte - span.start_byte
        guard @source.parse_json_bytes_preserving(
            bytes[span.start_byte:span.end_byte].to_owned(),
            { max_input_bytes: 65536, max_nodes: 1, max_depth: 0, },
          )
          is Ok({ value: String(name), .. }) else {
          return None
        }
        original.push(@source.Key(name))
        cursor = child
      }
      @source.Index(index) => {
        guard @decode.element_at(cursor, index) is Some(child) else {
          return None
        }
        original.push(@source.Index(index))
        cursor = child
      }
    }
  }
  check_supplied_pointer(original)
}

///|
/// Missing members have no submitted node to locate. Use only the supplied
/// cursor's existing children; declaration-only paths are not input locations.
fn check_supplied_cursor(
  root : @decode.Cursor,
  path : Array[@decode.PathSegment],
) -> @decode.Cursor? {
  guard path.length() <= 65 else { return None }
  let mut cursor = root
  for segment in path {
    match segment {
      @source.Key(key) => {
        guard @decode.open_object(cursor) is Ok(object) &&
          @decode.lookup(object, key) is Some(child) else {
          return None
        }
        cursor = child
      }
      @source.Index(index) => {
        guard @decode.elements(cursor) is Ok(elements) &&
          elements.get(index) is Some(child) else {
          return None
        }
        cursor = child
      }
    }
  }
  Some(cursor)
}

///|
/// Explain an already proven mismatch using its supplied-input origin and path.
/// Walking admitted declaration/value cursors reads explanation facts only;
/// it does not admit values again or infer a new nested contract.
fn check_supplied_type_finding(
  issue : @parameter_binding.Issue,
  declarations : @parameter_binding.Declarations,
  supplied : @decode.Cursor?,
  parameters : String?,
) -> CheckFinding {
  let path = match issue {
    BindingInput(Supplied, Value(ValueIssue(_, path~, ..))) => path
    BindingInput(Supplied, Value(Decode({ path, .. })))
    | BindingInput(Supplied, Decode({ path, .. })) => path
    BindingInput(Supplied, ParameterIssue(_, path~, ..)) => path
    _ => return Violation("supplied_value_invalid")
  }
  let pointer = if supplied is Some(cursor) &&
    parameters is Some(body) &&
    check_supplied_cursor(cursor, path) is Some(_) {
    check_original_pointer(body, cursor, path)
  } else {
    None
  }
  let fallback = SuppliedViolation(pointer)
  // These are the binder's proven families, not another constraint check.
  // NumericConstraint does not identify which integer/bound condition failed.
  let constraint = match issue {
    BindingInput(Supplied, ParameterIssue(NumericConstraint, ..)) =>
      Some("numeric")
    BindingInput(Supplied, ParameterIssue(DurationConstraint, ..)) =>
      Some("duration")
    BindingInput(Supplied, ParameterIssue(LengthConstraint, ..)) =>
      Some("array_length")
    BindingInput(Supplied, Value(ValueIssue(ArrayConstraint, ..))) =>
      Some("array_size")
    _ => None
  }
  if constraint is Some(constraint) &&
    path.get(0) is Some(@source.Key(name)) &&
    name.length() <= 256 {
    return ConstraintViolation(name, constraint, pointer)
  }
  guard issue
    is (BindingInput(
      Supplied,
      Value(ValueIssue(WrongType | UnexpectedNull, ..))
    )
    | BindingInput(
      Supplied,
      Value(Decode({ kind: WrongType | UnexpectedNull, .. }))
    )) else {
    return fallback
  }
  guard !path.is_empty() &&
    path[0] is @source.Key(name) &&
    name.length() <= 256 &&
    supplied is Some(cursor) &&
    @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, name) is Some(root) else {
    return fallback
  }
  let mut source = None
  for index in 0..<@parameter_binding.declaration_count(declarations) {
    let declaration = @parameter_binding.declaration_at(declarations, index).unwrap()
    if declaration.name == name {
      source = Some(@parameter_binding.declaration_source(declaration))
      break
    }
  }
  guard source is Some(root_source) else { return fallback }
  guard check_type_facts(root_source, root, path, 1) is Some((expected, actual)) else {
    return fallback
  }
  TypeViolation(name, expected, actual, pointer)
}

///|
/// Read explanation facts after the declaration owner has rejected a default.
/// The admitted declaration type precedes default validation; this walk does
/// not validate another value or change declaration admission.
fn check_default_type_finding(
  issue : @parameter_binding.Issue,
  root : @decode.Cursor,
  path : Array[@decode.PathSegment],
  pointer : String?,
) -> CheckFinding? {
  guard issue
    is (Value(ValueIssue(WrongType | UnexpectedNull, ..))
    | Value(Decode({ kind: WrongType | UnexpectedNull, .. }))) &&
    path.length() >= 2 &&
    path[0] is @source.Key(name) &&
    name.length() <= 256 &&
    path[1] is @source.Key("default") &&
    @decode.open_object(root) is Ok(declarations) &&
    @decode.lookup(declarations, name) is Some(source) &&
    @decode.open_object(source) is Ok(declaration) &&
    @decode.lookup(declaration, "default") is Some(value) else {
    return None
  }
  guard check_type_facts(source, value, path, 2) is Some((expected, actual)) else {
    return None
  }
  Some(DefaultTypeViolation(name, expected, actual, pointer))
}

///|
/// Walk only the already owned type/value paths of a proven mismatch.
fn check_type_facts(
  root_source : @decode.Cursor,
  root_value : @decode.Cursor,
  path : Array[@decode.PathSegment],
  offset : Int,
) -> (String, String)? {
  let mut value = root_value
  let mut source = root_source
  for index in offset..<path.length() {
    guard @decode.open_object(source) is Ok(type_object) else { return None }
    match path[index] {
      @source.Key(key) => {
        guard @decode.lookup(type_object, "fields") is Some(fields) &&
          @decode.open_object(fields) is Ok(fields) &&
          @decode.lookup(fields, key) is Some(child_type) &&
          @decode.open_object(value) is Ok(object) &&
          @decode.lookup(object, key) is Some(child) else {
          return None
        }
        source = child_type
        value = child
      }
      @source.Index(at) => {
        guard @decode.lookup(type_object, "items") is Some(child_type) &&
          @decode.elements(value) is Ok(elements) &&
          elements.get(at) is Some(child) else {
          return None
        }
        source = child_type
        value = child
      }
    }
  }
  guard check_type_name(source) is Some(expected) else { return None }
  let actual = match @decode.view(value) {
    NullValue => "null"
    BoolValue(_) => "boolean"
    NumberValue(_) => "number"
    TextValue(_) => "string"
    ArrayValue(_) => "array"
    ObjectValue(_) => "object"
  }
  Some((expected, actual))
}

///|
fn write_check_structured_location(
  writer : @encode.Writer,
  document_id : String,
  revision : String,
  pointer : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "location")
  @encode.begin_object(writer)
  @encode.key(writer, "document_id")
  @encode.string_value(writer, document_id)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "structured")
  @encode.key(writer, "pointer")
  @encode.string_value(writer, pointer)
  @encode.key(writer, "revision")
  @encode.string_value(writer, revision)
  @encode.end_object(writer)
}

///|
fn write_check_text_location(
  writer : @encode.Writer,
  revision : String,
  start : Int,
  end : Int,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "location")
  @encode.begin_object(writer)
  @encode.key(writer, "document_id")
  @encode.string_value(writer, "source")
  @encode.key(writer, "end_byte")
  @encode.number_value(writer, end.to_double())
  @encode.key(writer, "kind")
  @encode.string_value(writer, "text")
  @encode.key(writer, "precision")
  @encode.string_value(writer, "exact")
  @encode.key(writer, "revision")
  @encode.string_value(writer, revision)
  @encode.key(writer, "start_byte")
  @encode.number_value(writer, start.to_double())
  @encode.end_object(writer)
}
