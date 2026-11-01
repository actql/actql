///|
/// Construction DATA for the existing Parameter-supported Value body. The
/// caller keeps the original admitted ParameterType and its default Cursor;
/// these quantities do not check either, authorize a read, reserve resources
/// or describe Json/Vector/reference/authored-field admission. The complete
/// Value phase adds entry/indexed/refusal controls; its caller still adds its
/// own metadata, Parameter constraints and declaration construction.
pub(all) struct ParameterValueBodyConstructionInventory {
  values : @shape.CollectionConstructionInventory
  traversal : @shape.CollectionConstructionInventory
  value_extent : @shape.CollectionConstructionExtent
  traversal_extent : @shape.CollectionConstructionExtent
  decimal_scratch : @shape.CollectionConstructionExtent
  owned_value_utf16_units : Int64
  owned_decimal_scratch_utf16_units : Int64
  key_normalization : @canonical.NormalizationConstructionExtent?
} derive(Eq, Debug)

///|
// Inspect only the original checked type, never its syntax or default value.
// Its actual declaration reader alone owns constraints and precision law.
// The caller backs this bounded metadata stack before requesting the inventory.
// Json, Vector and reference constructors have different inventories.
fn value_body_contract_precision(original : @contract.Contract) -> Int? {
  let pending = [original]
  let mut largest = 0
  while pending.pop() is Some(current) {
    match current.shape {
      @contract.Decimal(precision~, ..) =>
        largest = Int::max(largest, precision)
      @contract.Array(item, ..) => pending.push(item)
      @contract.Object(fields) =>
        for index in 0..<@contract.field_count(fields) {
          pending.push(@contract.field_at(fields, index).unwrap().contract)
        }
      @contract.Text(_)
      | @contract.Number
      | @contract.Boolean
      | @contract.Timestamp
      | @contract.Date
      | @contract.Signed64 => ()
      _ => return None
    }
  }
  Some(largest)
}

///|
/// Constructor DATA from the SAME admitted non-reference Contract. No
/// ParameterType, syntax/default reader or replacement Contract is created.
/// Geometry quantities can describe an observed subtree or an independently
/// justified construction envelope; this function attests neither source nor
/// bound. The caller funds metadata inspection before entry and retains the
/// original input/Contract while its actual admission enforces the bounds.
/// Json, Vector and reference admission need their own original inventories.
pub fn contract_value_body_construction_inventory(
  original : @contract.Contract,
  geometry : @decode.SubtreeConstructionGeometry,
) -> ParameterValueBodyConstructionInventory? {
  guard parameter_value_body_geometry_valid(geometry) &&
    value_body_contract_precision(original) is Some(precision) else {
    return None
  }
  parameter_value_body_construction_inventory_owned(precision, geometry)
}

///|
/// The quantity observer reads one original default subtree, not the entire
/// Program's admission_usage or adjacent defaults/meta. It is not another
/// semantic pass. Original input/Contract/name/String backing stays borrowed.
/// All counts below are logical construction peaks, not retained-after-GC or
/// physical supply. The full Parameter phase must add its other live owners.
pub fn parameter_value_body_construction_inventory(
  parameter : @contract.ParameterType,
  geometry : @decode.SubtreeConstructionGeometry,
) -> ParameterValueBodyConstructionInventory? {
  contract_value_body_construction_inventory(parameter.contract, geometry)
}

///|
/// Same constructor inventory using the SAME completed ParameterSyntax's
/// retained Decimal fact. The ordinary declaration continuation already owns
/// this nominal syntax; it needs no new graph walk or caller precision hint.
pub fn parameter_syntax_value_body_construction_inventory(
  original : @contract.ParameterSyntax,
  geometry : @decode.SubtreeConstructionGeometry,
) -> ParameterValueBodyConstructionInventory? {
  if !parameter_value_body_geometry_valid(geometry) {
    return None
  }
  parameter_value_body_construction_inventory_owned(
    @contract.parameter_syntax_maximum_decimal_precision(original),
    geometry,
  )
}

