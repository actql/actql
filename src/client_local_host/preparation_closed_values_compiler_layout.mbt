///|
/// Constructor-local component, NOT a preparation allowance or a complete
/// phase envelope. The driver must supply the independently admitted original
/// Closed Values shape and combine every remaining constructor family before
/// reserving through the original preparation owner. Source/indexed trees,
/// borrowed names and shared contract references are not copied here.
struct ClosedValuesLiteralLayout {
  retained : @execution.PreparationRepresentationUnits
  field_capacity : Int64
  row_capacity : Int64
  cell_count : Int64
} derive(Eq)

///|
/// Pinned builtin Array growth: empty append arrays start at eight slots and
/// double (arraycore_nonjs.mbt::array_growth_capacity). JS exposes only logical
/// length; this common logical spare-capacity envelope covers that length too.
/// This is not a claim about either engine's allocator or physical heap size.
fn closed_values_append_capacity(length : Int) -> Int64? {
  if length < 0 {
    return None
  }
  if length == 0 {
    return Some(0L)
  }
  let mut capacity = 8L
  while capacity < length.to_int64() {
    capacity *= 2L
  }
  Some(capacity)
}

///|
/// Independent ownership in relation_values/check.mbt:
/// - each cell: Cursor, CheckedValue, Number payload and Literal payload;
/// - each row: source Cursor, Row, cell Array wrapper and backing;
/// - each field: Number Contract and Field (names borrow indexed source);
/// - one object Contract/Object/Fields/Schema/Flat and field Array;
/// - CheckedValues, Usage, its source Cursor, rows/pending/bindings Arrays.
/// Cursor.usage and Cursor.tree borrow the original indexed owner. Number and
/// Literal payload tags are scalar words; zero-payload Number shape is inline.
/// Empty bindings are still an owned empty Array. ResolvePublicationResources
/// is one inline enum slot in the literal pending Array (not append capacity).
/// No temporary Map, decoder view, admission frame or pipeline owner is hidden
/// in this vector; those must be supplied by their distinct phase components.
fn closed_values_literal_layout(
  fields : Int,
  rows : Int,
) -> ClosedValuesLiteralLayout? {
  if fields <= 0 || rows < 0 {
    return None
  }
  guard closed_values_append_capacity(fields) is Some(field_capacity) else {
    return None
  }
  guard closed_values_append_capacity(rows) is Some(row_capacity) else {
    return None
  }
  let f = fields.to_int64()
  let r = rows.to_int64()
  // Int inputs make f*r fit signed Int64; each subsequent projection is still
  // checked before use because headers/slots can overflow even when cells fit.
  let cells = f * r
  // Per-cell (4,6,4); per-row (4,5+field_capacity,3); per-field
  // (2,2,2). Constant owners (16,18,20), plus field/row backing slots.
  guard @execution.checked_preparation_add_product(16L, cells, 4L)
    is Some(headers) else {
    return None
  }
  guard @execution.checked_preparation_add_product(headers, r, 4L)
    is Some(headers) else {
    return None
  }
  guard @execution.checked_preparation_add_product(headers, f, 2L)
    is Some(headers) else {
    return None
  }
  guard @execution.checked_preparation_add_product(18L, cells, 6L) is Some(refs) else {
    return None
  }
  guard @execution.checked_preparation_add_product(refs, r, 5L + field_capacity)
    is Some(refs) else {
    return None
  }
  guard @execution.checked_preparation_add_product(refs, f, 2L) is Some(refs) else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      refs,
      field_capacity + row_capacity,
      1L,
    )
    is Some(refs) else {
    return None
  }
  guard @execution.checked_preparation_add_product(20L, cells, 4L)
    is Some(words) else {
    return None
  }
  guard @execution.checked_preparation_add_product(words, r, 3L) is Some(words) else {
    return None
  }
  guard @execution.checked_preparation_add_product(words, f, 2L) is Some(words) else {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: headers,
    reference_slots: refs,
    scalar_words: words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Refuse a component whose existing tariff cannot itself be represented.
  guard @execution.preparation_representation_cost(retained) is Some(_) else {
    return None
  }
  Some({ retained, field_capacity, row_capacity, cell_count: cells, })
}

