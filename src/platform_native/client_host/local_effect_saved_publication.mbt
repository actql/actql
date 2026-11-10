///|
pub(all) enum NativeLocalSavedEffectPublicationIssue {
  Original(NativeLocalInitialHostAttestationIssue)
  Journal(NativeClientRunJournalIssue)
  Service(@native_publication.NativeRunPublicationIssue)
  Construction
  Publisher(NativeLocalPublisherBindingIssue)
}

///|
// Closed receipt emitters add scalar CID/ordinal/state fields, not arbitrary
// provider JSON. Preserve the original receipt's encoder usage and count the
// appended member/row/final controls separately from their wire bytes.
fn saved_effect_publication_geometry(
  receipt_usage : (Int, Int, Int),
  schema_usage : (Int64, Int64, Int, Int64),
  rows : Int64,
  members : Int,
  results : Int,
  limits : @checkpoint.WireLimits,
) -> (Int, Int, Int)? {
  let (receipt_bytes, receipt_nodes, receipt_depth) = receipt_usage
  let (schema_wire_bytes, schema_nodes, schema_depth, schema_fields) = schema_usage
  if receipt_bytes < 1 ||
    receipt_nodes < 1 ||
    receipt_depth < 1 ||
    schema_wire_bytes < 0L ||
    schema_nodes < 0L ||
    schema_depth < 0 ||
    schema_fields < 0L ||
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
      receipt_bytes.to_int64(),
      1L,
    )
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, schema_wire_bytes, 1L)
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
    @execution.checked_preparation_add_product(nodes, schema_nodes, 1L)
    is Some(nodes) &&
    @execution.checked_preparation_add_product(nodes, schema_fields, 2L)
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
  // small but sufficient node/depth limit. The same final encoder already
  // counted escaping: encoded document bytes are not escaped a second time.
  Some(
    (
      bytes.to_int(),
      Int64::min(nodes, limits.max_nodes.to_int64()).to_int(),
      Int::min(
        limits.max_depth,
        Int::max(4, Int::max(receipt_depth, schema_depth)),
      ),
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
    publisher.authority.capture is Some(capture) &&
    physical_equal(capture, read.owner.capture) &&
    publisher.journal_operation is Some(_) &&
    physical_equal(publisher.store, store) &&
    publisher.request == self.request &&
    publisher.namespace_id == namespace_id &&
    @publication.publication_contract_identity(publisher.definition) ==
    @publication.publication_contract_identity(
      original.materials.run_definition,
    ) else {
    return Err(Construction)
  }
  let live = () => {
    self
    .application_original_in_original_read()
    .map(_ => ())
    .map_err(issue => NativeLocalSavedEffectPublicationIssue::Original(issue))
  }
  let current = () => {
    publisher.with_original_journal_read((host, _) => {
      if !physical_equal(host, self.host) {
        return Err(SelectionMismatch)
      }
      Ok(self.authority_current(publication=Some(publisher)))
    })
    is Ok(true)
  }
  install_native_client_work_publication_service(
    self.host.journal,
    self.request,
    original.materials.run_definition,
    current,
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
      publisher
      .with_original_journal_read((host, operations) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        host.journal
        .bind_publication(
          self.request,
          binding,
          current,
          operations=Some(operations),
        )
        .map_err(issue => Journal(issue))
      })
      .map_err(issue => NativeLocalSavedEffectPublicationIssue::Publisher(issue))
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
      let captured = publisher.with_original_journal_read((host, operations) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        match
          host.journal.fence_publication_outcome(
            self.request,
            original.materials.run_definition,
            binding,
            current,
            () => publisher.with_original_store_commit(commit),
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
    original.definitions.length() != original.schema_originals.length() ||
    original.definitions.length() != original.codec_cids.length() {
    return Err(Construction)
  }
  let members = @publication.effect_preview_member_count(original.preview)
  let results = original.definitions.length()
  let mut schema_wire_bytes = 0L
  let mut schema_nodes = 0L
  let mut schema_depth = 0
  let mut schema_fields = 0L
  for index in 0..<original.schema_originals.length() {
    let schema = original.schema_originals[index]
    guard @publication.captured_effect_dependency_body_wire_usage(schema)
      is Some((schema_bytes, nodes, depth)) &&
      @publication.captured_effect_dependency_body_field_count(schema)
      is Some(fields) &&
      @publication.captured_effect_dependency_body_json(schema) ==
      original.schema_wires[index] &&
      @execution.checked_preparation_add_product(
        schema_nodes,
        nodes.to_int64(),
        1L,
      )
      is Some(next_nodes) &&
      @execution.checked_preparation_add_product(
        schema_fields,
        fields.to_int64(),
        1L,
      )
      is Some(next_fields) else {
      return Err(Construction)
    }
    schema_nodes = next_nodes
    schema_fields = next_fields
    schema_depth = Int::max(schema_depth, depth)
    guard @execution.checked_preparation_add_product(
        schema_wire_bytes,
        schema_bytes.to_int64(),
        1L,
      )
      is Some(next) else {
      return Err(Construction)
    }
    schema_wire_bytes = next
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
      (schema_wire_bytes, schema_nodes, schema_depth, schema_fields),
      rows,
      members,
      results,
      original.wire_limits,
    )
    is Some((bytes, nodes, depth)) else {
    return Err(Construction)
  }
  let bound = bytes.to_int64()
  let semantic = match
    @local.installed_effect_contract_response_construction_capacity(
      bytes, nodes, depth,
    ) {
    Some(value) => value
    None => return Err(Construction)
  }
  let mut snapshot_nodes = 1
  let mut snapshot_depth = 1
  let mut snapshot_chunk_bytes = 1
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
    let (b, n, d) = @publication.captured_result_snapshot_payload_extent(
      snapshot,
    )
    snapshot_nodes = Int::max(snapshot_nodes, n)
    snapshot_depth = Int::max(snapshot_depth, d)
    snapshot_chunk_bytes = Int::max(snapshot_chunk_bytes, Int::min(65536, b))
  }
  // Same original payload size bounds each actual stream chunk. Receipt
  // emitters use the closed wire envelope; retain old/new builders, returned
  // text, UTF8 chunk and the SHA/Store writer concurrently.
  let writer_bytes = Int::max(bytes, snapshot_chunk_bytes)
  guard @encode.text_writer_construction_inventory(
      writer_bytes,
      Int::max(nodes, snapshot_nodes),
      Int::max(depth, snapshot_depth),
    )
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers +
      // Additional current callback/Some/Result and routing-exchange frames.
      // The outcome and routing-issue Some values can coexist after a lost
      // reentry: 2H2R plus their two fields, with no copied Result strings.
      // Final Saved-state CAS: retained-current closure1H3R1W, selected
      // route/result and return frames4H5R1W. Original state/IDs are borrowed.
      119L +
      12L * rows +
      16L * results.to_int64(),
      reference_slots: writer.reference_slots +
      428L +
      32L * rows +
      48L * results.to_int64(),
      scalar_words: writer.scalar_words +
      210L +
      16L * rows +
      24L * results.to_int64(),
      owned_utf16_units: writer.owned_utf16_units + bound,
      owned_wire_bytes: snapshot_chunk_bytes.to_int64(),
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
      writer_bytes,
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
  // The opaque observation already retains the original publisher. Borrow
  // its same bound Journal route for this final Submission-state CAS too;
  // the Store commit alone cannot supply a Saved-state acknowledgement.
  guard physical_equal(observed.host, self.host) &&
    observed.request == self.request &&
    observed.publisher.authority.capture is Some(capture) &&
    physical_equal(capture, read.owner.capture) &&
    observed.publisher.journal_operation is Some(_) else {
    return Err(Construction)
  }
  observed.publisher
  .with_original_journal_read((host, _) => {
    if !physical_equal(host, self.host) {
      return Err(SelectionMismatch)
    }
    capture
    .retain_observed_run_state_in_original_read(
      self.principal,
      self.connection,
      self.reference,
      self.request,
      observed,
      now,
    )
    .map_err(issue => NativeLocalPublisherBindingIssue::Adoption(issue))
  })
  .map_err(issue => NativeLocalSavedEffectPublicationIssue::Publisher(issue))
}
