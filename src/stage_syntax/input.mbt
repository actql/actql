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
  PrefixPublication
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
struct ParsedProgramInput {
  root : @wire.Cursor
  usage : @source.ParseUsage
  max_stages : Int
}

///|
fn admit_program_input(
  parsed : @source.ParsedSource, limits : Limits,
) -> Result[ParsedProgramInput, SyntaxError] {
  match @wire.admit(parsed.node, limits.tree) {
    Ok(root) => Ok({root, usage:parsed.usage, max_stages:limits.max_stages})
    Err(issue) => Err(Decode(issue))
  }
}

///|
fn admit_program(
  parsed : @source.ParsedSource, limits : Limits,
) -> Result[Program, SyntaxError] {
  match admit_program_input(parsed,limits) {
    Ok(original) => finish_program_input(original)
    Err(issue) => Err(issue)
  }
}

///|
/// Parse and index the original source without constructing its Program
/// envelope. This opaque phase result retains the original measured usage and
/// selected stage limit; it cannot replace them with caller-supplied counts.
/// The editable parser tree is not retained by this result. Resource admission
/// belongs to the fixed caller before this constructor, not to this API.
pub fn parse_program_input(
  source : String,
  limits : Limits,
  format? : Format = Auto,
  source_path? : String = "<memory>",
) -> Result[ParsedProgramInput, SyntaxError] {
  if !valid_limits(limits) { return Err(InvalidLimits) }
  let node = read_source(
    format => {
      if format == Yaml {
        @source.parse_program_yaml_measured(source, limits.source, source_path~)
      } else {
        @source.parse_program_json_measured(source, limits.source, source_path~)
      }
    }, format,
  )
  match node {
    Ok(node) => admit_program_input(node,limits)
    Err(error) => Err(error)
  }
}

///|
/// Borrow the exact indexed owner for a bounded preparation shape proof. This
/// does not copy a tree, construct a Program, or grant execution authority.
pub fn program_input_cursor(original : ParsedProgramInput) -> @wire.Cursor {
  original.root
}

///|
/// Continue the same ordinary structural decoder after its fixed caller has
/// admitted the next construction phase. Original stage policy is preserved.
pub fn finish_program_input(original : ParsedProgramInput) -> Result[Program, SyntaxError] {
  Ok(decode(original.root, original.max_stages, original.usage)) catch {
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
  match parse_program_input(source,limits,format~,source_path~) {
    Ok(original) => finish_program_input(original)
    Err(issue) => Err(issue)
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
        @source.parse_program_yaml_bytes_measured(
          source,
          limits.source,
          source_path~,
        )
      } else {
        @source.parse_program_json_bytes_measured(
          source,
          limits.source,
          source_path~,
        )
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
/// Generated input follows the same closed-envelope decoder. The builder owns
/// admission and measurements; no caller-supplied usage is accepted here.
pub fn admit_generated_source(
  source : @builder.Source,
  limits : Limits,
) -> Result[Program, SyntaxError] {
  let root = @builder.cursor(source)
  let usage = @builder.usage(source)
  match
    check_usage(
      { source: usage, tree: @wire.admission_usage(root), stages: 0, },
      limits,
      @wire.cursor_span(root).source_path,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(decode(root, limits.max_stages, usage)) catch {
    Abort(error) => Err(error)
  }
}

///|
/// Admit an unfinished generated prefix through the same closed envelope and
/// retained-size checks. Authored Program parsing and admission remain strict.
pub fn admit_generated_prefix(
  source : @builder.Source,
  limits : Limits,
) -> Result[Prefix, SyntaxError] {
  let root = @builder.cursor(source)
  let usage = @builder.usage(source)
  match
    check_usage(
      { source: usage, tree: @wire.admission_usage(root), stages: 0, },
      limits,
      @wire.cursor_span(root).source_path,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(decode_prefix(root, limits.max_stages, usage)) catch {
    Abort(error) => Err(error)
  }
}