///|
/// One local Values lowering owner with no parameters/expressions. Prepared
/// and Usage, PreparedNode, Payload::Values, Some(output_schema), BoundPrepared,
/// Some(original empty BoundValues), ExpressionProfileAdmission: eight headers,
/// twenty refs and sixteen scalar slots. Six Arrays (nodes, three inputs,
/// node refs, node targets) add twelve headers/six refs/twelve words; only nodes
/// is populated (append capacity eight). BoundPrepared's empty builtin Map
/// owns one record + fixed backing, one backing ref, six metadata words and
/// eight empty slots. The generated "values_0" String has one logical header
/// and eight UTF16 units; names/contracts/checked values otherwise borrow.
/// Temporary `used`, identifier concatenation and binding result wrappers are
/// excluded here, not asserted free. No expression-context replacement occurs
/// because the guarded shape's expression closure is empty.
fn closed_values_lower_retained_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 23L,
    reference_slots: 35L,
    scalar_words: 42L,
    owned_utf16_units: 8L,
    owned_wire_bytes: 0L,
  }
}

///|
/// One source-free task, one REL.values publication-resource obligation and
/// one root occurrence. CheckedDAG has thirteen Array fields, plus stage_tasks,
/// operations and numeric each own one nested Array: sixteen wrappers/backings.
/// Scalar backing slots: original_tasks, stage_tasks[0], input_counts,
/// selected_steps, prefix_ends (five). Reference backing slots: owners1,
/// stage_tasks1, targets1, operations1+8, numeric1, results8 (twenty-one).
/// Other owners: CheckedDAG; CheckedResultOccurrence; ManagedResultOccurrence;
/// its Ref[Unit]; one TaskOperationRequirement; Some(Step(0)). All operation
/// sites/dispositions/ports and owners borrow their original context/checker.
/// The single-step Values route does not split carrier tasks; split_boundaries
/// and work Ref are temporary, not included in this retained vector.
fn closed_values_dag_retained_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 39L,
    reference_slots: 59L,
    scalar_words: 45L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// The single Values CheckedPipeline. Its twenty Array fields have length at