///|
fn parameter_value_body_construction_inventory_owned(
  precision : Int,
  geometry : @decode.SubtreeConstructionGeometry,
) -> ParameterValueBodyConstructionInventory? {
  let g = geometry
  let n = g.nodes.to_int64()
  let a = g.arrays.to_int64()
  let o = g.objects.to_int64()
  let f = g.fields.to_int64()
  let t = if precision == 0 { 0L } else { g.texts.to_int64() }
  let containers = a + o
  // A Value alternative owns at most1H1R2W. A possible Decimal text adds its
  // actual DecimalValue(1H1R2W) and coefficient String header. Only an original
  // checked type containing Decimal selects that bounded alternative envelope;
  // a pure String/Date/Timestamp default borrows its input without such backing.
  // Containers retain FrozenArray(1H1R); each Object output field is the actual
  // (name,Value) pair(1H2R). Builders transfer their SAME growing backing.
  let values : @shape.CollectionConstructionInventory = {
    records: n + 2L * t + containers + f,
    record_references: n + t + containers + 2L * f,
    record_words: 2L * n + 2L * t,
    reference_arrays: containers,
    reference_items: g.array_items.to_int64() + f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  // A live ancestor keeps Next+Append, with one current child frame. There
  // are <=2N+1 retained frames and one popped current frame. The largest
  // Parameter-supported alternative is TypedObjectFind:3R and3 scalars+tag.
  // Each retained child Cursor owns1H2R1W; tree/usage remain original borrows.
  // ArrayBuilder:1H1R2W. Per Object: original typed record1H3R1W,
  // ObjectBuilder1H3R3W and its same-fields Some1H1R1W. Output backing above
  // is not charged a second time. Original child Maps own exactly these keys.
  let frames = 2L * n + 2L
  let traversal : @shape.CollectionConstructionInventory = {
    records: frames + n + a + 3L * o,
    record_references: 3L * frames + 2L * n + a + 7L * o,
    record_words: 4L * frames + n + 2L * a + 5L * o,
    reference_arrays: 1L,
    reference_items: frames - 1L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: o,
    map_entries: f,
  }
  guard @shape.collection_construction_extent(values) is Some(value_extent) &&
    @shape.collection_construction_extent(traversal) is Some(traversal_extent) &&
    @counts.checked_nonnegative_add_product(
      2L,
      Int::min(g.max_text_utf16, precision).to_int64(),
      3L,
    )
    is Some(decimal_units) &&
    @counts.checked_nonnegative_add_product(0L, t, precision.to_int64() + 1L)
    is Some(coefficient_units) else {
    return None
  }
  // Decimal's existing parser stops before writing a significant digit beyond
  // its original checked precision. Final coefficient length is <=P+1 and
  // <=input Text length. Mixed type alternatives may co-count text leaves,
  // but cannot reserve a large borrowed String as a large Decimal coefficient.
  // No duplicate precision ceiling or policy maximum enters this inventory.
  // One Decimal builder runs at a time. Pinned JS concat retains preceding/
  // new digit Strings and the current character; native buffer growth or
  // to_string retains <=3L slots. The final String is already above. Two
  // fixed slots also cover the empty one-slot native buffer/character case.
  // Five headers cover builder + old/new buffers/Strings + current character;
  // two references and one length scalar cover either pinned implementation.
  let decimal_scratch : @shape.CollectionConstructionExtent = if t == 0L {
    { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  } else {
    { record_headers: 5L, reference_slots: 2L, scalar_words: 1L, }
  }
  let key_normalization = if g.fields == 0 {
    None
  } else {
    guard @canonical.nfc_lf_construction_extent(g.max_key_utf16)
      is Some(original) else {
      return None
    }
    Some(original)
  }
  Some({
    values,
    traversal,
    value_extent,
    traversal_extent,
    decimal_scratch,
    owned_value_utf16_units: if g.total_utf16 < coefficient_units {
      g.total_utf16
    } else {
      coefficient_units
    },
    owned_decimal_scratch_utf16_units: if t == 0L {
      0L
    } else {
      decimal_units
    },
    key_normalization,
  })
}

///|
// Preserve the original malformed-geometry boundary before either metadata
// source is consulted. Both public routes use this same closed DATA rule.
fn parameter_value_body_geometry_valid(
  g : @decode.SubtreeConstructionGeometry,
) -> Bool {
  !(g.nodes < 1 ||
  g.arrays < 0 ||
  g.array_items < 0 ||
  g.objects < 0 ||
  g.fields < 0 ||
  g.texts < 0 ||
  g.max_object_fields < 0 ||
  g.max_key_utf16 < 0 ||
  g.max_text_utf16 < 0 ||
  g.total_utf16 < 0L ||
  g.work < 0L ||
  g.arrays.to_int64() + g.objects.to_int64() + g.texts.to_int64() >
  g.nodes.to_int64() ||
  g.array_items.to_int64() + g.fields.to_int64() != g.nodes.to_int64() - 1L ||
  g.max_object_fields > g.fields ||
  g.max_key_utf16.to_int64() > g.total_utf16 ||
  g.max_text_utf16.to_int64() > g.total_utf16)
}
