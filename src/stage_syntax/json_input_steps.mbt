///|
/// Same original Program source and limits across the preflight/tree/index
/// boundary. No editable Node, claimed usage or substitute limit packet enters
/// the continuation. This holder is not a resource owner or an admission grant.
struct ProgramJsonInput {
  source : @source.JsonSourcePreflight
  limits : Limits
}

///|
pub(all) enum ProgramJsonInputIssue {
  Preflight(@source.JsonSourcePreflightIssue)
  Parser(@source.JsonParseControlIssue)
  Syntax(SyntaxError)
} derive(Eq, Debug)

///|
/// The fixed producer funds Source's original initial inventory plus the
/// additional Program holder inventory BEFORE calling this constructor. The
/// backend's input/limits/path backing and outer roles stay independently held.
pub fn start_program_json_input(
  document : String,
  limits : Limits,
  source_path? : String = "<memory>",
) -> Result[ProgramJsonInput, SyntaxError] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  match
    @source.start_program_json_source_preflight(
      document,
      limits.source,
      source_path~,
    ) {
    Err(error) => Err(Parse(error))
    Ok(source) => Ok({ source, limits, })
  }
}

///|
/// Wire geometry and per-poll work are still the original Source owner's
/// observations, not grammar, Resource or typed Program acceptance.
pub fn advance_program_json_input_preflight(
  original : ProgramJsonInput,
  quantum : Int,
) -> Result[@source.JsonSourcePreflightPoll, @source.JsonSourcePreflightIssue] {
  @source.advance_json_source_preflight(original.source, quantum)
}

///|
/// Call only AFTER the original producer has admitted tree/key/normalization
/// AND index/control coexistence on the SAME parent. Source's cursor is taken
/// once, then the existing index admission constructs its opaque result with
/// these SAME original limits. No raw ParsedSource can replace that owner.
pub fn finish_program_json_input(
  original : ProgramJsonInput,
) -> Result[ParsedProgramInput, ProgramJsonInputIssue] {
  let cursor = match @source.take_json_source_parser(original.source) {
    Err(issue) => return Err(Preflight(issue))
    Ok(value) => value
  }
  // The existing parser is finite under its original input/node/depth bounds.
  // A poll quantum is scheduling DATA, never a new grammar or resource cap.
  while true {
    match @source.advance_json_parse(cursor, 256) {
      Err(issue) => {
        @source.cancel_json_parse(cursor)
        return Err(Parser(issue))
      }
      Ok(@source.JsonParseContinue(..)) => continue
      Ok(@source.JsonParseFailed(error, ..)) => return Err(Syntax(Parse(error)))
      Ok(@source.JsonParseComplete(parsed, ..)) =>
        return match admit_program_input(parsed, original.limits) {
          Err(issue) => Err(Syntax(issue))
          Ok(value) => Ok(value)
        }
    }
  } nobreak {
    Err(Parser(@source.JsonParseControlIssue::Terminal))
  }
}

///|
/// Before transfer, retire the SAME source cursor. After the synchronous
/// continuation returned, it is already terminal and the indexed input belongs
/// to its original caller. This is logical retirement, never physical stop ACK.
pub fn cancel_program_json_input(original : ProgramJsonInput) -> Unit {
  @source.cancel_json_source_preflight(original.source)
}

///|
/// Additional request-owned controls only: original holder1H2R and start
/// carrier1H1R1W. Indexed receipt+success2H3R2W and the nested syntax/error
/// chain3H3R3W are alternatives; their majorant3H4R3W keeps one conservative
/// reference slot. Source initial/tree/index owners and borrowed Limits stay
/// separate. Read this installed descriptor BEFORE request allocation.
pub fn program_json_input_control_extent() -> ProgramConstructorControlExtent {
  program_json_input_controls
}

///|
let program_json_input_controls : ProgramConstructorControlExtent = {
  record_headers: 5L,
  reference_slots: 7L,
  scalar_words: 4L,
}

///|
/// Retained parsed/indexed input receipt only: ParsedProgramInput1H2R1W and
/// its original measured Source ParseUsage1H3W. The Cursor/index, Source
/// spans/Strings, borrowed limits and later Program remain separate owners.
pub fn program_input_retained_control_extent() -> ProgramConstructorControlExtent {
  program_input_retained_controls
}

///|
let program_input_retained_controls : ProgramConstructorControlExtent = {
  record_headers: 2L,
  reference_slots: 2L,
  scalar_words: 4L,
}
