///|
/// Initial bounded Client Host preparation profile. Hosts may choose tighter
/// limits, but sharing this profile keeps Local and Cloud prototype intake
/// consistent while they use the same checked Program owner.
pub fn client_standard_program_preparation_limits() -> ClientProgramPreparationLimits {
  {
    checking: {
      input: {
        source: { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
        tree: {
          max_nodes: 8192,
          max_depth: 64,
          max_string_bytes: 65536,
          max_total_string_bytes: 65536,
        },
        max_stages: 32,
      },
      compilation: {
        work: 10000000,
        artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
        structure: {
          stages: 32,
          steps: 1024,
          results: 1024,
          parameters: 1024,
          bindings: 100000,
          slots: 100000,
          references: 100000,
          requirements: 100000,
          tokens: 100000,
        },
        traversal: {
          nodes: 1000000,
          depth: 100,
          text_bytes: 10000000,
          string_bytes: 1000000,
          name_bytes: 1000000,
          pointer_units: 1000000,
          comparison_pairs: 1000000,
        },
        values: { nodes: 1000000, depth: 100, text_bytes: 1000000, },
        policy: { bytes: 1000000, nodes: 1000000, depth: 100, },
        patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
      },
    },
    lowering: {
      max_nodes: 100000,
      max_references: 100000,
      max_work: 1000000,
      max_identifier_bytes: 65536,
    },
    max_parameters: 1024,
    max_parameter_name_bytes: 65536,
    max_tasks: 32,
    max_graph_work: 1000000,
  }
}

///|
/// Exact sequence budget for the first direct Values execution profile.
pub fn client_standard_values_sequence_limits() -> @lower.SequenceLimits {
  {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
}
