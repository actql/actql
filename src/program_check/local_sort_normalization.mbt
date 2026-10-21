///|
// These are owned completion occurrences, not a journal admitted from DATA.
priv struct LocalSortNormalizationEntry {
  operation : @relation.CheckedOperation
  order : @pipeline.SortOrder?
  path : String
  authored : String
  canonical : String
}

///|
/// Retains the original checked Program and its actual completion occurrences.
/// The completion-free inventory remains a separate, strict subset.
struct LocalSortNormalizationInventory {
  owner : CheckedProgram
  audited_work : Int
  entries : Array[LocalSortNormalizationEntry]
  distincts : Bool
  sets : Bool
  dedupes : Bool
  assertions : Bool
  joins : Bool
  defaulted_parameters : Bool
}

///|
fn local_sort_text_work(text : String, remaining : Int) -> Int? {
  if text.length() > remaining / 4 {
    None
  } else {
    Some(remaining - text.length() * 4)
  }
}

///|
fn local_sort_normalization_entry(
  operation : @relation.CheckedOperation,
  order : @pipeline.SortOrder,
  available : Int,
) -> (LocalSortNormalizationEntry, Int)? {
  guard @pipeline.sort_order_strategy(order) is CandidateKey(completion) &&
    @pipeline.sort_completion_count(completion) > 0 else {
    return None
  }
  let source = @relation.source(operation)
  // The path is read from the original decoded Program, never reconstructed
  // from a stage name, caller index or an equal operation body.
  guard @decode.cursor_path(source)
    is [Key("stages"), Index(stage), Key("steps"), Index(step), Key("sort")] &&
    stage >= 0 &&
    step == @pipeline.sort_order_step(order) else {
    return None
  }
  let path = "$.stages[" +
    stage.to_string() +
    "].steps[" +
    step.to_string() +
    "].sort"
  let mut remaining = match local_sort_text_work(path, available - 5) {
    Some(left) => left
    None => return None
  }
  let authored = @encode.writer(1024, 32, 8) catch { _ => return None }
  let canonical = @encode.writer(1024, 32, 8) catch { _ => return None }
  try {
    @encode.begin_array(authored)
    @encode.begin_array(canonical)
    for index in 0..<@relation.sort_term_count(operation) {
      if remaining <= 0 {
        return None
      }
      remaining -= 1
      let term = @relation.sort_term_at(operation, index).unwrap()
      guard @decode.element_at(source, index) is Some(original) &&
        @decode.tree_index(original, term.source) ==
        @decode.tree_index(original, original) else {
        return None
      }
      let fields = @decode.object_field_names(original).unwrap()
      fields.sort_by(@canonical.compare_utf16)
      @encode.begin_object(authored)
      for name in fields {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        let value = @decode.text(
          @decode.lookup(@decode.open_object(original).unwrap(), name).unwrap(),
        ).unwrap()
        remaining = match local_sort_text_work(name, remaining) {
          Some(left) => left
          None => return None
        }
        remaining = match local_sort_text_work(value, remaining) {
          Some(left) => left
          None => return None
        }
        @encode.key(authored, name)
        @encode.string_value(authored, value)
      }
      @encode.end_object(authored)
      let name = @schema.reference_name(term.field)
      remaining = match local_sort_text_work(name, remaining) {
        Some(left) => left
        None => return None
      }
      @encode.begin_object(canonical)
      @encode.key(canonical, "dir")
      @encode.string_value(
        canonical,
        if term.direction is Asc {
          "asc"
        } else {
          "desc"
        },
      )
      @encode.key(canonical, "field")
      @encode.string_value(canonical, name)
      @encode.key(canonical, "nulls")
      @encode.string_value(
        canonical,
        if term.nulls is First {
          "first"
        } else {
          "last"
        },
      )
      @encode.end_object(canonical)
    }
    for index in 0..<@pipeline.sort_completion_count(completion) {
      if remaining <= 0 {
        return None
      }
      remaining -= 1
      let name = @schema.reference_name(
        @pipeline.sort_completion_field(completion, index).unwrap(),
      )
      remaining = match local_sort_text_work(name, remaining) {
        Some(left) => left
        None => return None
      }
      @encode.begin_object(canonical)
      @encode.key(canonical, "dir")
      @encode.string_value(canonical, "asc")
      @encode.key(canonical, "field")
      @encode.string_value(canonical, name)
      @encode.key(canonical, "nulls")
      @encode.string_value(canonical, "last")
      @encode.end_object(canonical)
    }
    @encode.end_array(authored)
    @encode.end_array(canonical)
    Some(
      (
        {
          operation,
          order: Some(order),
          path,
          authored: @encode.finish(authored),
          canonical: @encode.finish(canonical),
        },
        remaining,
      ),
    )
  } catch {
    _ => None
  }
}

///|
// Each original operation has one unique path. Sorting these paths therefore
// gives the full journal tuple order even when their frozen rules differ.
fn canonical_local_sort_entries(
  entries : Array[LocalSortNormalizationEntry],
  available : Int,
) -> Int? {
  let mut remaining = available
  for index in 1..<entries.length() {
    let mut at = index
    while at > 0 {
      remaining = match local_sort_text_work(entries[at - 1].path, remaining) {
        Some(left) => left
        None => return None
      }
      remaining = match local_sort_text_work(entries[at].path, remaining) {
        Some(left) => left
        None => return None
      }
      let comparison = @canonical.compare_utf16(
        entries[at - 1].path,
        entries[at].path,
      )
      if comparison == 0 {
        return None
      }
      if comparison < 0 {
        break
      }
      let previous = entries[at - 1]
      entries[at - 1] = entries[at]
      entries[at] = previous
      at -= 1
    }
  }
  Some(remaining)
}

