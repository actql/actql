///|
/// An origin is a document domain, not a file name or preparation phase.
pub(all) enum DiagnosticOrigin {
  ProgramDocument
  CheckEnvironment
  SuppliedValues
  CapacityEvidence
  CheckConfiguration
} derive(Eq, Debug)

///|
priv enum DiagnosticPosition {
  Cursor(@decode.Cursor)
  Parsed(@source.ParseError)
  Located(Array[@decode.PathSegment], @source.Span)
  Retained(String)
}

///|
struct DiagnosticLocation {
  position : DiagnosticPosition
}

///|
/// None means no domain projection is available for this cause; the original
/// typed cause is still retained. Domains are never guessed from file labels.
pub fn diagnostic_origin(value : CheckDiagnostic) -> DiagnosticOrigin? {
  if search_request_parts(value.cause) is Some(_) {
    return Some(ProgramDocument)
  }
  if diagnostic_pipeline_issue(value) is Some(issue) {
    return Some(
      if issue.kind == @pipeline.InvalidLimits {
        CheckConfiguration
      } else {
        ProgramDocument
      },
    )
  }
  if diagnostic_result_issue(value) is Some(issue) {
    return Some(
      if issue.kind == @publication.InvalidLimits {
        CheckConfiguration
      } else {
        ProgramDocument
      },
    )
  }
  match value.cause {
    InvalidLimits | Program(InvalidLimits) => Some(CheckConfiguration)
    Program(_) => Some(ProgramDocument)
    CapacityInputs(InvalidLimits) => Some(CheckConfiguration)
    CapacityInputs(_) => Some(CapacityEvidence)
    Environment(_) => Some(CheckEnvironment)
    Source(UnsupportedBindings(_) | UnsupportedEffects(_)) =>
      Some(ProgramDocument)
    Closure(UnresolvedOperation(_)) => Some(ProgramDocument)
    Closure(GroupStringLimits(MissingFiniteBound(_))) => Some(ProgramDocument)
    Source(Requests(Rows(MissingPositiveBound(_, _, _)))) =>
      Some(ProgramDocument)
    Source(Declarations(@stages.Declarations(@parameters.InvalidLimits)))
    | Source(SourceView(Binding(Binding(@parameters.InvalidLimits)))) =>
      Some(CheckConfiguration)
    Source(Declarations(@stages.Declarations(_))) => Some(ProgramDocument)
    Source(SourceView(Binding(Binding(@parameters.BindingInput(origin, _))))) =>
      Some(
        match origin {
          Supplied => SuppliedValues
          Default => ProgramDocument
        },
      )
    Source(_) | Closure(_) | Units(_) => None
  }
}

///|
/// Location extraction does not reparse input or allocate a path during
/// rejection. Ambiguous auto-format failures have alternatives, not a primary.
pub fn diagnostic_location(value : CheckDiagnostic) -> DiagnosticLocation? {
  if search_request_parts(value.cause) is Some((source, _, _)) {
    return Some({ position: Cursor(source), })
  }
  if diagnostic_pipeline_issue(value) is Some(issue) {
    if issue.kind == @pipeline.InvalidLimits {
      return None
    }
    return Some({ position: Located(issue.path, issue.span), })
  }
  if diagnostic_result_issue(value) is Some(issue) {
    if issue.kind == @publication.InvalidLimits {
      return None
    }
    return Some({ position: Located(issue.path, issue.span), })
  }
  let position = match value.cause {
    Program(Parse(error)) => Parsed(error)
    Program(Decode(error)) => Located(error.path, error.span)
    Program(Structure(_, path~, span~)) => Located(path, span)
    Program(RetentionLimit(_, source_path~)) => Retained(source_path)
    Source(UnsupportedBindings(cursor) | UnsupportedEffects(cursor)) =>
      Cursor(cursor)
    Closure(UnresolvedOperation(site)) => {
      guard @pipeline.operation_obligation_source_at(
          site.obligations,
          site.index,
        )
        is Some(source) else {
        return None
      }
      Cursor(source)
    }
    Closure(GroupStringLimits(MissingFiniteBound(source))) => Cursor(source)
    Source(Requests(Rows(MissingPositiveBound(_, _, source)))) => Cursor(source)
    Source(SourceView(Binding(Binding(@parameters.BindingInput(_, issue))))) =>
      match parameter_issue_position(issue) {
        Some(position) => position
        None => return None
      }
    Source(Declarations(@stages.Declarations(issue))) =>
      match parameter_issue_position(issue) {
        Some(position) => position
        None => return None
      }
    _ => return None
  }
  Some({ position, })
}

///|
fn diagnostic_pipeline_issue(value : CheckDiagnostic) -> @pipeline.Issue? {
  diagnostic_pipeline_cause(value.cause)
}

