///|
// These constructors describe QUOTATION, not the parser/writer/tree that a
// quote describes. Build and price this immutable packet during module load,
// before any request. Request entry only reads three scalar values and asks
// its original Read to retain their backing; no quote funds itself.
fn static_plan_quote_units(
  h : Int64,
  r : Int64,
  w : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn static_plan_quote_sum(
  values : Array[@execution.PreparationRepresentationUnits],
) -> @execution.PreparationRepresentationUnits {
  @execution.compose_preparation_representation(values).unwrap()
}

///|
fn static_plan_quote_repeat(
  value : @execution.PreparationRepresentationUnits,
  n : Int64,
) -> @execution.PreparationRepresentationUnits {
  static_plan_quote_units(
    value.record_headers * n,
    value.reference_slots * n,
    value.scalar_words * n,
  )
}

///|
// compose_preparation_representation: five checked Some sums/member, one
// five-word Unit, the five-field tariff and the final Some. Literal arrays
// are explicitly separate (wrapper/backing2H, n+1 references,2 words).
fn static_plan_compose_quote(
  n : Int64,
) -> @execution.PreparationRepresentationUnits {
  static_plan_quote_units(5L * n + 7L, 1L, 10L * n + 16L)
}

///|
let static_plan_collection_quote : @execution.PreparationRepresentationUnits = {
  let v = @shape.collection_construction_quotation_extent()
  static_plan_quote_units(v.record_headers, v.reference_slots, v.scalar_words)
}

///|
let static_plan_frame_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_quote_units(1L, 0L, 9L), // CollectionConstructionInventory
    static_plan_collection_quote,
  ],
)

///|
let static_plan_hash_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_frame_quote,
    static_plan_frame_quote, // sink collection input + expansion, same signature
    static_plan_quote_units(5L, 1L, 10L), // add_collection_construction_extents
    static_plan_quote_units(2L, 1L, 6L), // HashWriter inventory + Some
  ],
)

///|
let static_plan_text_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_frame_quote,
    static_plan_quote_units(2L, 1L, 5L), // TextWriter inventory + Some
  ],
)

///|
let static_plan_codec_quote : @execution.PreparationRepresentationUnits = {
  // program_artifact_parse_layout includes Source grammar20H5R46W (the
  // original Source/index quotation family), canonical36H9R80W, borrowed
  // index2H1R5W, and caller50H13R111W: structural tuple, canonical shape,
  // string-node Some, two Units, literal2/3 arrays, compose2/3 and result.
  let parse = static_plan_quote_units(108L, 28L, 242L)
  static_plan_quote_sum([
    static_plan_quote_units(5L, 0L, 10L), // validator tariff
    parse,
    static_plan_quote_units(7L, 1L, 16L), // canonical emitter Unit/tariff/Some
    static_plan_hash_quote,
    static_plan_text_quote,
    static_plan_quote_units(2L, 1L, 6L), // pinned sort layout Unit/Some
    static_plan_frame_quote, // root-copy collection input + expansion
    static_plan_quote_units(5L, 0L, 25L), // root/strings/result/hash/text Units
    static_plan_quote_units(4L, 13L, 4L), // literal arrays4 and7
    static_plan_compose_quote(4L),
    static_plan_compose_quote(7L),
    static_plan_quote_units(1L, 0L, 1L), // map-bucket Some
    static_plan_quote_units(2L, 3L, 7L), // CodecLayout and Some
  ])
}

///|
let static_plan_validator_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_frame_quote, // validation collection input and expansion
    static_plan_quote_units(1L, 0L, 3L), // extra fixed collection extent
    static_plan_quote_units(5L, 1L, 10L), // add collections
    static_plan_quote_units(2L, 2L, 10L), // validator construction/Some
  ],
)

