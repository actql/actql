///|
pub(all) enum NativeLocalSavedEffectPublicationIssue {
  Original(NativeLocalInitialHostAttestationIssue)
  Journal(NativeClientRunJournalIssue)
  Service(@native_publication.NativeRunPublicationIssue)
  Construction
}

///|
// Closed receipt emitters add scalar CID/ordinal/state fields, not arbitrary
// provider JSON. Preserve the original receipt's encoder usage and count the
// appended member/row/final controls separately from their wire bytes.
fn saved_effect_publication_geometry(
  receipt_usage : (Int, Int, Int),
  receipt_text_units : Int,
  schema_text_units : Int64,
  rows : Int64,
  members : Int,
  results : Int,
  limits : @checkpoint.WireLimits,
) -> (Int, Int, Int)? {
  let (receipt_bytes, receipt_nodes, receipt_depth) = receipt_usage
  if receipt_bytes < 1 ||
    receipt_nodes < 1 ||
    receipt_depth < 1 ||
    receipt_text_units < 1 ||
    receipt_text_units > receipt_bytes ||
    schema_text_units < 0L ||
    rows < 0L ||
    members < 1 ||
    results < 0 {
    return None
  }
  // A member row has at most six scalar fields (including its ordinal),
  // beneath the rows array. Thirty-two nodes covers object/key/value controls
  // and the enclosing sealed identity. Set member records have five scalar
  // fields. Final Run receipt adds three scalar CID fields to the SAME old
  // receipt. The extra result/control allowance covers publication bindings.
  // The byte envelope also includes escaping and the existing result wires.
  guard @execution.checked_preparation_add_product(1024L, rows, 800L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, members.to_int64(), 512L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, results.to_int64(), 4096L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(
      bytes,
      receipt_text_units.to_int64(),
      6L,
    )
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, schema_text_units, 6L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(128L, rows, 32L) is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, members.to_int64(), 32L)
    is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, results.to_int64(), 64L)
    is Some(nodes) &&
    @execution.checked_preparation_add_product(
      nodes,
      receipt_nodes.to_int64(),
      1L,
    )
    is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, schema_text_units, 1L)
    is Some(nodes) else {
    return None
  }
  if bytes > limits.max_wire_bytes.to_int64() ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    receipt_nodes > limits.max_nodes ||
    receipt_depth > limits.max_depth {
    return None
  }
  // Every successful existing encoder is also bounded by this SAME policy.
  // A conservative coholding quote must not impose stricter admission on a
  // small but sufficient node/depth limit. Keep the old UTF16 byte envelope.
  Some(
    (
      bytes.to_int(),
      Int64::min(nodes, limits.max_nodes.to_int64()).to_int(),
      limits.max_depth,
    ),
  )
}

