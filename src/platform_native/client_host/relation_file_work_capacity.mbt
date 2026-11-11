///|
// Closed Work-control overlap, distinct from Source acquisition and Common
// task/output geometry. H/R/S mean representation headers/reference slots/
// scalar words. Borrowed original trees, strings and contracts are not copied.
//
// * Work H1/R18/S2; no Resident wrapper. Its six additional optional
//   timing/publication/identity/basis/error references and grow latch add
//   R6/S1 (56 bytes), even when unpopulated on the existing Query path.
// * Existing Source-cut LedgerUsage H1/S13 retained beyond later mutable
//   replacements and Source logical close. ledger_usage itself only borrows;
//   this item funds the extended custody through Work physical retirement.
// Access/base/source originals are Read-owned. The routing-refusal frontier
// separately owns the terminal access-primary Some, so it is not counted twice.
// * Failure carrier, three field options and ResultErr H5/R8/S4.
// * Three closed source/plan match tuples H3/R7.
// * Funded Query selector H1/R5/S1 and retained Query plan H1/R1/S1.
// * Pre-Source read-cleanup continuation/closure/Some H3/R5/S1.
// * The selected result bridge's row/count pair H1/R1/S1.
//   These replace the former declaration/requirement/acquisition tuple;
//   the net fixed Query delta is H8/R16/S4 = 288 bytes.
// * Work closure expressions H7/R11: unstarted2, rejected Source cleanup1,
//   Source cleanup1, current2, live2, Common failure cleanup2, Work cleanup1.
// * Row-access call closures H4/R4: current0, lookup1, claim1, start-current2.
//   Include the zero-capture function value conservatively, without relying
//   on compiler lifting; all mutually exclusive call branches are counted.
// * Common requirements/live option arguments H2/R2/S2.
// * Successful Work Result and caller-retained option H2/R2/S2.
// * Work current-error mapping function H1/R0 and issue wrapper H1/R1/S1.
// * Two original prepared-binding cache hits and final map_err Unit product
//   H3/S6. Primitive exact-cache guards refuse before any business reseeding.
// * Original requirement stage lookup Some H1/R1/S1.
// * Direct Row capture-source Result and mapped CaptureIdentity H2/R2/S2.
// * Original publication-limit projection H9/R7/S20.
// * One retained Common result-export record + Result H2/R3/S2, then the
//   Work-owned retained Some and return Result H2/R2/S2. Its payload,
//   exporter and variable row/schema workspace retain their Common inventory.
// * Original StoreOperation business pre-switch frontier H790/R374/S1498:
//   direct receiver/Read observers H353/R176/S676 and nested begin/leave
//   H437/R198/S822. This includes all 588 literal Ok(Unit) occurrences,
//   conservative zero-capture function values and actual Library Ok mapping.
//   It includes both separately produced host/original tuple+Ok pairs, not
//   copies of their borrowed payloads. Poll H428/R192/S812 fits this frontier
//   only after actual completed return has cleared the registered route Some
//   fields. Sticky failure prevents reusing it as a fresh normal-current cut.
// * Successful reference-return tail H7/R1/S11; the Unit variant H7/S12
//   has identical cost. Lower-current error overlay H34/R26/S42.
// * Routing refusal H16/R12/S11/U237 includes the actual terminal primary
//   Some and bounded SQLite diagnostic construction, not borrowed text.
// * Simultaneous preflight DATA H6/R3/S20: Source limit clone/addition and
//   original Common simultaneous-limit projection (280 bytes).
// * Source failure with no acquired owner returns Ok(true) H1/S2 on cleanup.
// * Owner-backed Failure.close then Work.close/close_export: all three
//   allocating cleanup predicates H296/R95/S500, summed without reuse.
//   Primitive original/token/scope guards precede every accepted predicate.
// * Original business return/reentry frontier H86/R23/S149 (2752 bytes).
//   It preserves this same Work/token; separate Read and outer products remain
//   coordinator-owned. No unrelated reservation or replacement Run is issued.
// * Source's original business Ledger borrow including refusal H88/R26/S152,
//   and its metadata byte-token reserve H26/R20/S60, before that token exists.
// First-start and Account callback products belong to the entered original
// Read. Read-owned entry/token constructors have a distinct pre-admitted
// component. The Source caller inventory below separately owns its first
// mapping and quote evaluator, not the later Source-owned payload.
//
// Keep this complete peak reserved through original child cleanup. No phase,
// closed callback or GC success is treated as reusable capacity.
fn relation_file_work_control_bytes() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 1L +
    1L +
    5L +
    3L +
    7L +
    4L +
    2L +
    2L +
    1L +
    1L +
    2L +
    790L +
    7L +
    34L +
    16L +
    88L +
    26L +
    6L +
    1L +
    3L +
    1L +
    9L +
    2L +
    2L +
    296L +
    86L +
    6L,
    reference_slots: 18L +
    8L +
    7L +
    11L +
    4L +
    2L +
    2L +
    1L +
    3L +
    374L +
    1L +
    26L +
    12L +
    26L +
    20L +
    3L +
    1L +
    7L +
    2L +
    2L +
    95L +
    23L +
    12L,
    scalar_words: 2L +
    13L +
    4L +
    2L +
    2L +
    1L +
    2L +
    1498L +
    11L +
    42L +
    11L +
    152L +
    60L +
    20L +
    2L +
    6L +
    1L +
    20L +
    2L +
    2L +
    500L +
    149L +
    4L,
    owned_utf16_units: 237L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Complete control constructor overlap for the original relation-file Work.
