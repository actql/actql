///|
/// References the original producer-funded preparation and filesystem failure.
/// This private carrier issues no reservation, permission or replacement read.
priv struct HolderEffectCatalogFileCustody {
  original : HolderEffectOriginalPolicyContext
  preparation : @journal.NativeInitialCatalogUseEnvelope
  diagnostic_ceiling : Int
  failure : Ref[@bounded_files.NativeBoundedTextFailure?]
  mut retiring : Bool
}

///|
fn holder_catalog_file_original_matches(
  retained : HolderEffectOriginalPolicyContext,
  proposed : HolderEffectOriginalPolicyContext,
) -> Bool {
  physical_equal(retained.task, proposed.task) &&
  physical_equal(retained.producer_task, proposed.producer_task) &&
  physical_equal(retained.consumer, proposed.consumer) &&
  physical_equal(retained.producer, proposed.producer) &&
  physical_equal(retained.journal, proposed.journal) &&
  physical_equal(retained.materials.prepared, proposed.materials.prepared) &&
  retained.request == proposed.request
}

///|
fn HolderEffectCatalogFileCustody::current(
  self : HolderEffectCatalogFileCustody,
) -> Bool {
  self.diagnostic_ceiling > 0 &&
  !self.retiring &&
  self.failure.val is None &&
  self.original.current() &&
  self.original.consumer.read_catalog_preparation_capacity(
    self.original.journal,
    self.original.producer,
    self.preparation,
  )
  is Ok(_) &&
  self.original.current()
}

///|
/// Charge validation precedes the carrier and every selected physical read.
/// Equal envelope quantities do not replace the original nominal producer.
fn prepare_holder_catalog_file_custody(
  resources : HolderOutputResources,
  original : HolderEffectOriginalPolicyContext,
  preparation : @journal.NativeInitialCatalogUseEnvelope,
  diagnostic_ceiling : Int,
) -> HolderEffectCatalogFileCustody? {
  // Selection is not permission or proof of complete numeric funding. Refuse
  // before the original current/Journal query, never fall back to legacy detail.
  if diagnostic_ceiling <= 0 {
    return None
  }
  if resources.effect_catalog_files.val is Some(retained) {
    guard retained.diagnostic_ceiling == diagnostic_ceiling &&
      holder_catalog_file_original_matches(retained.original, original) &&
      retained.preparation.record_bytes == preparation.record_bytes &&
      retained.preparation.control_bytes == preparation.control_bytes &&
      retained.preparation.workspace_bytes == preparation.workspace_bytes &&
      retained.current() else {
      return None
    }
    return Some(retained)
  }
  guard original.current() &&
    original.consumer.read_catalog_preparation_capacity(
      original.journal,
      original.producer,
      preparation,
    )
    is Ok(_) &&
    original.current() else {
    return None
  }
  let retained : HolderEffectCatalogFileCustody = {
    original,
    preparation,
    diagnostic_ceiling,
    failure: Ref(None),
    retiring: false,
  }
  resources.effect_catalog_files.val = Some(retained)
  Some(retained)
}

///|
/// The private read seam forwards actual opaque failure, never only its Issue.
/// A callback return is not a stop/cleanup acknowledgement or a send grant.
fn holder_catalog_file_read(
  failure : Ref[@bounded_files.NativeBoundedTextFailure?],
  current : () -> Bool,
  read : () -> Result[String, @bounded_files.NativeBoundedTextFailure],
) -> String? {
  guard failure.val is None && current() else { return None }
  match read() {
    Ok(text) => if current() { Some(text) } else { None }
    Err(original) => {
      failure.val = Some(original)
      None
    }
  }
}

///|
/// Forward the exact immutable installer selection to the original physical
/// read. This binds a private diagnostic extent, never a Source/Provider grant.
fn holder_catalog_file_read_with_ceiling(
  failure : Ref[@bounded_files.NativeBoundedTextFailure?],
  current : () -> Bool,
  diagnostic_ceiling : Int,
  read : (Int) -> Result[String, @bounded_files.NativeBoundedTextFailure],
) -> String? {
  if diagnostic_ceiling <= 0 {
    return None
  }
  holder_catalog_file_read(failure, current, () => read(diagnostic_ceiling))
}

///|
fn HolderEffectCatalogFileCustody::read(
  self : HolderEffectCatalogFileCustody,
  root : String,
  name : String,
  limit : Int64,
) -> String? {
  holder_catalog_file_read_with_ceiling(
    self.failure,
    () => self.current(),
    self.diagnostic_ceiling,
    ceiling => {
      @bounded_files.read_bounded_text_file_with_custody(
        root,
        name,
        limit,
        diagnostic_ceiling=Some(ceiling),
      )
    },
  )
}

///|
fn load_holder_catalog_file(
  custody : HolderEffectCatalogFileCustody,
  root : String,
  name : String,
  limit : Int64,
) -> String raise CommandStop {
  match custody.read(root, name, limit) {
    Some(text) => text
    None => stop("Effect installation file read pending")
  }
}

///|
/// Re-observe only the same opaque filesystem Owner. Unknown reply keeps the
/// original carrier; a second pass cannot reopen or replace its Reader/Root.
fn retry_holder_catalog_file_failure(
  failure : Ref[@bounded_files.NativeBoundedTextFailure?],
  close : (@bounded_files.NativeBoundedTextFailure) -> Result[
    Unit,
    @filesystem.NativeFilesystemIssue,
  ],
) -> Bool {
  if failure.val is Some(original) {
    guard close(original) is Ok(_) else { return false }
    failure.val = None
  }
  true
}

///|
/// Before either original task releases its stamp/holding, stop new reads and
/// ask the original filesystem Owner for cleanup. Keep preparation on refusal.
fn prepare_holder_catalog_file_cleanup(
  resources : HolderOutputResources,
  task : HolderTaskCustody,
) -> Bool {
  if resources.effect_catalog_files.val is Some(retained) &&
    (
      physical_equal(retained.original.task, task) ||
      physical_equal(retained.original.producer_task, task)
    ) {
    retained.retiring = true
    return retry_holder_catalog_file_failure(retained.failure, original => {
      original.retry_cleanup()
    })
  }
  true
}

///|
/// Called after Review/service close and before Runtime/stamp retirement. The
/// helper ends before its caller returns capacity; it exposes no failure alias.
fn detach_holder_catalog_file_custody(
  resources : HolderOutputResources,
  task : HolderTaskCustody,
) -> Bool {
  if resources.effect_catalog_files.val is Some(retained) &&
    (
      physical_equal(retained.original.task, task) ||
      physical_equal(retained.original.producer_task, task)
    ) {
    guard retained.retiring && retained.failure.val is None else {
      return false
    }
    resources.effect_catalog_files.val = None
  }
  true
}

///|
fn holder_catalog_file_cleanup_pending(
  resources : HolderOutputResources,
  task : HolderTaskCustody,
) -> Bool {
  resources.effect_catalog_files.val is Some(retained) &&
  retained.failure.val is Some(_) &&
  (
    physical_equal(retained.original.task, task) ||
    physical_equal(retained.original.producer_task, task)
  )
}