///|
/// Install the existing publication service for this SAME resumed Request.
/// Store operations retain their own Read flights; the Journal fence never
/// encloses a whole Store SQLite exchange. No new Request or publisher exists.
pub fn NativeLocalEffectResumeOriginal::install_saved_publication_service_in_original_read(
  self : Self,
  publisher : NativeLocalPublisherBinding,
  store : @publication_store.Store,
  namespace_id : String,
) -> Result[
  @native_publication.NativeRunPublicationService,
  NativeLocalSavedEffectPublicationIssue,
] {
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  guard self.subject is Some(SavedSigningSubject(read)) &&
    physical_equal(publisher.authority.host, self.host) &&
    physical_equal(publisher.store, store) &&
    publisher.request == self.request &&
    publisher.namespace_id == namespace_id &&
    @publication.publication_contract_identity(publisher.definition) ==
    @publication.publication_contract_identity(
      original.materials.run_definition,
    ) else {
    return Err(Construction)
  }
  let capture = read.owner.capture
  let live = () => {
    self
    .application_original_in_original_read()
    .map(_ => ())
    .map_err(issue => NativeLocalSavedEffectPublicationIssue::Original(issue))
  }
  install_native_client_work_publication_service(
    self.host.journal,
    self.request,
    original.materials.run_definition,
    () => self.authority_current(),
    live,
    store,
    namespace_id,
    _ => publisher.current(),
    original.wire_limits.max_wire_bytes,
    original.wire_limits.max_nodes,
    original.wire_limits.max_depth,
    request_authorize=Some((context, facts) => {
      publisher.authorize_request(context, facts)
    }),
    bind_original=Some(binding => {
      capture
      .with_current_adoption_material_in_original_read((
        host,
        _material,
        operations,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(Journal(CustodyLost))
        }
        host.journal
        .bind_publication(
          self.request,
          binding,
          () => self.authority_current(),
          operations=Some(operations),
        )
        .map_err(issue => Journal(issue))
      })
      .map_err(issue => {
        NativeLocalSavedEffectPublicationIssue::Original(
          HostAttestationOriginal(issue),
        )
      })
    }),
    fence_original=Some((binding, commit) => {
      // Retain a real committed/lost reply before the original Read return.
      // An outer return failure is never evidence that commit did not happen.
      let output : Ref[
        Result[
          @native_publication.NativeRunPublicationResult,
          @native_publication.NativeRunPublicationIssue,
        ]?,
      ] = Ref(None)
      let captured = capture.with_current_adoption_material_in_original_read((
        host,
        _material,
        operations,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(Journal(CustodyLost))
        }
        match
          host.journal.fence_publication_outcome(
            self.request,
            original.materials.run_definition,
            binding,
            () => self.authority_current(),
            commit,
            operations=Some(operations),
          ) {
          Ok(value) => {
            output.val = Some(value)
            Ok(())
          }
          Err(issue) => {
            self.issue = Some(issue)
            Err(Journal(issue))
          }
        }
      })
      match captured {
        Ok(_) =>
          output.val.unwrap_or(Err(@native_publication.CommitFenceUnavailable))
        Err(_) => Err(@native_publication.CommitFenceUnavailable)
      }
    }),
  ).map_err(issue => {
    match issue {
      Work(issue) => issue
      Journal(issue) => NativeLocalSavedEffectPublicationIssue::Journal(issue)
      Service(issue) => Service(issue)
    }
  })
}

///|
/// Same original selected limits, not a default or a new policy. Final
/// admission matches these exact limits to the once-retained computation.
pub fn NativeLocalSavedEffectApprovalOriginal::publication_limits(
  self : Self,
) -> @checkpoint.WireLimits {
  self.wire_limits
}