/// most one on this shape. Charging an append capacity of eight for each is a
/// constructor-derived upper envelope, including empty borrowed input tables;
/// those same input tables must not be charged again in the context component.
/// Their slots use the eight-byte reference tariff conservatively even for
/// inline None values. Additional retained families are CheckedStep, two
/// source Cursors, Usage, binding/current/output Options, Step targets,
/// Connections, Carrier/Knowledge and complete-schema Option, names Map,
/// RankingInput plus its two empty Maps, DeltaEvidence plus its empty Map,
/// RowCount, LogicalOrder and its empty dependencies. The fixed inventory is
/// (79 headers,254 refs,137 words). This is not an unexplained per-node price.
///
/// The parameters slot references Some(original empty Declarations), not None.
/// That Some owner is charged by the stage-source topology constructor.
///
/// carrier_contract::typed_rows creates a fresh carrier Field + Some(contract)
/// + Unqualified(name) per schema field, and one field-array slot: (3,5,3).
/// The temporary relation_schema::fields array and Field records are separate
/// scratch; names, contracts and Schema themselves remain borrowed.
fn closed_values_pipeline_retained_layout(
  fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  if fields <= 0 {
    return None
  }
  let f = fields.to_int64()
  Some({
    record_headers: 79L + 3L * f,
    reference_slots: 254L + 5L * f,
    scalar_words: 137L + 3L * f,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Top-level CheckedProgram (28 fields: 25 borrowing references and three
/// inline flags/None slots) and BuiltUnit (15 borrowing references). Eleven
/// per-stage limit tables have one outer entry and an empty inner table for
/// Values: nest, traversal, sequence, interval, asof, window, input completeness,
/// group, analytic, group string, analytic string. Their outer backing is
/// conservatively eight slots; inner backing is empty. Empty keyed-input proofs
/// and one-element units add two Arrays. Numeric-slot/audit/context objects and
/// all eight BuiltUnit context arrays remain in the context component.
fn closed_values_program_wrappers_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 50L,
    reference_slots: 160L,
    scalar_words: 51L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Constructor-local builtin linked Map upper inventory including a grow's old
/// and new backing. Each entry has one Entry and two live Some link/bucket
/// wrappers; growth may temporarily keep a further bucket wrapper per entry.
/// Both key and value slots are priced as references even for inline values
/// (same eight-byte tariff). The initial capacity is eight and the threshold
/// is capacity*13/16; this also upper-bounds Map(from_array)'s smaller initial
/// capacities. This helper does not authorize arbitrary Map creation.
fn closed_values_map_constructor_layout(
  entries : Int,
) -> @execution.PreparationRepresentationUnits? {
  if entries < 0 {
    return None
  }
  let n = entries.to_int64()
  let mut capacity = 8L
  while n > capacity * 13L / 16L {
    capacity *= 2L
  }
  Some({
    record_headers: 3L + 4L * n,
    reference_slots: 2L + 2L * capacity + 6L * n,
    scalar_words: 5L + 6L * n,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// `relation_values::scan` traversal storage, before its current ObjectView Map
/// is added separately. node_upper is the admitted source-subtree node bound;
/// largest_object_fields bounds current names. This is an additive coexistence
/// upper bound, not the sum of all sequential scan invocations:
/// - stack wrapper/backing plus old backing during growth;
/// - at most node_upper (Cursor, depth) tuples and their Cursors;
/// - one decoded child array and at most node_upper child Cursors;
/// - current names array, ValueView/ObjectView, returned Usage;
/// - one pop Option, lookup Option, decoded Result and loop view Option.
/// Names, original indexed tree and AdmissionUsage are borrowed. Object maps,
/// caller-local schema/name inventories, scalar admission and sorting remain
/// separate components; none are asserted free by this helper.
fn closed_values_walk_storage_layout(
  node_upper : Int,
  largest_object_fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  if node_upper <= 0 ||
    largest_object_fields < 0 ||
    largest_object_fields > node_upper {
    return None
  }
  closed_values_walk_storage_from_extents(
    node_upper, node_upper, largest_object_fields,
  )
}

///|
/// One constructor formula for generic and guarded traversal. Pending entries
/// own a tuple and Cursor; the current child array owns its Cursor projection.
/// Shared Cursors may make this additive bound conservative, never a second
/// actual allocation charge. Both routes use the same wrapper/backing tariff.
fn closed_values_walk_storage_from_extents(
  pending : Int,
  children : Int,
  names : Int,
) -> @execution.PreparationRepresentationUnits? {
  if pending <= 0 || children < 0 || names < 0 {
    return None
  }
  guard closed_values_append_capacity(pending) is Some(capacity) else {
    return None
  }
  let p = pending.to_int64()
  let c = children.to_int64()
  let f = names.to_int64()
  Some({
    record_headers: 14L + 2L * p + c,
    reference_slots: 10L + 2L * capacity + 3L * p + 3L * c + f,
    scalar_words: 14L + 2L * p + c,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Original exact-shape guard only. relation_values::scan can retain unvisited
/// rows plus current row cells and the other schema branch: <=R+F+2 pending
/// tuples. Schema contract objects have exactly two scalar members; their
/// siblings need <=F+2 entries. Result preflight has one result and its fields
/// array, <=F+2. Current decoded child array has <=max(R,F) Cursors; current
/// object names have <=max(F,3) members. No metadata or other operators enter
/// this route. Generic unproved traversals retain the node-upper helper above.
fn closed_values_guarded_walk_storage_layout(
  fields : Int,
  rows : Int,
) -> @execution.PreparationRepresentationUnits? {
  if fields <= 0 || rows < 0 {
    return None
  }
  let pending = fields.to_int64() + rows.to_int64() + 2L
  if pending > 2147483647L {
    return None
  }
  closed_values_walk_storage_from_extents(
    pending.to_int(),
    Int::max(fields, rows),
    Int::max(fields, 3),
  )
}

///|
/// One numeric `value_admission::admit` transition, not cells copies. Ordinary
/// Values currently uses the resumable typed path (not admit_number_usage).
/// Fixed owners: Limits, Budget, TypedAdmission, Some(root), frame Array/backing,
/// ReadTyped frame, Some(value), popped-frame Option, completion poll, returned
/// usage tuple, its Result and mapped Result; numeric view/finite Result/finite
/// Option. CheckedValue and Value::Number belong to retained literals above.
/// Calls are sequential, so one such component coexists with accumulated rows.
fn closed_values_numeric_admission_scratch_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 16L,
    reference_slots: 17L,
    scalar_words: 32L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Successful authored {type:"number",nullable:false} Contract reader owned
/// scratch, excluding its returned Contract and algorithmic call-frame slots.
/// Six Arrays: work, values, extras, allowed, closed-object keys and required;
/// backing upper slots are 1+8+0+2+2+0. Budget/Limits, Read frame, two ObjectViews,
/// type/nullable Cursors, returned tuple/two Results, map-get/lookup/required
/// wrappers, text/UTF8/NFC/Boolean results and two pop Options give (34,39,43).
/// Two two-entry ObjectView maps add twice the independently checked grow
/// envelope (11,30,17). ASCII quick check retains original "number" text.
fn closed_values_number_contract_scratch_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 56L,
    reference_slots: 99L,
    scalar_words: 77L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Additive coexistence envelope for Values caller-owned temporaries. It sums
/// even mutually exclusive constructor scopes rather than assume early GC:
/// six field-sized maps (schema view, row view, wide-key present/admitted/seen,
/// object_contract duplicate set), one two-field Values view and empty params.
/// Separate arrays own schema names, (name,Contract) tuples, input row Cursors,
/// current row keys, empty required keys and two wide-key tuple inventories.
/// All row Cursors themselves are already in the retained literal envelope.
/// Fixed Budget/Limits, views/Cursors and nonblank's fourteen-scalar literal
/// array are counted. Four old backing headers cover tuple fields, schema
/// fields, current cells and rows during their append growth; their slots are
/// three field capacities plus one row capacity. Returned data/string backing
/// is not copied. Algorithmic local frames and error paths remain separate.
fn closed_values_values_caller_scratch_layout(
  fields : Int,
  rows : Int,
) -> @execution.PreparationRepresentationUnits? {
  if fields <= 0 || rows < 0 {
    return None
  }
  guard closed_values_map_constructor_layout(fields) is Some(map) else {
    return None
  }
  guard closed_values_append_capacity(fields) is Some(fc) else { return None }
  guard closed_values_append_capacity(rows) is Some(rc) else { return None }
  let f = fields.to_int64()
  let r = rows.to_int64()
  // Base (23+3F,19+8F+fc+R,40+2F), six large maps,
  // two-field map (11,30,17), empty-map envelope (3,18,5), growth overlap.
  Some({
    record_headers: 41L + 3L * f + 6L * map.record_headers,
    reference_slots: 67L + 8L * f + 4L * fc + rc + r + 6L * map.reference_slots,
    scalar_words: 62L + 2L * f + 6L * map.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Logical sorting frame/view envelope for the pinned builtin sort_by, not
/// engine stack/RSS. Only the smaller partition recurses, so repeatedly halving
/// field count bounds all live quick-sort frames. Each level counts all named
/// argument/loop/local slots (including shadows): eight reference slots and
/// fifteen scalar slots, plus two tuple results, three views and two predecessor
/// Options: (8 headers,13 refs,27 words). Fixed nonrecursive helper frames are model-A runtime baseline, not
/// per-request owners. Pivot's two allocated closures/counter box/tuple, two
/// partition tuple results, heap slice view and comparator closure contribute
/// (8,5,9); these are allocated objects, not baseline frames.
/// Both schema-name and Field sorts are synchronous and share this peak, not
/// two retained arrays or one frame per comparison. ASCII comparison borrows
/// strings. This constructor convention excludes opaque runtime stack backing.
fn closed_values_sort_scratch_layout(
  fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  if fields <= 0 {
    return None
  }
  let mut size = fields
  let mut depth = 1L
  while size > 1 {
    size = size / 2
    depth += 1L
  }
  Some({
    record_headers: 8L + 8L * depth,
    reference_slots: 5L + 13L * depth,
    scalar_words: 9L + 27L * depth,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// One strict ResultPort over the guarded all-field Values projection. The
/// original fields Cursor feeds relation.check(Select); no synthetic source
/// document exists. Two independent Flat output schemas are built (declaration
/// and checked Select). The projected producer builds three typed Knowledge
/// copies: KeySet.records, RankingInput.carrier and ProducedInput.carrier.
/// Their copied Field/Some/FieldName owners are not the input schema's fields.
///
/// Fixed families: two Flat schemas (14,14,18); three Knowledge/carrier graphs
/// (14,14,20); ranking/maps/Some (6,6,33); key set/array/Some (4,4,5); literal
/// domains/map/Some (4,4,15); ProducedInput (1,10,2); projection/order Options
/// (2,2,2); ResultPublication (1,4,1); logical order/dependencies (4,5,9);
/// inherited Decision/terms (4,4,7); PublishedInput (1,3,0); ResultPort (1,2,1);
/// ResultPorts/entries/Usage (4,12,5); ResultDefinition/names/Cursor/target
/// (5,8,7); CheckedResults/table/map/Usage/Cursor (10,30,17); CheckedOrders
/// (1,2,2); PublicationOrders/table (3,11,4); PublicationOrder/terms (4,5,8);
/// checked Select/arrays/source Cursor (8,11,19). Fixed total (91,151,175).
/// Per field: two schema Fields, three copied carrier Fields/Some/FieldNames,
/// Select ProjectionField and original FieldName: (13,22,10). Four append
/// field-array backing capacities are separate. ContextualClosure and original
/// pipeline/contract/source dependencies are borrowed and owned elsewhere.
/// This retained component does not include Result preparation scratch.
fn closed_values_result_port_retained_layout(
  fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  if fields <= 0 {
    return None
  }
  guard closed_values_append_capacity(fields) is Some(capacity) else {
    return None
  }
  let f = fields.to_int64()
  Some({
    record_headers: 91L + 13L * f,
    reference_slots: 151L + 22L * f + 4L * capacity,
    scalar_words: 175L + 10L * f,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
struct ClosedValuesCompilerPhaseLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
  failure : @execution.PreparationRepresentationUnits
} derive(Eq)

///|
/// All source/declaration/Select/port scratch is conservatively added rather
/// than relying on early GC. Declaration and strict Select each have at most
/// the complete Result graph's fixed owners and per-field slots: declaration
/// field cache/projection/schema builders use <=8 headers/field; Select visible
/// table/Cursors/schema builders/typed_rows temporary Fields use <=11. Both
/// are bounded by the retained Result component's 13 headers,22 refs,10 words
/// per field. Their eight large Maps are additional, not hidden in that bound.
/// Ranking transfer owns two current "u:"+name Strings even with empty scores.
fn closed_values_result_scratch_layout(
  fields : Int,
  longest_name : Int,
) -> @execution.PreparationRepresentationUnits? {
  if longest_name < 0 {
    return None
  }
  guard closed_values_result_port_retained_layout(fields) is Some(port) else {
    return None
  }
  guard closed_values_map_constructor_layout(fields) is Some(map) else {
    return None
  }
  let strings : @execution.PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 2L * (longest_name.to_int64() + 2L),
    owned_wire_bytes: 0L,
  }
  @execution.compose_preparation_representation([
    port, port, map, map, map, map, map, map, map, map, strings,
  ])
}

///|
/// One local failure, conservatively including all mutually exclusive issue
/// families: Decode/Value/Values/Pipeline/Relation/Results/Lower/Binding/Graph,
/// CheckDiagnostic/DiagnosticLocation, typed cause wrappers through LocalSource,
/// LocalProgram/SourceView/LocalContext/SourceFailure/LocalConstruction and the
/// two client preparation boundaries, plus their Result/Option wrappers. Node's
/// fixed-code Error and final code/classification record are counted, not its
/// opaque engine stack. Four detached paths cover original + Values/Pipeline
/// copies + diagnostic location projection. Path segments borrow source keys;
/// source/indexed backing and original phase reservation MUST remain alive
/// through async raw-cause disclosure/unwind. This is not permission to detach
/// an opaque raw cause or stringify the entire source without a new proof.
fn closed_values_compiler_failure_layout(
  depth_upper : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard closed_values_append_capacity(depth_upper) is Some(capacity) else {
    return None
  }
  let d = depth_upper.to_int64()
  Some({
    record_headers: 48L + 4L * d,
    reference_slots: 70L + 4L * capacity + 4L * d,
    scalar_words: 42L + 8L * d,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Complete compiler-owned additive phase envelope for the original guarded
/// shape. It excludes the separately owned source/indexed syntax, context,
/// normalization and installed catalog dependencies; the driver combines those
/// before constructors under the SAME original preparation token. These facts
/// are internal projections of the original Cursor guard, never caller grants.
///
/// Fixed nonrecursive implementation frames belong to model-A runtime baseline.
/// Allocated records/arrays, input-dependent sort frames and failure carriers
/// do not. Lower/DAG temporaries are bounded by two complete lowering graphs
/// plus one DAG graph: original owners/stages/split arrays, used-name Map,
/// identifier concatenation, binding tuples/Results and accessor Options. The
/// original and copied tables are included even where constructor scopes do not
/// overlap. One extra pipeline graph bounds typed_rows temporary schema Fields,
/// evidence predecessors and their empty maps. Two wrapper inventories cover
/// checker limit collectors and old/new outer tables. No body-sized string copy
/// or encoded row wire is introduced by this shape's compiler.
fn closed_values_compiler_phase_layout(
  fields : Int,
  rows : Int,
  node_upper : Int,
  longest_name : Int,
  depth_upper : Int,
) -> ClosedValuesCompilerPhaseLayout? {
  if longest_name < 0 ||
    depth_upper < 0 ||
    depth_upper > node_upper ||
    fields > node_upper {
    return None
  }
  guard closed_values_literal_layout(fields, rows) is Some(literal) else {
    return None
  }
  if literal.cell_count > node_upper.to_int64() {
    return None
  }
  guard closed_values_pipeline_retained_layout(fields) is Some(pipeline) else {
    return None
  }
  let wrappers = closed_values_program_wrappers_layout()
  let lower = closed_values_lower_retained_layout()
  let dag = closed_values_dag_retained_layout()
  guard closed_values_result_port_retained_layout(fields) is Some(port) else {
    return None
  }
  // Original SequencePreparationDemand: three scalar fields plus its one
  // PreparedClientProgram reference. This is not an output cardinality claim.
  let demand : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 1L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // One lower demand record/Ok, composition Ok, and two error carriers.
  // Both branches are summed; the actual node scan allocates no collection.
  let demand_scratch : @execution.PreparationRepresentationUnits = {
    record_headers: 5L,
    reference_slots: 4L,
    scalar_words: 7L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      literal.retained,
      pipeline,
      wrappers,
      lower,
      dag,
      port,
      demand,
    ])
    is Some(retained) else {
    return None
  }
  let widest = Int::max(fields, 3)
  guard closed_values_guarded_walk_storage_layout(fields, rows) is Some(walk) else {
    return None
  }
  guard closed_values_map_constructor_layout(widest) is Some(map) else {
    return None
  }
  guard closed_values_values_caller_scratch_layout(fields, rows) is Some(caller) else {
    return None
  }
  guard closed_values_sort_scratch_layout(fields) is Some(sort) else {
    return None
  }
  guard closed_values_result_scratch_layout(fields, longest_name)
    is Some(result) else {
    return None
  }
  guard closed_values_map_constructor_layout(1) is Some(used_names) else {
    return None
  }
  // Fixed planner-owned unit descriptors, Options and the four fixed component
  // lists: 34 unit records +32 Option wrappers +one literal-layout record +one
  // phase record +four Array wrappers/backings; list backing slots total37.
  let bookkeeping : @execution.PreparationRepresentationUnits = {
    record_headers: 76L,
    reference_slots: 77L,
    scalar_words: 213L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      walk,
      map,
      caller,
      sort,
      result,
      closed_values_numeric_admission_scratch_layout(),
      closed_values_number_contract_scratch_layout(),
      pipeline,
      wrappers,
      wrappers,
      lower,
      lower,
      dag,
      used_names,
      bookkeeping,
      demand_scratch,
    ])
    is Some(temporary) else {
    return None
  }
  guard closed_values_compiler_failure_layout(depth_upper) is Some(failure) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      retained, temporary, failure,
    ])
    is Some(_) else {
    return None
  }
  Some({ retained, temporary, failure, })
}