///|
fn diagnostic_pipeline_cause(
  cause : LocalConstructionFailure,
) -> @pipeline.Issue? {
  match cause {
    Source(SourceView(Program(Program(Pipeline(_, issue)))))
    | Source(SourceView(Program(MissingCalendarSelection(_, issue))))
    | Source(SourceView(Program(Program(Order(_, PipelineOrder(issue))))))
    | Source(SourceView(Context(Stages(Guards(_, _, issue))))) => Some(issue)
    _ => None
  }
}

///|
fn diagnostic_result_issue(value : CheckDiagnostic) -> @publication.Issue? {
  diagnostic_result_cause(value.cause)
}

///|
fn diagnostic_result_cause(
  cause : LocalConstructionFailure,
) -> @publication.Issue? {
  match cause {
    Source(SourceView(Program(Program(Results(_, issue)))))
    | Source(SourceView(Program(Program(Order(_, ResultOrder(issue)))))) =>
      Some(issue)
    _ => None
  }
}

///|
/// Range within the original decoded expression, not a document byte span.
/// Absence is retained when the underlying checker has no expression range.
pub fn diagnostic_expression_range(
  value : CheckDiagnostic,
) -> @expression_text.Range? {
  match diagnostic_pipeline_issue(value) {
    Some(issue) =>
      if issue.kind == @pipeline.InvalidLimits {
        None
      } else {
        issue.range
      }
    None => None
  }
}

///|
fn parameter_issue_position(issue : @parameters.Issue) -> DiagnosticPosition? {
  match issue {
    @parameters.Decode(error) => Some(Located(error.path, error.span))
    @parameters.Contract(Decode(error)) => Some(Located(error.path, error.span))
    @parameters.Contract(ContractIssue(_, path~, span~)) =>
      Some(Located(path, span))
    @parameters.Value(Decode(error)) => Some(Located(error.path, error.span))
    @parameters.Value(ValueIssue(_, path~, span~)) => Some(Located(path, span))
    @parameters.ParameterIssue(_, path~, span~) => Some(Located(path, span))
    @parameters.InvalidLimits
    | @parameters.Contract(InvalidLimits)
    | @parameters.BindingInput(_, _) => None
  }
}

///|
pub fn diagnostic_alternative_count(value : CheckDiagnostic) -> Int {
  match value.cause {
    Program(Alternatives(..)) => 2
    _ => 0
  }
}

///|
/// Alternatives retain the parser's JSON-then-YAML ordering and typed errors.
/// Neither alternative is promoted to a successful parse or primary failure.
pub fn diagnostic_alternative_at(
  value : CheckDiagnostic,
  index : Int,
) -> (@syntax.Format, DiagnosticLocation)? {
  guard value.cause is Program(Alternatives(json~, yaml~)) else { return None }
  match index {
    0 => Some((Json, { position: Parsed(json), }))
    1 => Some((Yaml, { position: Parsed(yaml), }))
    _ => None
  }
}

///|
pub fn diagnostic_location_source_path(value : DiagnosticLocation) -> String {
  match value.position {
    Cursor(cursor) => @decode.cursor_span(cursor).source_path
    Parsed(error) => error.source_path
    Located(_, span) => span.source_path
    Retained(path) => path
  }
}

///|
/// Byte and UTF-16 offsets remain distinct. Unavailable is not a zero offset.
pub fn diagnostic_location_position(
  value : DiagnosticLocation,
) -> @source.ParseLocation {
  match value.position {
    Cursor(cursor) => @source.Source(@decode.cursor_span(cursor))
    Parsed(error) => error.location
    Located(_, span) => @source.Source(span)
    Retained(_) => @source.Unavailable
  }
}

///|
/// The returned path is a caller-owned copy. None means unavailable, whereas
/// Some([]) means that the original diagnostic explicitly identifies the root.
pub fn diagnostic_location_path(
  value : DiagnosticLocation,
) -> Array[@decode.PathSegment]? {
  match value.position {
    Cursor(cursor) => Some(@decode.cursor_path(cursor))
    Parsed(error) => error.path.map(path => path.copy())
    Located(path, _) => Some(path.copy())
    Retained(_) => None
  }
}

///|
pub fn input_request_origin(value : InputRequest) -> DiagnosticOrigin {
  match value.kind {
    ParameterValue(_)
    | NumericReductionProfile(_)
    | AggregateStringByteLimit(_) => ProgramDocument
    TemporalSearchInputRows(_, _) => ProgramDocument
    KeyedAcquisitionInputRows(_) => ProgramDocument
    HostCapacityPolicy
    | HostTextTimePolicy
    | HostTextRankSelection
    | TextRankProfileArtifact(_)
    | HostCalendarSelection
    | CalendarProfileArtifact(_) => CheckEnvironment
  }
}

///|
/// A proven undeclared parameter, retained by the existing semantic checker.
/// This is not a missing-value request or a search through rendered messages.
pub fn diagnostic_undeclared_parameter(value : CheckDiagnostic) -> String? {
  match diagnostic_pipeline_issue(value) {
    Some(
      {
        kind: Operation(
          Expression(UnknownParameter(name))
          | UnknownParameter(name)
        ),
        ..
      }
    ) => Some(name)
    _ => None
  }
}