/// The installed coordinator composes this DATA before provisioning; the Work
/// entry reserves it on its actual retained execution Ledger before allocation.
pub fn native_relation_file_work_control_capacity(
  selection : @row_file.NativeRelationFileSelection,
  limits : @row_file.NativeRelationFileLimits,
) -> @execution.ExecutionCapacity? {
  guard @row_file.native_relation_file_caller_preparation_inventory(
      selection, limits,
    )
    is Some(source_inventory) &&
    @execution.preparation_representation_cost(source_inventory) is Some(source) &&
    relation_file_work_control_bytes() is Some(fixed) &&
    @execution.checked_preparation_add_product(fixed, source, 1L)
    is Some(native) &&
    @local.captured_local_tasks_control_capacity() is Some(common) &&
    @execution.checked_preparation_add_product(
      native,
      @execution.execution_capacity_retained_bytes(common),
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      native,
      @execution.execution_capacity_execution_bytes(common),
      1L,
    )
    is Some(executing) else {
    return None
  }
  @execution.execution_capacity(retained, executing)
}

///|
/// Native wrapper/source/task-loop overlap for the existing whole-input Plan.
/// Common module/DAG construction remains held by that same original Plan;
/// this adds no replacement controller, maximum startup or new allowance.
fn native_relation_whole_file_work_control_capacity(
  selection : @row_file.NativeRelationFileSelection,
  limits : @row_file.NativeRelationFileLimits,
  provider : @row_file.NativeRelationFilePreparedProvider,
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  guard @row_file.native_relation_file_caller_preparation_inventory(
      selection,
      limits,
      prepared_provider=Some(provider),
    )
    is Some(source_units) &&
    @execution.preparation_representation_cost(source_units) is Some(source) &&
    relation_file_work_control_bytes() is Some(native) &&
    @local.source_input_local_tasks_control_capacity(graph) is Some(common) &&
    @execution.preparation_representation_cost({
      // The fixed SourceRead record/managed tuple/options and return quadruple;
      // selected-plan/cleanup closures and its immutable bridge geometry.
      // Original current/ledger/metadata frontiers retain the Row/Native
      // recipes above; graph/provider/module payloads retain the Core Plan.
      record_headers: 1L + 2L + 8L + 2L + 3L + 2L,
      reference_slots: 10L + 3L + 8L + 5L + 7L + 3L,
      scalar_words: 1L + 1L + 8L + 1L + 3L + 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(wrappers) &&
    @execution.checked_preparation_add_product(native, source, 1L) is Some(base) &&
    @execution.checked_preparation_add_product(base, wrappers, 1L) is Some(base) &&
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