///|
/// Selection reads the original precomputed audit; it does not retry checking
/// or interpret a failed completion-free issuer as permission.
pub fn local_program_sort_normalization_inventory(
  owner : CheckedProgram,
) -> Result[LocalSortNormalizationInventory?, CompletionFreeInventoryIssue] {
  if owner.has_effects {
    return Err(ProfileNotInstalled)
  }
  match local_audit_base(owner.local_completion_free_audit) {
    Complete(_, _, _, _, _, _, _, _)
    | DistinctComplete(_, _, _, _, _, _, _, _)
    | SetComplete(_, _, _, _, _, _, _, _, _)
    | DedupeComplete(_, _, _, _, _, _, _, _, _, _)
    | AssertionComplete(_, _, _, _, _, _, _, _, _, _, _)
    | JoinComplete(_, _, _, _, _, _, _, _, _, _, _, _) => Ok(None)
    SortCompleted(work, entries, defaulted_parameters)
    | DistinctSortCompleted(work, entries, defaulted_parameters)
    | SetSortCompleted(work, entries, _, defaulted_parameters)
    | DedupeSortCompleted(work, entries, _, _, defaulted_parameters)
    | AssertionSortCompleted(work, entries, _, _, _, defaulted_parameters)
    | JoinSortCompleted(work, entries, _, _, _, _, defaulted_parameters) =>
      Ok(
        Some({
          owner,
          audited_work: work,
          entries,
          defaulted_parameters,
          sets: local_audit_uses_set(owner.local_completion_free_audit),
          dedupes: local_audit_uses_dedupe(owner.local_completion_free_audit),
          assertions: local_audit_uses_assertions(
            owner.local_completion_free_audit,
          ),
          joins: local_audit_uses_join(owner.local_completion_free_audit),
          distincts: local_audit_uses_distinct(
            owner.local_completion_free_audit,
          ),
        }),
      )
    CompletionObserved => Err(CompletionObserved)
    ProfileNotInstalled | ScalarCapabilitiesAudit(_, _, _) =>
      Err(ProfileNotInstalled)
  }
}

///|
pub fn local_sort_normalization_inventory_matches(
  value : LocalSortNormalizationInventory,
  owner : CheckedProgram,
) -> Bool {
  physical_equal(value.owner, owner)
}

///|
pub fn local_sort_normalization_inventory_work(
  value : LocalSortNormalizationInventory,
) -> Int {
  value.audited_work
}

///|
pub fn local_sort_normalization_entry_count(
  value : LocalSortNormalizationInventory,
) -> Int {
  value.entries.length()
}

///|
/// DATA projection from the nominal inventory, not an alternate issuer.
pub fn local_sort_normalization_entry_at(
  value : LocalSortNormalizationInventory,
  index : Int,
) -> (String, String, String)? {
  guard value.entries.get(index) is Some(entry) else { return None }
  match entry.order {
    Some(order) =>
      if !(@pipeline.sort_order_consumer(order).operation
        is @pipeline.Unary(original) &&
        physical_equal(original, entry.operation)) {
        return None
      }
    None =>
      match @relation.operation(entry.operation) {
        Rename | Drop => ()
        _ => return None
      }
  }
  Some((entry.path, entry.authored, entry.canonical))
}

///|
/// Rule metadata from the same owned occurrence, never a caller-selected rule.
pub fn local_sort_normalization_entry_rule_at(
  value : LocalSortNormalizationInventory,
  index : Int,
) -> String? {
  guard local_sort_normalization_entry_at(value, index) is Some(_) &&
    value.entries.get(index) is Some(entry) else {
    return None
  }
  Some(
    match entry.order {
      Some(_) => "sort.candidate_key_completion"
      None =>
        match @relation.operation(entry.operation) {
          Rename => "relation.rename_projection"
          Drop => "relation.drop_projection"
          _ => return None
        }
    },
  )
}

///|
/// Catalogue metadata from actual original projection occurrences.
pub fn local_sort_normalization_inventory_uses_projection(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.entries.any(entry => entry.order is None)
}

///|
/// Metadata of the same original audit, including its actual completion entries.
pub fn local_sort_normalization_inventory_uses_distinct(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.distincts
}

///|
/// Metadata from the complete original audit, independent of Sort entries.
pub fn local_sort_normalization_inventory_parameters_defaulted(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.defaulted_parameters
}

///|
/// Metadata from the same retained audit, not a caller-selected catalogue.
pub fn local_sort_normalization_inventory_uses_set(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.sets
}

///|
/// Dedupe capability is independent of the retained real completion entries.
pub fn local_sort_normalization_inventory_uses_dedupe(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.dedupes
}

///|
/// Original assertion capability; actual validation stays with execution.
pub fn local_sort_normalization_inventory_uses_assertions(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.assertions
}

///|
/// Original keyed-Join metadata alongside actual retained completion entries.
pub fn local_sort_normalization_inventory_uses_join(
  value : LocalSortNormalizationInventory,
) -> Bool {
  value.joins
}

///|
/// Exact Decimal sums retain the same original Source/Sort completion entries.
pub fn local_sort_normalization_inventory_uses_decimal_sum(
  inventory : LocalSortNormalizationInventory,
) -> Bool {
  inventory.owner.local_completion_free_audit
  is ScalarCapabilitiesAudit(_, true, _)
}

///|
/// The same unary original retains actual Source/Sort completion entries.
pub fn local_sort_normalization_inventory_uses_unary_timestamp(
  inventory : LocalSortNormalizationInventory,
) -> Bool {
  inventory.owner.local_completion_free_audit
  is ScalarCapabilitiesAudit(_, _, true)
}