///|
let static_plan_presence_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    // Six Collection extents; names input+expansion; literal array6;
    // six add_collection calls; returned RelationSchemaMeasurementControls.
    static_plan_quote_units(6L, 0L, 18L),
    static_plan_frame_quote,
    static_plan_quote_units(2L, 7L, 2L),
    static_plan_quote_repeat(static_plan_quote_units(5L, 1L, 10L), 6L),
    static_plan_quote_units(1L, 1L, 3L),
  ],
)

///|
let static_plan_carrier_variable_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    // Measuring writer: frame, finish input/expansion, add; copied collections;
    // add; checked-emission input/expansion; add; final layout and Some.
    static_plan_frame_quote,
    static_plan_frame_quote,
    static_plan_quote_units(5L, 1L, 10L),
    static_plan_frame_quote,
    static_plan_quote_units(5L, 1L, 10L),
    static_plan_frame_quote,
    static_plan_quote_units(5L, 1L, 10L),
    static_plan_quote_units(2L, 3L, 7L),
  ],
)

///|
let static_plan_carrier_measurement_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_carrier_variable_quote,
    static_plan_quote_units(2L, 1L, 7L), // measurement operation+collection
    static_plan_quote_units(5L, 1L, 10L), // add operation
    static_plan_presence_quote,
    static_plan_quote_units(5L, 1L, 10L), // add Presence
    static_plan_quote_units(1L, 0L, 5L), // Unit conversion
    static_plan_quote_units(4L, 2L, 12L), // two sort layout/Some
    static_plan_quote_units(2L, 4L, 2L),
    static_plan_compose_quote(3L),
    static_plan_quote_units(5L, 0L, 10L), // tariff
    static_plan_quote_units(1L, 0L, 1L), // bucket Some
    static_plan_quote_units(4L, 1L, 14L), // raw scalar array/tuple/Some
    static_plan_quote_units(2L, 1L, 4L), // result tuple/Some
  ],
)

///|
let static_plan_carrier_codec_quote : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_carrier_variable_quote,
    static_plan_hash_quote,
    static_plan_quote_units(2L, 1L, 7L), // measurement operation+collection
    static_plan_quote_units(1L, 0L, 5L), // scratch Unit
    static_plan_text_quote,
    static_plan_frame_quote, // names collection
    static_plan_presence_quote,
    static_plan_quote_units(1L, 0L, 5L), // Presence Unit
    static_plan_quote_units(2L, 3L, 2L),
    static_plan_compose_quote(2L),
    static_plan_quote_units(4L, 2L, 12L), // two sort layout/Some
    static_plan_quote_units(2L, 4L, 2L),
    static_plan_compose_quote(3L),
    static_plan_quote_units(1L, 0L, 1L), // bucket Some
    static_plan_quote_units(1L, 0L, 5L), // retained Unit
    static_plan_quote_units(2L, 3L, 7L), // layout/Some
  ],
)

