///|
// Preserve detailed typed causes. A missing execution value, profile, resource
// ceiling or unconnected static Owner is never a definitive author error.
fn template_diagnostic_category(
  issue : TemplateConstructionIssue,
) -> DiagnosticCategory {
  match issue {
    BudgetExceeded
    | Capacity(BudgetExceeded | Policy(BudgetExceeded))
    | Semantics(BudgetExceeded | StageHash(_, OutputLimit))
    | Definition(OutputLimit)
    | Profiles(_, BudgetExceeded)
    | Pipeline(_, BudgetExceeded | ExpressionSlots(WorkLimit | SlotLimit))
    | Context(_, BudgetExceeded | Orders(BudgetExceeded))
    | Publication(_, BudgetExceeded)
    | Contracts(BudgetExceeded | Collection(BudgetExceeded)) => CompileLimit
    Capacity(InvalidLimits | InvalidComponent | Policy(_))
    | Semantics(InvalidLimits)
    | Profiles(_, InvalidLimits)
    | Pipeline(_, InvalidLimits | ExpressionSlots(InvalidLimits))
    | Context(_, InvalidLimits)
    | Publication(_, InvalidLimits)
    | Contracts(InvalidLimits) => InvalidConfiguration
    Capacity(MissingCapacity) | Publication(_, MissingHostCeiling(_)) =>
      MissingInput
    Profiles(_, UnsupportedProfile(_, _))
    | Pipeline(
      _,
      UnsupportedOperation(_)
      | PendingExpression(_, _)
      | PendingOperation(_, _, _)
    )
    | Context(_, UnsupportedInputs)
    | Contracts(
      UnsupportedIncoming(_)
      | UnsupportedLocalInputs(_)
      | UnsupportedTableInputs(_)
    ) => UnsupportedImplementation
    Values(_, _, error) => template_values_diagnostic_category(error)
    Orders(_, error) => template_context_diagnostic_category(error)
    Context(_, Context(error)) => template_context_diagnostic_category(error)
    Context(_, Values(BudgetExceeded) | Capacity(WorkLimit)) => CompileLimit
    Context(_, Values(Count(step, error))) =>
      template_values_diagnostic_category(
        @context.ValuesPublicationIssue::Rows(step, error),
      )
    Context(
      _,
      Values(Extension(BudgetExceeded | Arithmetic(ClosureBudgetExceeded)))
    ) => CompileLimit
    Context(_, Values(InvalidLimits) | Capacity(InvalidLimits)) =>
      InvalidConfiguration
    _ => UnclassifiedFailure
  }
}

///|
fn template_values_diagnostic_category(
  issue : @context.ValuesPublicationIssue,
) -> DiagnosticCategory {
  match issue {
    InvalidLimits
    | Recursive(_, InvalidLimits)
    | Rows(_, InvalidLimits)
    | Wire(_, Measurement(InvalidRequirement)) => InvalidConfiguration
    BudgetExceeded
    | Encoding(OutputLimit)
    | Recursive(_, BudgetExceeded | Encoding(OutputLimit))
    | Rows(_, BudgetExceeded | Encoding(OutputLimit))
    | Wire(_, Encoding(OutputLimit) | Measurement(Encoding(OutputLimit))) =>
      CompileLimit
    RowsExceeded(_) | Recursive(_, DepthExceeded | BytesExceeded) =>
      InvalidInput
    Recursive(_, MissingCeiling) | Rows(_, MissingCeiling) => MissingInput
    Wire(_, Measurement(NeedsBinding(_, _)))
    | Recursive(_, Measurement(NeedsBinding(_, _))) => MissingInput
    _ => closure_diagnostic_category(ConstructionFailure::Values(issue))
  }
}

///|
fn template_context_diagnostic_category(
  issue : @context.Issue,
) -> DiagnosticCategory {
  match issue {
    InvalidIntegrationLimits
    | Expressions(Slots(_, InvalidLimits))
    | Capacity(InvalidLimits) => InvalidConfiguration
    PriorOrderLimit
    | Expressions(WorkLimit(_) | Slots(_, WorkLimit | SlotLimit))
    | Capacity(WorkLimit(_) | ProofWorkLimit) => CompileLimit
    Orders(ResultOrder(error)) =>
      match error.kind {
        InvalidLimits => InvalidConfiguration
        BudgetExceeded => CompileLimit
        Decode(kind) => decode_diagnostic_category(kind)
        _ => InvalidInput
      }
    _ => UnclassifiedFailure
  }
}
