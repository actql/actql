///|
/// Stable caller decisions, independent of preparation phases and source domains.
/// UnclassifiedFailure makes no claim that the author or configuration is wrong.
pub(all) enum DiagnosticCategory {
  InvalidInput
  InvalidConfiguration
  UnsupportedImplementation
  CompileLimit
  MissingInput
  UnclassifiedFailure
} derive(Eq, Debug)

///|
/// Classification never changes the outcome, detailed cause or source location.
/// MissingInput is assigned only by the existing typed request admission path.
pub fn diagnostic_category(value : CheckDiagnostic) -> DiagnosticCategory {
  value.category
}

///|
fn decode_diagnostic_category(kind : @decode.IssueKind) -> DiagnosticCategory {
  match kind {
    InvalidLimits => InvalidConfiguration
    BudgetExceeded => CompileLimit
    MissingField
    | WrongType
    | UnexpectedNull
    | UnknownField
    | DuplicateField
    | OutOfRange
    | InvalidDecimal
    | InvalidUnicode => InvalidInput
  }
}

///|
fn parse_diagnostic_category(issue : @source.ParseIssue) -> DiagnosticCategory {
  match issue {
    InvalidLimits => InvalidConfiguration
    InputLimit | NodeLimit | DepthLimit => CompileLimit
    _ => InvalidInput
  }
}

///|
fn parameter_diagnostic_category(
  issue : @parameters.Issue,
) -> DiagnosticCategory {
  match issue {
    BindingInput(_, nested) => parameter_diagnostic_category(nested)
    InvalidLimits | Contract(InvalidLimits) => InvalidConfiguration
    Decode(error) | Contract(Decode(error)) | Value(Decode(error)) =>
      decode_diagnostic_category(error.kind)
    ParameterIssue(InvalidLimits, ..) | Value(ValueIssue(InvalidLimits, ..)) =>
      InvalidConfiguration
    ParameterIssue(BudgetExceeded | ParameterLimit, ..)
    | Contract(ContractIssue(BudgetExceeded, ..))
    | Value(ValueIssue(BudgetExceeded, ..)) => CompileLimit
    _ => InvalidInput
  }
}

///|
fn classify_diagnostic_cause(
  cause : LocalConstructionFailure,
) -> DiagnosticCategory {
  if diagnostic_pipeline_cause(cause) is Some(issue) {
    return match issue.kind {
      InvalidLimits => InvalidConfiguration
      BudgetExceeded => CompileLimit
      UnsupportedOperation(_) => UnsupportedImplementation
      Operation(kind) => relation_diagnostic_category(kind)
      Window(InvalidLimits) | Values(InvalidLimits) => InvalidConfiguration
      Window(BudgetExceeded) | Values(BudgetExceeded) => CompileLimit
      Window(_) => InvalidInput
      Values(Decode(kind)) => decode_diagnostic_category(kind)
      Values(Contract(BudgetExceeded) | Value(BudgetExceeded)) => CompileLimit
      Values(Value(InvalidLimits)) => InvalidConfiguration
      Values(_) => InvalidInput
      TimeSeries(InvalidLimits | Temporal(InvalidLimits))
      | Calendar(Options(InvalidLimits))
      | Projection(InvalidLimits)
      | Graph(InvalidLimits | ContractMismatch(InvalidLimits))
      | Vector(InvalidLimits)
      | Event(InvalidLimits | Temporal(InvalidLimits))
      | Join(InvalidLimits)
      | Append(InvalidLimits)
      | Nest(InvalidLimits)
      | Set(InvalidLimits | Schema(InvalidLimits))
      | KeyEvidence(InvalidLimits) => InvalidConfiguration
      TimeSeries(BudgetExceeded | Temporal(BudgetExceeded))
      | Calendar(BudgetExceeded | Options(BudgetExceeded))
      | Projection(BudgetExceeded)
      | Graph(BudgetExceeded | ContractMismatch(BudgetExceeded))
      | Vector(BudgetExceeded)
      | Event(BudgetExceeded | Temporal(BudgetExceeded))
      | Join(BudgetExceeded)
      | Append(BudgetExceeded)
      | Nest(BudgetExceeded)
      | Set(BudgetExceeded | Schema(BudgetExceeded))
      | KeyEvidence(LimitExceeded) => CompileLimit
      TimeSeries(Decode(kind))
      | Calendar(Options(Decode(kind)))
      | Graph(Decode(kind))
      | Vector(Decode(kind))
      | Event(Decode(kind))
      | KeyEvidence(Decode(kind)) => decode_diagnostic_category(kind)
      // An unprojected composite or ownership failure must not blame the author.
      GraphMatch(_)
      | KeyEvidence(InputContractMismatch)
      | Vector(RankingInputMismatch)
      | Calendar(MissingProfile) => UnclassifiedFailure
      _ => InvalidInput
    }
  }
  if diagnostic_result_cause(cause) is Some(issue) {
    return match issue.kind {
      InvalidLimits => InvalidConfiguration
      BudgetExceeded => CompileLimit
      Decode(kind) => decode_diagnostic_category(kind)
      _ => InvalidInput
    }
  }
  match cause {
    InvalidLimits => InvalidConfiguration
    Program(issue) =>
      match issue {
        InvalidLimits => InvalidConfiguration
        Parse(error) => parse_diagnostic_category(error.issue)
        Alternatives(json~, yaml~) => {
          let a = parse_diagnostic_category(json.issue)
          let b = parse_diagnostic_category(yaml.issue)
          // Auto-format cannot establish invalid input if one alternative was
          // stopped by a limit. Keep both original alternative locations.
          if a == InvalidConfiguration || b == InvalidConfiguration {
            InvalidConfiguration
          } else if a == CompileLimit || b == CompileLimit {
            CompileLimit
          } else {
            InvalidInput
          }
        }
        Decode(error) => decode_diagnostic_category(error.kind)
        RetentionLimit(_, ..) => CompileLimit
        Structure(StageLimit, ..) => CompileLimit
        Structure(_, ..) => InvalidInput
      }
    CapacityInputs(InvalidLimits) => InvalidConfiguration
    CapacityInputs(BudgetExceeded) => CompileLimit
    CapacityInputs(_) => InvalidConfiguration
    Environment(issue) => environment_diagnostic_category(issue)
    Source(issue) => source_diagnostic_category(issue)
    Closure(issue) => closure_diagnostic_category(issue)
    Units(BudgetExceeded | Encoding(OutputLimit)) => CompileLimit
    Units(UnsupportedReceipt | UnsupportedStaticPath(_)) =>
      UnsupportedImplementation
    Units(_) => UnclassifiedFailure
  }
}

