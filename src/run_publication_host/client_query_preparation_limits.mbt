///|
/// Query syntax uses the same finite Program preparation profile as its
/// subsequent lowerer/compiler. This DATA grants no capacity: the Request
/// reserves actual document/syntax coexistence before calling the parser.
pub fn client_program_query_syntax_limits(
  limits : ClientProgramPreparationLimits,
) -> @query_syntax.QueryLimits {
  let original = @source_frontend.syntax_limits()
  let lexical : @query_syntax.LexicalLimits = {
    max_source_bytes: limits.checking.input.source.max_input_bytes,
    max_tokens: limits.lowering.max_nodes,
    max_literal_bytes: limits.checking.input.tree.max_string_bytes,
    max_work: limits.lowering.max_work,
  }
  {
    ..original,
    lexical,
    expression: {
      lexical,
      max_nodes: limits.lowering.max_nodes,
      max_depth: limits.checking.input.tree.max_depth,
      max_work: limits.lowering.max_work,
    },
    max_syntax_nodes: limits.lowering.max_nodes,
    max_work: limits.lowering.max_work,
  }
}

///|
/// The output is generated Program material, not the original SQL wire.
/// Keep the installed join/collection dimensions, and use the existing
/// compiler artifact envelope for this constructor's tree and encoded output.
/// The original Request funds actual expanded material before construction.
pub fn client_program_query_lowering_limits(
  limits : ClientProgramPreparationLimits,
) -> @update_targets.Limits {
  let artifacts = limits.checking.compilation.artifacts
  let input : @syntax.Limits = {
    source: {
      max_input_bytes: artifacts.bytes,
      max_nodes: artifacts.nodes,
      max_depth: artifacts.depth,
    },
    tree: {
      max_nodes: artifacts.nodes,
      max_depth: artifacts.depth,
      max_string_bytes: limits.checking.compilation.traversal.string_bytes,
      max_total_string_bytes: limits.checking.compilation.traversal.text_bytes,
    },
    max_stages: limits.checking.input.max_stages,
  }
  {
    ..@source_frontend.query_limits(),
    source: {
      source: input.source,
      tree: input.tree,
      max_origin_entries: artifacts.nodes,
      max_output_bytes: artifacts.bytes,
    },
    program: input,
    max_expression_work: limits.lowering.max_work,
  }
}