///|
// Core quote results remain live together. Four codec roles and seven schema
// profiles are the actual fresh issuer call graph (step/port/map body+sealed,
// view sealed). Cold uses fewer codec roles; it keeps its independent arbitrary
// schema validation and binding scans, never the fresh schema assumption.
let static_plan_quote_controls : @execution.PreparationRepresentationUnits = static_plan_quote_sum([
    static_plan_quote_repeat(static_plan_codec_quote, 4L),
    static_plan_quote_repeat(static_plan_validator_quote, 7L),
    // Projection: collection, quote writer, sixteen checked String joins,
    // three Unit records, three tariffs, five layout/count pairs + array,
    // five iterations of two tariffs and checked product, two final sums,
    // two bucket Options, final five-element array, layout/Some.
    static_plan_frame_quote,
    static_plan_text_quote,
    static_plan_quote_units(16L, 0L, 32L),
    static_plan_quote_units(3L, 0L, 15L),
    static_plan_quote_units(15L, 0L, 30L),
    static_plan_quote_units(7L, 11L, 7L),
    static_plan_quote_units(55L, 0L, 110L),
    static_plan_quote_units(4L, 0L, 6L),
    static_plan_quote_units(2L, 6L, 2L),
    static_plan_quote_units(2L, 1L, 9L),
    static_plan_carrier_measurement_quote,
    static_plan_carrier_codec_quote,
    // Cold local wrappers, separately from their tree/scanner owners: six
    // Unit arguments, ParseLimits, geometry and preflight/geometry pair, two
    // defer closures, compose6 input Array, common tariff/compose/raw helpers,
    // and distinct success/refusal wrappers. These co-count sequential routes.
    static_plan_quote_units(6L, 0L, 30L),
    static_plan_quote_units(1L, 0L, 3L),
    static_plan_quote_units(2L, 2L, 3L),
    static_plan_quote_units(2L, 2L, 0L),
    static_plan_quote_units(2L, 7L, 2L),
    static_plan_compose_quote(6L),
    static_plan_quote_units(10L, 0L, 20L), // two additional tariffs
    static_plan_quote_units(16L, 16L, 16L), // typed return alternatives
    static_plan_quote_units(2L, 2L, 2L), // empty-map borrowed zero-layout Options
    // Fresh adapter: four validator Units, three optional bodies; prior+next
    // Carrier maxima; original/captured/Ok holders and temporary identity.
    static_plan_quote_units(7L, 3L, 20L),
    static_plan_quote_units(8L, 8L, 24L),
    static_plan_quote_units(4L, 10L, 0L),
    // Native converter: input scalar array6, bootstrap tuple, returned pair
    // of Some+tuple, tariff, checked-addition and typed refusal alternatives.
    static_plan_quote_units(12L, 5L, 42L),
  ],
)

///|
let static_plan_quote_control_bytes : Int64 = @execution.preparation_representation_cost({
    ..static_plan_quote_controls,
    // Some quoted source families include discriminator words and others list
    // only payload fields. At most one tag exists per named allocated record;
    // charge that upper bound uniformly, including untagged struct records.
    scalar_words: static_plan_quote_controls.scalar_words +
    static_plan_quote_controls.record_headers,
  },
).unwrap()

