///|
/// Same original source/key admission and closed Program envelope as text
/// intake, without serializing an already captured native value. Native DATA
/// is not an SDK receipt; the actual Request caller owns its original lease.
pub fn[T] admit_captured_program_input(
  input : T,
  reader : @source.JsonDataReader[T],
  limits : Limits,
) -> Result[ParsedProgramInput, SyntaxError] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  match
    @source.admit_captured_json(input, reader, limits.source, program_keys=true) {
    Err(issue) => Err(Parse(issue))
    Ok(parsed) => admit_program_input(parsed, limits)
  }
}