///|
fn relation_diagnostic_category(
  kind : @relation.IssueKind,
) -> DiagnosticCategory {
  match kind {
    InvalidLimits | Expression(InvalidLimits) => InvalidConfiguration
    BudgetExceeded | Expression(BudgetExceeded) => CompileLimit
    Syntax(issue) =>
      match issue.kind {
        InvalidLimits => InvalidConfiguration
        BudgetExceeded => CompileLimit
        Decode(kind) => decode_diagnostic_category(kind)
        Text(InvalidLimits) => InvalidConfiguration
        Text(CapacityExceeded | Lexical(ByteLimit | TokenLimit)) => CompileLimit
        Text(Lexical(InvalidLimits)) => InvalidConfiguration
        Text(TreeAdmission(kind)) => decode_diagnostic_category(kind)
        _ => InvalidInput
      }
    FillValue(Decode(error)) => decode_diagnostic_category(error.kind)
    FillValue(ValueIssue(InvalidLimits, ..)) => InvalidConfiguration
    FillValue(ValueIssue(BudgetExceeded, ..)) => CompileLimit
    Temporal(_) => UnclassifiedFailure
    _ => InvalidInput
  }
}

///|
fn environment_diagnostic_category(
  issue : EnvironmentFailure,
) -> DiagnosticCategory {
  match issue {
    BudgetExceeded
    | Registry(BudgetExceeded)
    | Catalog(BudgetExceeded)
    | Catalog(Contract(BudgetExceeded))
    | Policies(WorkLimit | PolicyLimit)
    | Values(EnvelopeLimit) => CompileLimit
    References(error) =>
      match error.kind {
        WorkLimit | ReferenceLimit => CompileLimit
        Resolution(BudgetExceeded | Contract(BudgetExceeded)) => CompileLimit
        _ => InvalidConfiguration
      }
    Shapes(error) =>
      match error.kind {
        WorkLimit | ViewLimit => CompileLimit
        _ => InvalidConfiguration
      }
    Modes(error) =>
      match error.kind {
        WorkLimit => CompileLimit
        _ => InvalidConfiguration
      }
    Carriers(error) =>
      match error.kind {
        WorkLimit | SchemaLimit | BudgetExceeded => CompileLimit
        _ => InvalidConfiguration
      }
    Requests(error) =>
      match error.kind {
        WorkLimit | RoleLimit => CompileLimit
        UnsupportedResponseCarrier => UnsupportedImplementation
        _ => InvalidConfiguration
      }
    Registry(_) | Catalog(_) | Policies(_) | Values(_) => InvalidConfiguration
  }
}