///|
let static_plan_quote_raw : Int64 = {
  let (header, _, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  // Largest fixed literal quote array has7 elements, bounded by the same
  // pinned growth owner12+3N; largest record is geometry8R11W. Co-counting
  // eight references and fifteen words also covers the named sort controls.
  Int64::max(
    array_header + (12L + 3L * 7L) * pointer,
    header + 8L * pointer + 15L * 8L,
  )
}

///|
fn native_prepare_static_plan_quote_controls(
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[Unit, NativeClientRunJournalIssue] {
  // Keep the quote forest conservatively until the original Read ends. Later
  // construction quotes therefore cannot erase its overlapping retained cost.
  reserve(
    static_plan_quote_control_bytes, static_plan_quote_control_bytes, static_plan_quote_raw,
  )
}

///|
// Ten explicitly named writers in measure_client_static_plan_view. live_keys
// is the sum of open object keys, NOT nodes or the policy node ceiling. Child
// geometry uses emit_measurement and creates no child container or key Map.
let static_plan_measurement_writer_units : @execution.PreparationRepresentationUnits = {
  let mut total = static_plan_quote_units(0L, 0L, 0L)
  for
    (keys, depth) in [
      (0, 1), // all_steps
      (7, 2), // step_key (root5 + occurrence2)
      (0, 1), // ports
      (6, 1), // port_key
      (11, 2), // port (root8 + source3)
      (0, 1), // names
      (8, 1), // step item
      (4, 1), // map body
      (5, 1), // sealed map
      (15, 3), // view(root7 + capabilities8); quantities has only3
    ] {
    let v = @encode.measuring_writer_construction_extent(keys, depth).unwrap()
    total = static_plan_quote_sum([
      total,
      static_plan_quote_units(
        v.record_headers,
        v.reference_slots,
        v.scalar_words,
      ),
    ])
  }
  let operation = @encode.measurement_operation_construction_extent()
  static_plan_quote_sum([
    total,
    {
      record_headers: operation.collections.record_headers,
      reference_slots: operation.collections.reference_slots,
      scalar_words: operation.collections.scalar_words,
      owned_utf16_units: operation.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    // Geometry record8R11W, eight retained triples and outer Ok. Prior/new
    // maxima five triples are counted beside those returned results.
    static_plan_quote_units(1L + 8L + 1L + 10L, 9L, 11L + 24L + 30L),
    // Source occurrence alternatives: unit pipeline/step/input Options,
    // pair+Some for input/carrier, carrier+source pair and source Some,
    // field_at pair+Some, operator and binding Options, quoted extent pair
    // and Some. These are shallow borrowed observations, no copied array.
    static_plan_quote_units(
      3L + 2L + 2L + 2L + 2L + 2L,
      3L + 3L + 2L + 3L + 2L + 1L,
      1L + 2L,
    ),
    // Fresh callback: selected-policy triple, two Ref cells, captured closure,
    // optional closure, failure Some+Err, no-capture map_err closure and Err.
    static_plan_quote_units(
      1L + 2L + 1L + 1L + 2L + 1L + 1L,
      2L + 3L + 1L + 2L + 1L,
      3L + 1L,
    ),
    // Pre-carrier name extent scan: reference_parts pair, two collection
    // extents and SchemaConstructionInventory. No spelling is constructed.
    static_plan_quote_units(4L, 4L, 14L),
    // Source selection: relation_rows, complete_schema and as_object Options,
    // map closure and mapped result; Record selection's two borrowed Options.
    static_plan_quote_units(7L, 7L, 0L),
    // Graph scan borrows node, edge, key, label and label/property Field
    // inventories through six distinct indexed Option sites. No array copy
    // or label tuple is created by those accessors.
    static_plan_quote_units(6L, 6L, 6L),
    // Carrier scanner1H1R9W and returned Construction+Some1R11W; source
    // branch shells co-count Graph8H9R5W,Object4H5R,Record6H8R.
    static_plan_quote_units(
      1L + 2L + 8L + 4L + 6L,
      1L + 2L + 9L + 5L + 8L,
      9L + 11L + 5L,
    ),
  ])
}

///|
let static_plan_measurement_control_bytes : Int64 = @execution.preparation_representation_cost({
    ..static_plan_measurement_writer_units,
    scalar_words: static_plan_measurement_writer_units.scalar_words +
    static_plan_measurement_writer_units.record_headers,
  },
).unwrap()

///|
// checked_emission_geometry's input-dependent recursion: argument+parent
// child/field references, six accumulators/index slots, one returned geometry
// record and its Some plus field Some. Count parent and returned child overlap.
// Depth is enforced BEFORE recursive descent; it is not merely a later writer
// refusal. Fixed nonrecursive runtime frames are not duplicated here.
let static_plan_geometry_frame_bytes : Int64 = @execution.preparation_representation_cost(
  static_plan_quote_units(4L, 6L, 13L),
).unwrap()

///|
fn native_prepare_static_plan_measurement(
  prepared : @host.PreparedClientProgram,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[Unit, NativeClientRunJournalIssue] {
  match native_prepare_static_plan_quote_controls(reserve) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (_, _, depth) = @host.prepared_client_artifact_limits(prepared)
  if depth < 1 {
    return Err(CapacityExceeded)
  }
  // Int depth times this fixed frame is safely below Int64.MAX. Quote DATA
  // cannot alter the selected depth or supply capacity; reserve decides.
  let cost = static_plan_measurement_control_bytes +
    depth.to_int64() * static_plan_geometry_frame_bytes
  reserve(cost, cost, static_plan_quote_raw)
}
