///|
// These are representation quantities on the SAME Task attachment. They do
// not grant value/work allowance or establish physical allocator retirement.
fn fund_managed_output_metadata(budget : ValueBudget, bytes : Int64) -> Bool {
  guard budget.row_scratch_start is Some(_) &&
    budget.retention is Some(growth) &&
    growth.retained_outputs is Some(total) else {
    return true
  }
  guard checked_preparation_add_product(total, bytes, 1L) is Some(next) else {
    growth.failed = true
    return false
  }
  grow_workspace(growth, growth.slots, growth.logical, retained=Some(next))
}

///|
// The existing complete schema proof selects the already-supported
// ReferenceFree receipt representation. Reference-bearing or unmetered
// streams keep their original full accounting/availability traversal.
fn prepare_managed_output_scratch(
  budget : ValueBudget,
  schema : @schema.Schema,
) -> Bool {
  guard budget.retention is Some(growth) && growth.retained_outputs is Some(_) else {
    return true
  }
  // Original-projection tuples/nullable overlap and the bridge's completion
  // aliases. These are fixed references/scalars, never another payload copy.
  guard preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 24L,
      scalar_words: 4L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(control) &&
    checked_preparation_add_product(
      growth.retained_outputs.unwrap(),
      control,
      1L,
    )
    is Some(retained) &&
    grow_workspace(
      growth,
      growth.slots,
      growth.logical,
      retained=Some(retained),
    ) else {
    return false
  }
  let proof_peak = Ref(0L)
  let reference_free = managed_schema_reference_free(
    schema,
    budget.limits.max_nodes,
    reserve=Some(count => {
      guard preparation_array_representation(1L, count.to_int64(), true)
        is Some(units) &&
        preparation_representation_cost(units) is Some(bytes) else {
        return false
      }
      let next = Int64::max(proof_peak.val, bytes)
      let delta = next - proof_peak.val
      if delta == 0L {
        return true
      }
      guard checked_preparation_add_product(growth.text, delta, 1L)
        is Some(text) &&
        grow_workspace(growth, growth.slots, growth.logical, text=Some(text)) else {
        return false
      }
      // Conservatively keep this bounded traversal/backing peak with the
      // original Task until cleanup; popping a slot is not a release witness.
      proof_peak.val = next
      true
    }),
  )
  if growth.failed {
    return false
  }
  if reference_free != Some(true) {
    return true
  }
  let width = @schema.field_count(schema).to_int64()
  // Three live column arrays and their finish copies, two row arrays and two
  // buffer roots, plus two empty reference-table roots. Include tuple old/new
  // overlap, stream/budget/finish/receipt
  // controls and the new row markers.
  // Payload rows are separate two-row scratch; no per-row reference matrix is
  // constructed for a schema which cannot contain a reference.
  guard preparation_array_representation(12L, 8L * width + 2L, true)
    is Some(arrays) &&
    compose_preparation_representation([
      arrays,
      {
        record_headers: 16L + 3L * width,
        reference_slots: 48L + 3L * width,
        scalar_words: 64L + 6L * width,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) &&
    preparation_representation_cost(units) is Some(bytes) else {
    return false
  }
  budget.row_scratch_start = Some((0, 0))
  fund_managed_output_metadata(budget, bytes)
}
