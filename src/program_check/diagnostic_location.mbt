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
  match value.cause {
    InvalidLimits | Program(InvalidLimits) => Some(CheckConfiguration)
    Program(_) => Some(ProgramDocument)
    CapacityInputs(InvalidLimits) => Some(CheckConfiguration)
    CapacityInputs(_) => Some(CapacityEvidence)
    Environment(_) => Some(CheckEnvironment)
    Source(UnsupportedBindings(_) | UnsupportedEffects(_)) =>
      Some(ProgramDocument)
    Source(_) | Closure(_) | Units(_) => None
  }
}

///|
/// Location extraction does not reparse input or allocate a path during
/// rejection. Ambiguous auto-format failures have alternatives, not a primary.
pub fn diagnostic_location(value : CheckDiagnostic) -> DiagnosticLocation? {
  let position = match value.cause {
    Program(Parse(error)) => Parsed(error)
    Program(Decode(error)) => Located(error.path, error.span)
    Program(Structure(_, path~, span~)) => Located(path, span)
    Program(RetentionLimit(_, source_path~)) => Retained(source_path)
    Source(UnsupportedBindings(cursor) | UnsupportedEffects(cursor)) =>
      Cursor(cursor)
    _ => return None
  }
  Some({ position, })
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
    ParameterValue(_) => ProgramDocument
    HostCapacityPolicy => CheckEnvironment
  }
}
