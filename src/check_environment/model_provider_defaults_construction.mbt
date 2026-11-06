///|
/// Constructor kinds of resolve_model_provider_defaults, after its original
/// ModelProviderDefaults has been read. This DATA is not a semantic verdict,
/// physical size, allocator bound, retained original census or Model admission.
///
/// comparison_arrays/items describe one nonescaping three-Int literal, with
/// its existing Array recipe. comparison_array_constructions is the maximum
/// number of visits to that constructor. It is NOT another simultaneously live
/// Array count. A target/allocator that retains dead storage must account for
/// those repeated constructions separately before treating this as funding.
pub(all) struct ModelProviderDefaultsResolutionConstructionInventory {
  resolved_records : Int64
  generation_copies : Int64
  comparison_arrays : Int64
  comparison_items : Int64
  comparison_array_constructions : Int64
  work_cells : Int64
  issue_tags : Int64
  error_results : Int64
  success_results : Int64
} derive(Eq, Debug)

///|
/// Source-constructor envelope for the SAME original profile and Task override.
/// No selection scan or copy of original data is performed by the quotation.
/// A nonempty profile can create one ResolvedModelProviderDefaults (1H4R1W)
/// and, only with an override, one ModelGeneration (1H1R3W). The latter borrows
/// seed_requested, including its existing Some/None. No new Option is created.
///
/// The resolver's mutable work cell is 1H1W. Both Array loops use their existing
/// indexed traversal; tuple bindings, input Option matches, Int/Int64 predicates,
/// String lengths and exact equality create no source-owned child object. VM
/// frames and target lowering are not inferred from these logical quantities.
/// The comparison Array never escapes an iteration or reaches the result.
///
/// Co-count six issue/Err sites: InvalidLimits, InvalidTaskOutputTokens,
/// DefaultUnavailable, both WorkLimit returns and UnknownModel. Each issue tag
/// is 1H1W and each Err carrier is 1H1R1W. The success Ok is also 1H1R1W.
/// These alternatives remain explicit even for early-refusal inputs, without
/// evaluating predicates or claiming every alternative is simultaneously live.
///
/// All input Strings, tuples, original profile/generation/handling and Option
/// bodies stay borrowed and must remain charged by their original owner. JSON
/// or YAML parsing, profile admission, Task normalization/emission, Contract,
/// Value/Json/Vector/reference construction and Native layout are not covered.
/// This quotation itself constructs one nine-scalar DATA record (1H9W); its
/// caller must fund that separately. It changes no existing allocation path.
pub fn model_provider_defaults_resolution_construction_inventory(
  original : ModelProviderDefaults,
  task_max_output_tokens : Int64?,
) -> ModelProviderDefaultsResolutionConstructionInventory {
  let populated = original.models.length() != 0
  {
    resolved_records: if populated {
      1L
    } else {
      0L
    },
    generation_copies: if populated && task_max_output_tokens is Some(_) {
      1L
    } else {
      0L
    },
    comparison_arrays: if populated {
      1L
    } else {
      0L
    },
    comparison_items: if populated {
      3L
    } else {
      0L
    },
    comparison_array_constructions: original.models.length().to_int64(),
    work_cells: 1L,
    issue_tags: 6L,
    error_results: 6L,
    success_results: 1L,
  }
}

///|
/// Owned bodies reachable from a successful resolved selection, excluding its
/// caller-owned Ok carrier and every borrowed original. The possible generation
/// copy adds 1H1R3W to the resolution's 1H4R1W. No success exists for an empty
/// profile. This is an envelope, not validation of a model/override or evidence
/// of release. In particular the original generation remains charged beside
/// its override copy, even when their scalar values happen to be equal.
/// The returned quotation descriptor itself is a separate 1H3W constructor.
pub fn model_provider_defaults_resolution_retained_extent(
  original : ModelProviderDefaults,
  task_max_output_tokens : Int64?,
) -> @shape.CollectionConstructionExtent {
  if original.models.is_empty() {
    return { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  }
  if task_max_output_tokens is Some(_) {
    { record_headers: 2L, reference_slots: 5L, scalar_words: 4L, }
  } else {
    { record_headers: 1L, reference_slots: 4L, scalar_words: 1L, }
  }
}
