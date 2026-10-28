///|
// Same original wrappers and completed body quantity survive failed grow. This
// cache owns no Resource, policy or semantic verdict; clear drops aliases only.
priv struct LocalSnapshotBatchConstruction {
  members : Array[@environment.Member]
  inventory : @snapshot.MemberReadConstructionInventory?
}

///|
fn local_snapshot_original_member(
  read : LocalEnvironmentPreparation,
  original : LocalEnvironmentArguments,
  index : Int,
) -> @environment.Member {
  match read.snapshot_batch {
    Some(batch) => batch.members[index]
    None =>
      @environment.member_at(
        original.environment,
        @environment.SchemaSnapshots,
        index,
      ).unwrap()
  }
}

///|
/// O(1) actual admitted input geometry bounds one metadata pass. This is not
/// parse/schema work or a policy ceiling; no semantic body is read here.
pub fn local_environment_snapshot_batch_inspection_bound(
  read : LocalEnvironmentPreparation,
) -> Int64? {
  guard read.state is ReadSnapshot(0) && read.arguments is Some(original) else {
    return None
  }
  let (_, nodes, _) = @environment.usage(original.environment)
  Some(7L * nodes.to_int64() + 6L * read.members.to_int64() + 1L)
}

///|
// All wrappers plus their original reference Array survive observation. The
// inventory/Some, peak/retained records, private cache/Some add6H6R13W. The
// shared Array recipe includes old/new growth; no input bodies are copied.
fn local_snapshot_batch_metadata_extent(
  read : LocalEnvironmentPreparation,
) -> @shape.CollectionConstructionExtent {
  let n = read.members.to_int64()
  let selected = @environment.member_instance_construction_extent()
  @shape.collection_construction_extent({
    records: selected.record_headers * n + 6L,
    record_references: selected.reference_slots * n + 6L,
    record_words: selected.scalar_words * n + 13L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
}

///|
/// Peak of one sequential inventory call, the full retained original wrapper
/// inventory and fixed fold/access controls. Never multiply the quote frame
/// by Member count or quote by limits.max_members.
pub fn local_environment_snapshot_batch_inspection_extent(
  read : LocalEnvironmentPreparation,
) -> @shape.CollectionConstructionExtent? {
  guard read.state is ReadSnapshot(0) else { return None }
  let quote = @snapshot.member_read_construction_inspection_extent()
  let retained = local_snapshot_batch_metadata_extent(read)
  let access = @environment.member_access_construction_extent()
  // Two fold joins22H4R52W; work Some1H2W; four simultaneously
  // selected extent records4H20W; two shape inputs2H6W; inventory/Some2H3R2W;
  // cache/Some2H3R1W; bound Some1H2W; loop/result carriers3H3R4W.
  Some({
    record_headers: quote.record_headers +
    retained.record_headers +
    access.record_headers +
    37L,
    reference_slots: quote.reference_slots +
    retained.reference_slots +
    access.reference_slots +
    13L,
    scalar_words: quote.scalar_words +
    retained.scalar_words +
    access.scalar_words +
    89L,
  })
}

///|
pub fn local_environment_snapshot_batch_retained_extent(
  read : LocalEnvironmentPreparation,
) -> @shape.CollectionConstructionExtent? {
  guard read.state is ReadSnapshot(0) else { return None }
  Some(local_snapshot_batch_metadata_extent(read))
}

///|
/// One completed observation on the SAME originals. Repeats return the stored
/// Option without rewalking fields or constructing wrappers. This precedes
/// the single whole-batch body work interval; it cannot admit a Snapshot.
pub fn observe_local_environment_snapshot_batch_construction(
  read : LocalEnvironmentPreparation,
) -> @snapshot.MemberReadConstructionInventory? {
  guard read.state is ReadSnapshot(0) && read.arguments is Some(original) else {
    return None
  }
  if read.snapshot_batch is Some(completed) {
    return completed.inventory
  }
  let members : Array[@environment.Member] = []
  for i in 0..<read.members {
    let selected = if i == 0 && read.snapshot_construction is Some(captured) {
      captured.original_member
    } else {
      @environment.member_at(
        original.environment,
        @environment.SchemaSnapshots,
        i,
      ).unwrap()
    }
    members.push(selected)
  }
  let inventory = @snapshot.member_batch_read_construction_inventory(members)
  read.snapshot_batch = Some({ members, inventory, })
  inventory
}

///|
/// Original grouping Arrays already have their empty growth envelope backed.
/// Only3 reference slots per selected appended item are added here; no second
/// Array-header inventory. The last success allocates the original empty Stage
/// Array/Some. Typed bodies and all earlier returned Snapshots coexist.
pub fn local_environment_snapshot_batch_body_construction(
  read : LocalEnvironmentPreparation,
) -> @snapshot.MemberReadConstructionInventory? {
  guard read.snapshot_batch is Some(batch) && batch.inventory is Some(body) else {
    return None
  }
  let appended_slots = 3L * read.members.to_int64()
  let peak = body.peak
  let retained = body.retained
  Some({
    peak: {
      ..peak,
      record_headers: peak.record_headers + 4L,
      reference_slots: peak.reference_slots + appended_slots + 14L,
      scalar_words: peak.scalar_words + 3L,
    },
    retained: {
      ..retained,
      record_headers: retained.record_headers + 4L,
      reference_slots: retained.reference_slots + appended_slots + 14L,
      scalar_words: retained.scalar_words + 3L,
    },
    inspection_work: body.inspection_work + read.members.to_int64(),
  })
}