///|
/// Back the finite saved-application publication tail BEFORE any file write.
/// All counts come from the retained original Preview/Results. This adds its
/// new live packet to the already funded Read; it does not reuse a Store quota
/// or the unentered file-execution reservation as constructor capacity.
pub fn NativeLocalEffectResumeOriginal::prepare_saved_publication_construction_in_original_read(
  self : Self,
) -> Result[Unit, NativeLocalSavedEffectPublicationIssue] {
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  guard self.subject is Some(SavedSigningSubject(read)) &&
    read.owner.capture.original_resources is Some(resources) &&
    !resources.interrupted &&
    resources.active_phase is Some(@arena.HostRead) else {
    return Err(Construction)
  }
  if read.owner._retained_publication_construction is Some(previous) {
    return previous
  }
  // Same original Review, one actual publication packet. Reentry and failed
  // construction retain the original refusal instead of debiting a new frame.
  read.owner._retained_publication_construction = Some(Err(Construction))
  if original.definitions.length() != original.derivations.length() ||
    original.definitions.length() != original.orderings.length() ||
    original.definitions.length() != original.retentions.length() ||
    original.definitions.length() != original.schema_wires.length() ||
    original.definitions.length() != original.codec_cids.length() {
    return Err(Construction)
  }
  let members = @publication.effect_preview_member_count(original.preview)
  let results = original.definitions.length()
  let mut schema_text_units = 0L
  for wire in original.schema_wires {
    guard @execution.checked_preparation_add_product(
        schema_text_units,
        wire.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return Err(Construction)
    }
    schema_text_units = next
  }
  let mut rows = 0L
  for member_index in 0..<members {
    guard @publication.effect_preview_row_count(original.preview, member_index)
      is Some(count) &&
      @execution.checked_preparation_add_product(rows, count.to_int64(), 1L)
      is Some(next) else {
      return Err(Construction)
    }
    rows = next
  }
  guard @publication.publication_contract_wire_usage(original.receipt)
    is Some(receipt_usage) &&
    saved_effect_publication_geometry(
      receipt_usage,
      @publication.publication_contract_json(original.receipt).length(),
      schema_text_units,
      rows,
      members,
      results,
      original.wire_limits,
    )
    is Some((bytes, nodes, depth)) else {
    return Err(Construction)
  }
  let bound = bytes.to_int64()
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let semantic = match
    @local.installed_json_effect_response_construction_capacity(
      empty, bytes, nodes, depth,
    ) {
    Some(value) => value
    None => return Err(Construction)
  }
  let mut snapshot_nodes = 1
  let mut snapshot_depth = 1
  for
    index in 0..<@publication.retained_effectful_computation_result_count(
      original.computation,
    ) {
    guard @publication.retained_effectful_computation_result_at(
        original.computation,
        index,
      )
      is Some(snapshot) else {
      return Err(Construction)
    }
    let (_, n, d) = @publication.captured_result_snapshot_payload_extent(
      snapshot,
    )
    snapshot_nodes = Int::max(snapshot_nodes, n)
    snapshot_depth = Int::max(snapshot_depth, d)
  }
  // Existing writer inventory conservatively covers the bounded 64KiB text
  // stream, including old/new builder and returned String. The following
  // UTF8 chunk, SHA/Store writer and canonical cursor coexist with that text.
  guard @encode.text_writer_construction_inventory(
      65536, snapshot_nodes, snapshot_depth,
    )
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers +
      96L +
      12L * rows +
      16L * results.to_int64(),
      reference_slots: writer.reference_slots +
      384L +
      32L * rows +
      48L * results.to_int64(),
      scalar_words: writer.scalar_words +
      192L +
      16L * rows +
      24L * results.to_int64(),
      owned_utf16_units: writer.owned_utf16_units + bound,
      owned_wire_bytes: 65536L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(semantic),
      controls,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(semantic),
      controls,
      1L,
    )
    is Some(execution) else {
    return Err(Construction)
  }
  // Raw backing is a largest individual allocation, never logical R/E.
  // The pinned Native Array backing grows by doubling reference slots;
  // source/contract and emitter arrays contain boxed values or smaller Ints.
  // The existing writer quote covers its UTF16 builder/finish/UTF8 allocation.
  let (_, _, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  let slots = Int64::max(
    nodes.to_int64(),
    snapshot_nodes.to_int64() + snapshot_depth.to_int64() + 1L,
  )
  let array_raw = array_header + (2L * slots + 1L) * pointer
  guard journal_row_construction_working(
      Int::max(bytes, 65536),
      Int::max(nodes, snapshot_nodes),
      Int::max(depth, snapshot_depth),
    )
    is Some((_, _, writer_raw)) else {
    return Err(Construction)
  }
  let old_retained = read.owner._retained_constructor_bytes
  guard @execution.checked_preparation_add_product(old_retained, retained, 1L)
    is Some(whole_retained) &&
    @execution.checked_preparation_add_product(old_retained, execution, 1L)
    is Some(whole_execution) else {
    return Err(Construction)
  }
  // This exact saved owner retains Store/cursors/entry controls alongside the
  // new publication forest. A past temporary Read peak is preserved as a max,
  // not counted as an additional live forest. No prior debit is refunded.
  read.owner._retained_constructor_bytes = whole_retained
  let prepared : Result[Unit, NativeLocalSavedEffectPublicationIssue] = match
    resources.host.prepare_domain_original_read_construction(
      resources.read,
      whole_retained,
      whole_execution,
      Int64::max(array_raw, writer_raw),
    ) {
    Err(issue) =>
      Err(
        Original(HostAttestationOriginal(OriginalResources(@arena.Read(issue)))),
      )
    Ok(_) =>
      if self.retired || !read.owner.saved_approval_original_live(original) {
        Err(Construction)
      } else {
        Ok(())
      }
  }
  read.owner._retained_publication_construction = Some(prepared)
  prepared
}

///|
/// Retain the real publication observation under the SAME submitted reference,
/// Request and epoch. No caller-supplied ID is reconstructed from a public wire.
pub fn NativeLocalEffectResumeOriginal::retain_saved_publication_state_in_original_read(
  self : Self,
  observed : NativeLocalObservedRunState,
  now : Double,
) -> Result[NativeClientSavedRunState, NativeLocalSavedEffectPublicationIssue] {
  guard self.subject is Some(SavedSigningSubject(read)) && !self.retired else {
    return Err(Construction)
  }
  read.owner.capture
  .retain_observed_run_state_in_original_read(
    self.principal,
    self.connection,
    self.reference,
    self.request,
    observed,
    now,
  )
  .map_err(issue => {
    NativeLocalSavedEffectPublicationIssue::Original(
      HostAttestationOriginal(issue),
    )
  })
}
