///|
fn query_checked_limits(stage_count : Int) -> @program_check.CompileLimits {
  {
    work: 100000000,
    artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
    structure: {
      stages: stage_count,
      steps: stage_count,
      results: stage_count,
      parameters: 1,
      bindings: 100,
      slots: 1000,
      references: 1000,
      requirements: 1000,
      tokens: 10000,
    },
    traversal: {
      nodes: 100000,
      depth: 100,
      text_bytes: 10000000,
      string_bytes: 100000,
      name_bytes: 1000000,
      pointer_units: 1000000,
      comparison_pairs: 1000000,
    },
    values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
    policy: { bytes: 10000, nodes: 1000000, depth: 100, },
    patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
  }
}
