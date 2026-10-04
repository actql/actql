///|
/// Public check of authored source against the Host's audience-visible alias
/// publication. Absent and inaccessible aliases are both left out of that
/// publication by the Host, so checking never sees the difference. This is the
/// one projection that builds `actql-check-outcome/0.1`; private causes,
/// supplied values and Host metadata never reach it.
priv enum CheckFinding {
  // A disclosable proven violation of the caller's own input.
  Violation(String)
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
) -> String {
  let findings : Array[CheckFinding] = []
  let stop = check_source_findings(
    findings, document, format, environment, visible_publication, declarations, parameters,
  )
  check_outcome_json(findings, stop, context_ref)
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
            Err(QuerySyntax(_) | WrongQueryForm) =>
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
  match context.parameter_declarations {
    Some(declared) =>
      match client_program_input("json", parameters) {
        Err(SuppliedSyntax({ issue, .. })) =>
          findings.push(
            if check_parse_budget(issue) {
              Limit("analysis_budget_exhausted")
            } else {
              Violation("supplied_parameters_invalid")
            },
          )
        Err(SuppliedAdmission(issue)) =>
          findings.push(
            if issue.kind is BudgetExceeded {
              Limit("analysis_budget_exhausted")
            } else {
              Violation("supplied_parameters_invalid")
            },
          )
        Err(_) => return Failed("check_internal")
        Ok((_, supplied)) =>
          match
            @parameter_binding.bind(declared, supplied, {
              max_nodes: 8192,
              max_depth: 64,
              max_text_bytes: 65536,
            }) {
            Ok(NeedsBindings(_)) => findings.push(Limit("bound_values_missing"))
            Ok(Ready(_)) => ()
            Err(issue) =>
              match check_binding_fault(issue) {
                Budget => findings.push(Limit("analysis_budget_exhausted"))
                Invalid => findings.push(Violation("supplied_value_invalid"))
                Internal => return Failed("check_internal")
              }
          }
      }
    None => ()
  }
  let lowered = match
    @source_frontend.lower(document, selected, Some(context)) {
    Ok(value) => value
    Err(issue) => {
      match issue {
        QuerySyntax({ issue: Limit(_), .. }) =>
          findings.push(Limit("analysis_budget_exhausted"))
        QuerySyntax(_) | WrongQueryForm =>
          findings.push(Violation("query_syntax_invalid"))
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
          | Expression(_)
        ) => findings.push(Violation("query_invalid"))
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
  if findings.iter().any(finding => finding is Violation(_)) {
    return Report
  }
  let outcome = client_program_prepare_effect_free_with_parameters(
    lowered.document,
    "json",
    environment,
    parameters,
  )
  match outcome {
    Prepared(_) => ()
    Rejected(SuppliedSyntax({ issue, .. })) =>
      findings.push(
        if check_parse_budget(issue) {
          Limit("analysis_budget_exhausted")
        } else {
          Violation("supplied_parameters_invalid")
        },
      )
    Rejected(SuppliedAdmission(issue)) =>
      findings.push(
        if issue.kind is BudgetExceeded {
          Limit("analysis_budget_exhausted")
        } else {
          Violation("supplied_parameters_invalid")
        },
      )
    Rejected(Preparation(NeedsInputs(_))) =>
      findings.push(Limit("bound_values_missing"))
    Rejected(Preparation(EffectNotSupported(_))) =>
      findings.push(Limit("implementation_limit"))
    Rejected(Preparation(Check(diagnostic))) =>
      match @program_check.diagnostic_category(diagnostic) {
        InvalidInput => findings.push(Violation("program_invalid"))
        MissingInput => findings.push(Limit("bound_values_missing"))
        UnsupportedImplementation =>
          findings.push(Limit("implementation_limit"))
        CompileLimit => findings.push(Limit("analysis_budget_exhausted"))
        // The checker makes no claim about the input or configuration.
        UnclassifiedFailure => findings.push(Limit("check_unclassified"))
        InvalidConfiguration => return Failed("check_context_invalid")
      }
    Rejected(Preparation(Binding({ kind: BindingBudgetExceeded, .. }))) =>
      findings.push(Limit("analysis_budget_exhausted"))
    Rejected(Preparation(Binding({ kind: MissingBindings, .. }))) =>
      findings.push(Limit("bound_values_missing"))
    Rejected(
      Preparation(
        Binding(_)
        | Syntax(_)
        | MissingCheckedStage(_)
        | MissingStageIdentity(_)
        | Lowering(_)
        | Graph(_)
      )
      | InvalidFormat
      | SourcePreparation(_)
    ) => return Failed("check_internal")
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
  if findings.iter().any(finding => finding is Violation(_)) {
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
) -> Unit raise @encode.EncodeFailure {
  let violations = check_codes(findings, finding => {
    match finding {
      Violation(code) => Some(code)
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
  @encode.key(writer, "reasons")
  @encode.begin_array(writer)
  for code in violations {
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, code)
    @encode.end_object(writer)
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
        )
      }
      Failed(problem) => {
        @encode.key(writer, "outcome")
        @encode.string_value(writer, "failed")
        // A partial report is only ever invalid, never verified or a guess.
        if check_verdict(findings) == "invalid" {
          @encode.key(writer, "partial_report")
          write_check_report(writer, findings, context_ref, "invalid")
        }
        @encode.key(writer, "problem")
        @encode.begin_object(writer)
        @encode.key(writer, "code")
        @encode.string_value(writer, problem)
        @encode.end_object(writer)
      }
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ =>
      "{\"outcome\":\"failed\",\"problem\":{\"code\":\"check_report_unbounded\"},\"version\":\"" +
      check_outcome_version +
      "\"}"
  }
}
