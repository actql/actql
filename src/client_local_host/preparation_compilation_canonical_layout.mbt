///|
/// Constructor facts for canonical_json::from_source with data_keys=true.
/// ScalarText keys are retained unchanged, including Unicode; this path does
/// not normalize identifier names. Source AST/text/UTF8 wire and parser owners
/// are separate dependencies. Bounds are construction DATA, not tree admission.
/// This is a representation projection, never a permit to admit another tree.
priv struct CompilationCanonicalShape {
  nodes : Int
  arrays : Int
  objects : Int
  fields : Int
  depth : Int
  largest_object : Int
}

///|
priv struct CompilationCanonicalLayout {
  tree : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
fn compilation_canonical_layout(
  s : CompilationCanonicalShape,
) -> CompilationCanonicalLayout? {
  if s.nodes < 1 ||
    s.arrays < 0 ||
    s.objects < 0 ||
    s.fields < 0 ||
    s.depth < 0 ||
    s.largest_object < 0 ||
    s.largest_object > s.fields ||
    s.arrays > s.nodes ||
    s.objects > s.nodes ||
    s.fields >= s.nodes {
    return None
  }
  let n = s.nodes.to_int64()
  // Independent subtree upper bounds may overlap; every real container is
  // still one of these SAME value nodes. Object-Map ownership stays separate.
  let c = Int64::min(n, s.arrays.to_int64() + s.objects.to_int64())
  let o = s.objects.to_int64()
  let k = s.fields.to_int64()
  let edges = n - 1L
  // Payload variant per node (Null/Bool use less), FrozenArray+Array/backing
  // per container, and one (key,value) tuple per field. Array::map creates
  // owned output; 8C+2edges also covers its occupied/spare backing. Canonical
  // strings borrow the source text here; they are not cloned per occurrence.
  let tree : @execution.PreparationRepresentationUnits = {
    record_headers: n + 3L * c + k,
    reference_slots: n + 10L * c + 2L * edges + 2L * k,
    scalar_words: n + 2L * c,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // from_source_visit's seen Map is captured only by its synchronous map
  // closure. Returned Object carries values, not seen or that closure. Thus
  // only open ancestor Objects coexist, including the current map being sorted.
  // Each ancestor has at most largest_object members. Keep whole-tree output
  // arrays separately; only these nonescaping duplicate maps use this bound.
  let live_o = Int64::min(o, s.depth.to_int64() + 1L)
  let live_k = Int64::min(k, live_o * s.largest_object.to_int64())
  // Old/new buckets retain inline None tags as well as reference slots.
  let maps : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * live_o + 4L * live_k,
    reference_slots: 18L * live_o + 14L * live_k,
    scalar_words: 21L * live_o + 14L * live_k,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let d = s.depth.to_int64() + 1L
  // InputBudget; active recursive from_source_visit frames (4refs2words);
  // one map closure per active container (<=6refs2words), output old backing
  // per container (conservative even when Array::map allocates exact length).
  let admission : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + 2L * d + c,
    reference_slots: 10L * d + 8L * c + 2L * edges,
    scalar_words: 3L + 4L * d,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Reuse the authoritative pinned Array.sort_by recursion/control recipe.
  guard closed_values_sort_scratch_layout(Int::max(1, s.largest_object))
    is Some(sort) else {
    return None
  }
  guard @execution.compose_preparation_representation([maps, admission, sort])
    is Some(temporary) &&
    @execution.preparation_representation_cost(tree) is Some(_) else {
    return None
  }
  Some({ tree, temporary, })
}
