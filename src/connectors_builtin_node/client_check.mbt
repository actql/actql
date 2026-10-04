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
  TypeViolation(String, String, String, String?)
  SuppliedViolation(String?)
  ConstraintViolation(String, String, String?)
  UndeclaredParameter(String, (Int, Int)?)
  RequiredValue(String, String)
  // An obligation that cannot be discharged from disclosable evidence.
  Unresolved(String)
  // An allowed construct or budget the checker could not close.
  Limit(String)
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
) -> String {
  let findings : Array[CheckFinding] = []
  let stop = check_source_findings(
    findings, document, format, environment, visible_publication, declarations, parameters,
  )
  check_outcome_json(findings, stop, context_ref, {
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
        Err(Budget) => {
          findings.push(Limit("analysis_budget_exhausted"))
          // Declarations are unavailable, but syntax is independent of them.
          // Reuse the frontend's bounded parser without inventing a context
          // or attempting name resolution against unadmitted declarations.
          match @source_frontend.parse_query(document, selected) {
            Ok(_) => ()
            Err(QuerySyntax({ issue: Limit(_), .. })) => ()
            Err(QuerySyntax(diagnostic)) =>
              findings.push(check_syntax_finding(diagnostic))
            Err(WrongQueryForm) =>
              findings.push(Violation("query_syntax_invalid"))
            Err(_) => return Failed("check_internal")
          }
          return Report
        }
        Err(Invalid) => {
          findings.push(Violation("parameter_declarations_invalid"))
          return Report
        }
        Err(Internal) => return Failed("check_internal")
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
    Err(SuppliedSyntax({ issue, .. })) => {
      findings.push(
        if check_parse_budget(issue) {
          Limit("analysis_budget_exhausted")
        } else {
          Violation("supplied_parameters_invalid")
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
  if supplied_admitted {
    match context.parameter_declarations {
      Some(declared) =>
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
                findings.push(RequiredValue(declaration.name, expected))
              }
            }
          }
          Ok(Ready(_)) => ()
          Err(issue) =>
            match check_binding_fault(issue) {
              Budget => findings.push(Limit("analysis_budget_exhausted"))
              Invalid =>
                findings.push(
                  check_supplied_type_finding(issue, declared, supplied),
                )
              Internal => return Failed("check_internal")
            }
        }
      None => ()
    }
  }
  let lowered = match
    @source_frontend.lower(document, selected, Some(context)) {
    Ok(value) => value
    Err(issue) => {
      match issue {
        QuerySyntax({ issue: Limit(_), .. }) =>
          findings.push(Limit("analysis_budget_exhausted"))
        QuerySyntax(diagnostic) =>
          findings.push(check_syntax_finding(diagnostic))
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
        QueryLowering(
          Expression(
            {
              issue: UnknownReference
              | UnsupportedFunction
              | InvalidArguments
              | InvalidNumber,
              ..
            }
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
      | TypeViolation(_, _, _, _)
      | SuppliedViolation(_)
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
          } else {
            findings.push(Violation("program_invalid"))
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
fn check_parse_budget(issue : @source.ParseIssue) -> Bool {
  issue is (InputLimit | NodeLimit | DepthLimit)
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
/// Admit the caller's declaration document with the limits of source
/// preparation, keeping budget and violation apart.
fn check_declarations(
  body : String,
) -> Result[@parameter_binding.Declarations, CheckInputFault] {
  let node = match
    @source.parse_json_bytes(@utf8.encode(body), {
      max_input_bytes: 1048576,
      max_nodes: 16384,
      max_depth: 32,
    }) {
    Ok(node) => node
    Err({ issue, .. }) =>
      return Err(if check_parse_budget(issue) { Budget } else { Invalid })
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes: 16384,
      max_depth: 32,
      max_string_bytes: 65536,
      max_total_string_bytes: 1048576,
    }) {
    Ok(cursor) => cursor
    Err(issue) => return Err(check_decode_fault(issue))
  }
  match
    @parameter_binding.read_declarations(Some(cursor), {
      max_parameters: 1024,
      max_nodes: 8192,
      max_depth: 64,
      max_text_bytes: 65536,
    }) {
    Ok(declared) => Ok(declared)
    Err(issue) => Err(check_binding_fault(issue))
  }
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
      | TypeViolation(_, _, _, _)
      | SuppliedViolation(_)
      | ConstraintViolation(_, _, _)
      | UndeclaredParameter(_, _))
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
) -> Unit raise @encode.EncodeFailure {
  let violations = check_codes(findings, finding => {
    match finding {
      Violation(code) => Some(code)
      SyntaxViolation(_, _) => Some("query_syntax_invalid")
      LexicalViolation(_, _) => Some("query_lexical_invalid")
      ExpressionViolation(_, _) => Some("query_expression_invalid")
      TypeViolation(_, _, _, _) => Some("supplied_value_type_mismatch")
      SuppliedViolation(_) => Some("supplied_value_invalid")
      ConstraintViolation(_, _, _) =>
        Some("supplied_value_constraint_violation")
      UndeclaredParameter(_, _) => Some("parameter_undeclared")
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
    if code == "supplied_value_type_mismatch" {
      for finding in findings {
        if finding is TypeViolation(name, expected, actual, pointer) {
          @encode.key(writer, "facts")
          @encode.begin_object(writer)
          @encode.key(writer, "actual_type")
          @encode.string_value(writer, actual)
          @encode.key(writer, "expected_type")
          @encode.string_value(writer, expected)
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
  for finding in findings {
    if finding is RequiredValue(name, expected) {
      @encode.begin_object(writer)
      @encode.key(writer, "code")
      @encode.string_value(writer, "parameter_value_required")
      @encode.key(writer, "facts")
      @encode.begin_object(writer)
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
/// The reporting budget is separate from the analysis budget: a report that
/// cannot be bounded becomes Failed without a partial report.
fn check_outcome_json(
  findings : Array[CheckFinding],
  stop : CheckStop,
  context_ref : String,
  documents : CheckDocuments,
) -> String {
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
        )
      }
      Failed(problem) => {
        @encode.key(writer, "outcome")
        @encode.string_value(writer, "failed")
        // A partial report is only ever invalid, never verified or a guess.
        if check_verdict(findings) == "invalid" {
          @encode.key(writer, "partial_report")
          write_check_report(
            writer, findings, context_ref, "invalid", documents,
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
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ =>
      "{\"outcome\":\"failed\",\"problem\":{\"code\":\"check_report_unbounded\"},\"reason_schema_cid\":\"" +
      check_reason_schema_cid +
      "\",\"version\":\"" +
      check_outcome_version +
      "\"}"
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
      let range = match diagnostic.origin {
        Some(origin) if @source_origin.kind(origin) == @source_origin.Authored =>
          Some(
            (
              @source_origin.start(origin).byte_offset,
              @source_origin.end(origin).byte_offset,
            ),
          )
        _ => None
      }
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
) -> CheckFinding {
  let path = match issue {
    BindingInput(Supplied, Value(ValueIssue(_, path~, ..))) => path
    BindingInput(Supplied, Value(Decode({ path, .. })))
    | BindingInput(Supplied, Decode({ path, .. })) => path
    BindingInput(Supplied, ParameterIssue(_, path~, ..)) => path
    _ => return Violation("supplied_value_invalid")
  }
  let pointer = if supplied is Some(cursor) &&
    check_supplied_cursor(cursor, path) is Some(_) {
    check_supplied_pointer(path)
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
  let mut value = root
  let mut source = None
  for index in 0..<@parameter_binding.declaration_count(declarations) {
    let declaration = @parameter_binding.declaration_at(declarations, index).unwrap()
    if declaration.name == name {
      source = Some(@parameter_binding.declaration_source(declaration))
      break
    }
  }
  guard source is Some(root_source) else { return fallback }
  let mut source = root_source
  for index in 1..<path.length() {
    guard @decode.open_object(source) is Ok(type_object) else {
      return fallback
    }
    match path[index] {
      @source.Key(key) => {
        guard @decode.lookup(type_object, "fields") is Some(fields) &&
          @decode.open_object(fields) is Ok(fields) &&
          @decode.lookup(fields, key) is Some(child_type) &&
          @decode.open_object(value) is Ok(object) &&
          @decode.lookup(object, key) is Some(child) else {
          return fallback
        }
        source = child_type
        value = child
      }
      @source.Index(at) => {
        guard @decode.lookup(type_object, "items") is Some(child_type) &&
          @decode.elements(value) is Ok(elements) &&
          elements.get(at) is Some(child) else {
          return fallback
        }
        source = child_type
        value = child
      }
    }
  }
  guard check_type_name(source) is Some(expected) else { return fallback }
  let actual = match @decode.view(value) {
    NullValue => "null"
    BoolValue(_) => "boolean"
    NumberValue(_) => "number"
    TextValue(_) => "string"
    ArrayValue(_) => "array"
    ObjectValue(_) => "object"
  }
  TypeViolation(name, expected, actual, pointer)
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
