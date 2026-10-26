///|
/// The standard record JSON implementation reuses the existing Client
/// preparation policies. These are codec rejection bounds, not Ledger
/// allowances, admissions, transfer budgets or measured engine allocation.
pub fn installed_record_effect_profile() -> Array[Int] {
  let effect = @publication_host.client_standard_effect_computation_limits()
  let program = effect.program
  let values = @publication_host.client_standard_values_sequence_limits()
  let fields = values.max_cells / values.max_rows
  [
    effect.max_members, // objects
    effect.max_members,
    values.max_rows,
    values.max_cells, // property catalog entries
    fields,
    values.max_name_bytes,
    effect.mapping.max_bytes,
    program.checking.compilation.policy.bytes,
    program.checking.compilation.artifacts.bytes, // saved request
    program.checking.compilation.artifacts.bytes, // complete description
    effect.effects.max_admission_nodes,
    effect.effects.max_admission_depth,
    values.expressions.max_literal_nodes,
    program.checking.compilation.values.text_bytes,
    effect.effects.max_work,
    program.checking.compilation.traversal.pointer_units,
    program.checking.compilation.artifacts.bytes,
    values.expressions.max_literal_nodes,
    program.checking.compilation.values.depth,
    7 + 2 * 32, // sha256: and the complete hexadecimal digest
    program.checking.input.tree.max_string_bytes,
    program.checking.compilation.structure.bindings,
  ]
}
