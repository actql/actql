///|
/// Complete Whole-input control peak on the SAME prepared Work. Every
/// Source has its own already-quoted physical capture/provider debt. This
/// recipe adds the Native vectors, per-slot typed handoffs, partial-open
/// cleanup frontier and the existing Common complete-input executor.
pub fn native_relation_whole_files_work_control_capacity(
  sources : Array[NativeRelationFileWholeSource],
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  let count = sources.length()
  if count <= 0 {
    return None
  }
  guard relation_file_work_control_bytes() is Some(fixed) &&
    native_relation_whole_file_clock_capacity() is Some(clock) &&
    @local.source_input_local_tasks_control_capacity(graph) is Some(common) &&
    @execution.preparation_array_representation(
      12L,
      12L * count.to_int64(),
      true,
    )
    is Some(vector_units) &&
    @execution.preparation_representation_cost(vector_units) is Some(vectors) &&
    @execution.preparation_representation_cost({
      // Read/acquisition tuples, option/Result handoffs and per-slot Source
      // wrappers; the fixed partial failure/capture/clock/cleanup closures.
      // The same managed-owner/count route pair adds H1/R1/W1.
      record_headers: 33L + 12L * count.to_int64(),
      reference_slots: 65L + 20L * count.to_int64(),
      scalar_words: 49L + 12L * count.to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(wrappers) else {
    return None
  }
  let mut retained = fixed
  for input in sources {
    guard @row_file.native_relation_file_caller_preparation_inventory(
        input.selection,
        input.limits,
        prepared_provider=Some(input.provider),
      )
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(bytes) &&
      @execution.checked_preparation_add_product(retained, bytes, 1L)
      is Some(next) else {
      return None
    }
    retained = next
  }
  guard @execution.checked_preparation_add_product(retained, vectors, 1L)
    is Some(base) &&
    @execution.checked_preparation_add_product(base, wrappers, 1L) is Some(base) &&
    @execution.checked_preparation_add_product(
      base,
      @execution.execution_capacity_retained_bytes(clock),
      1L,
    )
    is Some(base) &&
    @execution.checked_preparation_add_product(
      base,
      @execution.execution_capacity_retained_bytes(common),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      base,
      @execution.execution_capacity_execution_bytes(common),
      1L,
    )
    is Some(e) else {
    return None
  }
  @execution.execution_capacity(r, e)
}

///|
/// Original Read constructor and all selection snapshots, separate from the
/// one business Work debit. No capacity is acquired by this quantity DATA.
pub fn native_relation_whole_files_entry_read_capacity(
  sources : Array[NativeRelationFileWholeSource],
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  guard native_relation_whole_files_work_control_capacity(sources, graph)
    is Some(work) &&
    native_relation_whole_file_preback_read_capacity() is Some(backing) else {
    return None
  }
  let mut r = @execution.execution_capacity_retained_bytes(work)
  let mut e = @execution.execution_capacity_execution_bytes(work)
  for source in sources {
    guard native_relation_file_entry_read_control_capacity(
        source.selection,
        prepared_diagnostic=true,
      )
      is Some(entry) &&
      @execution.checked_preparation_add_product(
        r,
        @execution.execution_capacity_retained_bytes(entry),
        1L,
      )
      is Some(nr) &&
      @execution.checked_preparation_add_product(
        e,
        @execution.execution_capacity_execution_bytes(entry),
        1L,
      )
      is Some(ne) else {
      return None
    }
    r = nr
    e = ne
  }
  guard @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_retained_bytes(backing),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      e,
      @execution.execution_capacity_execution_bytes(backing),
      1L,
    )
    is Some(e) else {
    return None
  }
  @execution.execution_capacity(r, e)
}
