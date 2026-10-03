///|
pub(all) enum MatchIssueKind {
  Structure(IssueKind)
  Syntax(@syntax.IssueKind)
  Typing(@typing.IssueKind)
  UnknownField(String)
  UntypedField(String)
  ExpectedBoolean
  Value(@value.IssueKind)
  Decode(@decode.IssueKind)
} derive(Eq, Debug)

///|
pub struct MatchDiagnostic {
  kind : MatchIssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
  range : @text.Range?
}

///|
pub fn match_diagnostic(
  e : MatchIssue,
  _source : @decode.Cursor,
) -> MatchDiagnostic {
  match e {
    MatchStructure(e) =>
      {
        kind: Structure(e.kind),
        path: e.path.copy(),
        span: e.span,
        range: None,
      }
    MatchIdentity(@value.Decode(e)) =>
      { kind: Decode(e.kind), path: e.path.copy(), span: e.span, range: None, }
    MatchIdentity(@value.ValueIssue(kind, path~, span~)) =>
      { kind: Value(kind), path: path.copy(), span, range: None, }
    MatchPredicate(e) =>
      match e {
        SyntaxIssue(e) =>
          {
            kind: Syntax(e.kind),
            path: e.path.copy(),
            span: e.span,
            range: e.range,
          }
        TypingIssue(e) =>
          {
            kind: Typing(e.kind),
            path: @syntax.location_path(e.location),
            span: @syntax.location_span(e.location),
            range: e.location.range,
          }
        UnknownPredicateField(f) | UntypedPredicateField(f) =>
          {
            kind: if e is UnknownPredicateField(_) {
              UnknownField(f.name)
            } else {
              UntypedField(f.name)
            },
            path: @syntax.location_path(f.location),
            span: @syntax.location_span(f.location),
            range: f.location.range,
          }
        PredicateBudget(c) | ExpectedPredicateBoolean(c) =>
          {
            kind: if e is PredicateBudget(_) {
              Structure(BudgetExceeded)
            } else {
              ExpectedBoolean
            },
            path: @decode.cursor_path(c),
            span: @decode.cursor_span(c),
            range: None,
          }
      }
  }
}
