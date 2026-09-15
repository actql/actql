///|
pub(all) enum Format {
  Auto
  Json
  Yaml
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  source : @source.ParseLimits
  tree : @wire.Limits
  max_stages : Int
} derive(Eq, Debug)

///|
pub(all) enum StructuralIssue {
  WrongVersion
  EmptyName
  EmptyDeclarations
  ReservedMetadataKey(String)
  EmptyStages
  StageLimit
  DuplicateStage(String)
  InitialAfter
  InvalidAfter
  UnknownProducer(String)
  UnknownResult(String)
  UnknownEffect(String)
  UnknownInput(String)
} derive(Eq, Debug)

///|
pub(all) enum SyntaxError {
  InvalidLimits
  Parse(@source.ParseError)
  Alternatives(json~ : @source.ParseError, yaml~ : @source.ParseError)
  Decode(@wire.Issue)
  RetentionLimit(RetentionLimit, source_path~ : String)
  Structure(
    StructuralIssue,
    path~ : Array[@source.PathSegment],
    span~ : @source.Span
  )
} derive(Eq, Debug)

///|
priv suberror Abort {
  Abort(SyntaxError)
}

///|
fn[T] invalid(cursor : @wire.Cursor, issue : StructuralIssue) -> T raise Abort {
  raise Abort(
    Structure(
      issue,
      path=@wire.cursor_path(cursor),
      span=@wire.cursor_span(cursor),
    ),
  )
}

///|
fn valid_limits(limits : Limits) -> Bool {
  limits.source.max_input_bytes >= 0 &&
  limits.source.max_input_bytes < 2147483647 &&
  limits.source.max_nodes >= 0 &&
  limits.source.max_depth >= 0 &&
  limits.tree.max_nodes >= 0 &&
  limits.tree.max_depth >= 0 &&
  limits.tree.max_string_bytes >= 0 &&
  limits.tree.max_total_string_bytes >= 0 &&
  limits.max_stages >= 0
}

///|
/// Only lexical/grammar failure permits trying the other source syntax.
fn retry_yaml(issue : @source.ParseIssue) -> Bool {
  match issue {
    UnexpectedEnd
    | UnexpectedToken
    | InvalidString
    | InvalidEscape
    | InvalidNumber
    | ExpectedColon
    | ExpectedArraySeparator
    | ExpectedObjectSeparator
    | TrailingContent => true
    _ => false
  }
}

///|
fn read_source(
  read : (Format) -> Result[@source.ParsedSource, @source.ParseError],
  format : Format,
) -> Result[@source.ParsedSource, SyntaxError] {
  if format != Auto {
    return read(format).map_err(error => Parse(error))
  }
  match read(Json) {
    Ok(node) => Ok(node)
    Err(json) => {
      if !retry_yaml(json.issue) {
        return Err(Parse(json))
      }
      match read(Yaml) {
        Ok(node) => Ok(node)
        Err(yaml) =>
          match yaml.issue {
            InvalidLimits
            | InputLimit
            | NodeLimit
            | DepthLimit
            | InvalidUtf8
            | InvalidUtf16 => Err(Parse(yaml))
            _ => Err(Alternatives(json~, yaml~))
          }
      }
    }
  }
}

///|
fn admit_program(
  parsed : @source.ParsedSource,
  limits : Limits,
) -> Result[Program, SyntaxError] {
  let root = match @wire.admit(parsed.node, limits.tree) {
    Ok(root) => root
    Err(issue) => return Err(Decode(issue))
  }
  Ok(decode(root, limits.max_stages, parsed.usage)) catch {
    Abort(error) => Err(error)
  }
}

///|
/// Parse authored source and validate its stage envelope, not operation semantics.
/// Auto tries YAML only after JSON syntax failure, never after structural rejection.
pub fn parse(
  source : String,
  limits : Limits,
  format? : Format = Auto,
  source_path? : String = "<memory>",
) -> Result[Program, SyntaxError] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let node = read_source(
    format => {
      if format == Yaml {
        @source.parse_yaml_measured(source, limits.source, source_path~)
      } else {
        @source.parse_json_measured(source, limits.source, source_path~)
      }
    },
    format,
  )
  match node {
    Ok(node) => admit_program(node, limits)
    Err(error) => Err(error)
  }
}

///|
/// Byte input uses the same format policy and strict UTF-8 admission.
pub fn parse_bytes(
  source : Bytes,
  limits : Limits,
  format? : Format = Auto,
  source_path? : String = "<memory>",
) -> Result[Program, SyntaxError] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let node = read_source(
    format => {
      if format == Yaml {
        @source.parse_yaml_bytes_measured(source, limits.source, source_path~)
      } else {
        @source.parse_json_bytes_measured(source, limits.source, source_path~)
      }
    },
    format,
  )
  match node {
    Ok(node) => admit_program(node, limits)
    Err(error) => Err(error)
  }
}
