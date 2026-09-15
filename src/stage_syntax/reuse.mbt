///|
pub(all) enum RetentionLimit {
  InputBytes
  SourceNodes
  SourceDepth
  TreeNodes
  TreeDepth
  StringBytes
  TotalStringBytes
  Stages
} derive(Eq, Debug)

///|
/// Retained sizes, not parsing work performed by a later reuse.
pub(all) struct ProgramUsage {
  source : @source.ParseUsage
  tree : @wire.AdmissionUsage
  stages : Int
} derive(Eq, Debug)

///|
pub fn program_usage(program : Program) -> ProgramUsage {
  {
    source: program.source_usage,
    tree: @wire.admission_usage(program.body),
    stages: program.stages.length(),
  }
}

///|
/// Check current input restrictions without parsing, copying or revalidating
/// the stage envelope. Only an admitted Program can enter this path. This is
/// not semantic checking, and does not charge the original parse as new work.
pub fn validate_reuse(
  program : Program,
  limits : Limits,
) -> Result[Unit, SyntaxError] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let usage = program_usage(program)
  let exceeded = if usage.source.input_bytes > limits.source.max_input_bytes {
    Some(InputBytes)
  } else if usage.source.nodes > limits.source.max_nodes {
    Some(SourceNodes)
  } else if usage.source.depth > limits.source.max_depth {
    Some(SourceDepth)
  } else if usage.tree.nodes > limits.tree.max_nodes {
    Some(TreeNodes)
  } else if usage.tree.depth > limits.tree.max_depth {
    Some(TreeDepth)
  } else if usage.tree.largest_string_bytes > limits.tree.max_string_bytes {
    Some(StringBytes)
  } else if usage.tree.total_string_bytes > limits.tree.max_total_string_bytes {
    Some(TotalStringBytes)
  } else if usage.stages > limits.max_stages {
    Some(Stages)
  } else {
    None
  }
  match exceeded {
    Some(kind) =>
      Err(
        RetentionLimit(
          kind,
          source_path=@wire.cursor_span(program.body).source_path,
        ),
      )
    None => Ok(())
  }
}