///|
fn source_diagnostic_category(issue : SourceFailure) -> DiagnosticCategory {
  match issue {
    UnsupportedBindings(_) | UnsupportedEffects(_) => UnsupportedImplementation
    DeclarationWorkLimit | CapacityMetadataBudget => CompileLimit
    Registration(Declarations(WorkLimit | OrderLimit))
    | Registration(Registration(WorkLimit))
    | Registration(LocalInputs(BudgetExceeded)) => CompileLimit
    Declarations(Declarations(error)) => parameter_diagnostic_category(error)
    SourceView(Binding(Binding(error))) => parameter_diagnostic_category(error)
    Requests(InvalidLimits)
    | Checks(InvalidLimits)
    | Identity(InvalidLimits)
    | Registration(InvalidLimits)
    | SourceView(InvalidLimits) => InvalidConfiguration
    Requests(BudgetExceeded)
    | Checks(BudgetExceeded)
    | Identity(BudgetExceeded)
    | Identity(
      Bindings(BudgetExceeded)
      | References(BudgetExceeded)
      | Sources(BudgetExceeded)
    )
    | Requests(
      Requests(BudgetExceeded)
      | Rows(BudgetExceeded)
      | Policy(BudgetExceeded)
      | Capacity(BudgetExceeded)
      | Producers(BudgetExceeded)
    )
    | SourceView(Binding(BudgetExceeded))
    | SourceView(Program(BudgetExceeded))
    | SourceView(Binding(Operations(WorkLimit)))
    | SourceView(Program(Program(BudgetExceeded)))
    | SourceView(Context(BudgetExceeded))
    | SourceView(Context(Stages(BudgetExceeded)))
    | SourceView(Context(Stages(RowCapacity(BudgetExceeded))))
    | SourceView(Context(Stages(Values(_, BudgetExceeded))))
    | SourceView(Context(Inputs(BudgetExceeded)))
    | SourceView(Context(Selection(BudgetExceeded))) => CompileLimit
    SourceView(Program(Program(UnsupportedReceipt(_, _))))
    | Checks(
      OperationProfiles(UnsupportedProfile(_, _, _, _))
      | ExpressionProfiles(UnsupportedProfile(_, _))
      | Patterns(UnsupportedPattern(_, _))
      | TextBounds(UnsupportedOperation(_, _))
    ) => UnsupportedImplementation
    Checks(
      OperationProfiles(BudgetExceeded)
      | Assembly(BudgetExceeded)
      | Validation(BudgetExceeded)
      | ExpressionProfiles(BudgetExceeded)
      | Patterns(BudgetExceeded)
      | TextBounds(BudgetExceeded)
    ) => CompileLimit
    Checks(
      OperationProfiles(InvalidLimits)
      | Assembly(InvalidLimits)
      | Validation(InvalidLimits)
      | ExpressionProfiles(InvalidLimits)
      | Patterns(InvalidLimits)
      | TextBounds(InvalidLimits)
    ) => InvalidConfiguration
    Identity(Identity(BudgetExceeded | Hash(_, OutputLimit))) => CompileLimit
    SourceView(Binding(InvalidLimits))
    | SourceView(Program(InvalidLimits))
    | SourceView(Program(Program(InvalidLimits)))
    | SourceView(Context(InvalidLimits))
    | SourceView(Context(Stages(InvalidLimits))) => InvalidConfiguration
    _ => UnclassifiedFailure
  }
}

///|
fn closure_diagnostic_category(
  issue : ConstructionFailure,
) -> DiagnosticCategory {
  match issue {
    Operations(problem) =>
      match problem {
        InvalidLimits => InvalidConfiguration
        Expressions(BudgetExceeded)
        | Inventory(BudgetExceeded)
        | Orders(BudgetExceeded)
        | Scalars(BudgetExceeded)
        | Frames(BudgetExceeded)
        | Fills(BudgetExceeded)
        | Ranges(BudgetExceeded)
        | Queries(BudgetExceeded)
        | Cells(BudgetExceeded)
        | Lexical(BudgetExceeded)
        | Calendar(BudgetExceeded)
        | Profiles(BudgetExceeded)
        | Index(BudgetExceeded) => CompileLimit
        Scalars(InvalidValue(_, _)) => InvalidInput
        _ => UnclassifiedFailure
      }
    InvalidLimits => InvalidConfiguration
    BudgetExceeded
    | Values(BudgetExceeded)
    | Joins(BudgetExceeded)
    | IntervalSearch(BudgetExceeded)
    | AsOfSearch(BudgetExceeded)
    | WindowLimits(BudgetExceeded)
    | GroupLimits(BudgetExceeded)
    | NestValues(BudgetExceeded)
    | GroupStringLimits(BudgetExceeded)
    | NumericSlots(BudgetExceeded)
    | Incoming(BudgetExceeded)
    | Links(BudgetExceeded)
    | Requirements(BudgetExceeded)
    | Gates(BudgetExceeded)
    | Contracts(BudgetExceeded) => CompileLimit
    Values(InvalidLimits)
    | Joins(InvalidLimits)
    | IntervalSearch(InvalidLimits)
    | AsOfSearch(InvalidLimits)
    | WindowLimits(InvalidLimits)
    | GroupLimits(InvalidLimits)
    | NestValues(InvalidLimits)
    | GroupStringLimits(InvalidLimits)
    | NumericSlots(InvalidLimits)
    | Incoming(InvalidLimits)
    | Links(InvalidLimits)
    | Requirements(InvalidLimits)
    | Gates(InvalidLimits)
    | Contracts(InvalidLimits) => InvalidConfiguration
    // An unclosed static obligation is not proof that the language rejects it
    // or that an external input could resolve it.
    _ => UnclassifiedFailure
  }
}
