///|
/// Compilation controls, not runtime capacity contracts or physical budgets.
/// The same selected ceiling can bound several independent traversals; it does
/// not combine their different meters or replace aggregate work accounting.
pub(all) struct CompileLimits {
  work : Int
  artifacts : CompileArtifactLimits
  structure : CompileStructureLimits
  traversal : CompileTraversalLimits
  values : CompileValueLimits
  policy : CompilePolicyLimits
  patterns : CompilePatternLimits
} derive(Eq, Debug)

///|
/// Aggregate generated/admitted artifact accounting used by Program checking.
/// Depth is a per-traversal maximum, never an additive node counter.
pub(all) struct CompileArtifactLimits {
  bytes : Int
  nodes : Int
  depth : Int
} derive(Eq, Debug)

///|
pub(all) struct CompileStructureLimits {
  stages : Int
  steps : Int
  results : Int
  parameters : Int
  bindings : Int
  slots : Int
  references : Int
  requirements : Int
  tokens : Int
} derive(Eq, Debug)

///|
pub(all) struct CompileTraversalLimits {
  nodes : Int
  depth : Int
  text_bytes : Int
  string_bytes : Int
  name_bytes : Int
  pointer_units : Int
  comparison_pairs : Int
} derive(Eq, Debug)

///|
pub(all) struct CompileValueLimits {
  nodes : Int
  depth : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) struct CompilePolicyLimits {
  bytes : Int
  nodes : Int
  depth : Int
} derive(Eq, Debug)

///|
pub(all) struct CompilePatternLimits {
  bytes : Int
  nodes : Int
  depth : Int
} derive(Eq, Debug)

///|
fn compile_limits_valid(limits : CompileLimits) -> Bool {
  let a = limits.artifacts
  let s = limits.structure
  let t = limits.traversal
  let v = limits.values
  let p = limits.policy
  let r = limits.patterns
  limits.work >= 0 &&
  a.bytes >= 0 &&
  a.nodes >= 0 &&
  a.depth >= 0 &&
  s.stages >= 0 &&
  s.steps >= 0 &&
  s.results >= 0 &&
  s.parameters >= 0 &&
  s.bindings >= 0 &&
  s.slots >= 0 &&
  s.references >= 0 &&
  s.requirements >= 0 &&
  s.tokens >= 0 &&
  t.nodes >= 0 &&
  t.depth >= 0 &&
  t.text_bytes >= 0 &&
  t.string_bytes >= 0 &&
  t.name_bytes >= 0 &&
  t.pointer_units >= 0 &&
  t.comparison_pairs >= 0 &&
  v.nodes >= 0 &&
  v.depth >= 0 &&
  v.text_bytes >= 0 &&
  p.bytes >= 0 &&
  p.nodes >= 0 &&
  p.depth >= 0 &&
  r.bytes >= 0 &&
  r.nodes >= 0 &&
  r.depth >= 0
}

///|
// Only the compiler expands meters into preparation limits. Each lower pass
// keeps its own counting rule, and construct_local additionally clamps work and
// artifact emission to the actual remaining aggregate budget.
fn compile_source_limits(limits : CompileLimits) -> SourceLimits {
  let s = limits.structure
  let t = limits.traversal
  {
    topology: {
      max_stages: s.stages,
      max_steps: s.steps,
      max_results: s.results,
      max_work: limits.work,
      max_nodes: t.nodes,
      max_tokens: s.tokens,
      max_text_bytes: t.text_bytes,
      max_depth: t.depth,
    },
    context: {
      stages: {
        max_work: limits.work,
        max_text_bytes: t.text_bytes,
        max_name_bytes: t.name_bytes,
        max_input_work: limits.work,
        max_operand_work: limits.work,
      },
      max_policy_bytes: limits.policy.bytes,
      max_policy_nodes: limits.policy.nodes,
      max_policy_depth: limits.policy.depth,
      max_local_input_nodes: limits.values.nodes,
    },
    requests: {
      max_work: limits.work,
      max_pairs: t.comparison_pairs,
      values: {
        max_nodes: limits.values.nodes,
        max_depth: limits.values.depth,
        max_text_bytes: limits.values.text_bytes,
      },
    },
    checks: {
      work: limits.work,
      text_bytes: t.text_bytes,
      source_value_nodes: limits.values.nodes,
      source_comparison_pairs: t.comparison_pairs,
      policy_nodes: limits.policy.nodes,
      local_input_nodes: limits.values.nodes,
      pattern_ast_bytes: limits.patterns.bytes,
      pattern_ast_nodes: limits.patterns.nodes,
    },
    identity: {
      body: {
        max_work: limits.work,
        selectors: {
          max_nodes: t.nodes,
          max_depth: t.depth,
          max_text_bytes: t.text_bytes,
          max_tokens: s.tokens,
          tree: {
            max_nodes: t.nodes,
            max_depth: t.depth,
            max_string_bytes: t.string_bytes,
            max_total_string_bytes: t.text_bytes,
          },
        },
      },
      uses: {
        max_work: limits.work,
        max_slots: s.slots,
        max_references: s.references,
        max_pointer_units: t.pointer_units,
        max_direct_text_bytes: t.text_bytes,
      },
      references: {
        max_work: limits.work,
        max_slots: s.slots,
        max_references: s.references,
        max_pointer_units: t.pointer_units,
        max_request_text_bytes: t.text_bytes,
      },
      identity: {
        max_work: limits.work,
        max_stages: s.stages,
        max_hash_bytes: limits.artifacts.bytes,
        max_hash_nodes: limits.artifacts.nodes,
        max_depth: limits.artifacts.depth,
      },
      max_bindings: s.bindings,
    },
    max_parameters: s.parameters,
    max_bindings: s.bindings,
    max_slots: s.slots,
    max_policy_depth: limits.policy.depth,
    max_requirements: s.requirements,
    max_regex_depth: limits.patterns.depth,
  }
}
