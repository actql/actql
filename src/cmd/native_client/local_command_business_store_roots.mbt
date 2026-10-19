///|
// Keep both actual Roots and every partial constructor before another IO or
// application exception. A path String or private-ownership observation is
// never a descriptor cleanup acknowledgement.
fn LocalCommandBusinessPreparation::prepare_store_path(
  self : LocalCommandBusinessPreparation,
  managed : String,
  name : String,
) -> String raise ClientStop {
  self.original.prepare_business_store_path(managed, name)
}

///|
fn LocalCommandPreparationOriginal::prepare_business_store_path(
  self : LocalCommandPreparationOriginal,
  managed : String,
  name : String,
  existing? : Bool = false,
) -> String raise ClientStop {
  let business = self.business.unwrap_or_else(() => {
    stop("LocalBusinessOriginalUnavailable")
  })
  let parent = match
    @local_filesystem.open_private_root_in_current_read_context_with_custody(
      managed,
      self.profile.diagnostic_ceiling,
    ) {
    Ok(root) => {
      business.store_parent = Some(root)
      root
    }
    Err(failure) => {
      business.store_parent_failure = Some(failure)
      stop("LocalManagedRootCleanupPending")
    }
  }
  if parent
    .inspect_directory(name)
    .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
    is None {
    if existing {
      stop("LocalOriginalStoreUnavailable")
    }
    parent
    .create_directory(name)
    .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
    |> ignore
  }
  let root = match parent.open_child_with_custody(name) {
    Ok(root) => {
      business.store_root = Some(root)
      root
    }
    Err(failure) => {
      business.store_root_failure = Some(failure)
      stop("LocalStoreRootCleanupPending")
    }
  }
  root
  .private_ownership()
  .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
  |> ignore
  managed + "/" + name
}

///|
// Called after Store/DB return, while the parent still retains these aliases.
// Actual same-Read entry and return bracket child-before-parent descriptor
// cleanup. Even closed Root values stay retained until that return ACK.
fn LocalCommandPreparationOriginal::close_business_store_roots(
  self : LocalCommandPreparationOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.business is Some(business) else { return Ok(()) }
  if business.store_parent is None &&
    business.store_parent_failure is None &&
    business.store_root is None &&
    business.store_root_failure is None {
    business.store_root_operation = None
    return Ok(())
  }
  guard business.store_root_operation is Some(bridge) &&
    business.store is None &&
    business.store_failure is None &&
    !self.journal_read_open &&
    !self.phase_open else {
    return Err(CommandBusinessChildren)
  }
  match bridge.enter_cleanup_work() {
    Err(issue) => return Err(CommandStoreOperation(StoreOperationSqlite(issue)))
    Ok(_) => ()
  }
  let closed = business.close_store_root_descriptors()
  if closed is Err(issue) {
    self.retain_primary(issue)
  }
  let returned = bridge.leave_store()
  match (closed, returned) {
    (Err(issue), _) => Err(issue)
    (Ok(_), Err(issue)) =>
      Err(CommandStoreOperation(StoreOperationSqlite(issue)))
    (Ok(_), Ok(_)) => {
      business.store_root_failure = None
      business.store_root = None
      business.store_parent_failure = None
      business.store_parent = None
      business.store_root_operation = None
      Ok(())
    }
  }
}

///|
fn LocalCommandBusinessOriginal::close_store_root_descriptors(
  self : LocalCommandBusinessOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.store_root_failure is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  if self.store_root is Some(root) {
    match root.close() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  if self.store_parent_failure is Some(failure) {
    match failure.retry_cleanup() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  if self.store_parent is Some(root) {
    match root.close() {
      Err(issue) => return Err(CommandFilesystemCleanup(issue))
      Ok(_) => ()
    }
  }
  Ok(())
}
