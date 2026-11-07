///|
// Only Row Work retains this wrapper. The existing Values access record and
// its SourceFree current/fence closure shapes remain unchanged. This is a
// closed original-purpose projection, never another routing or Account owner.
priv struct NativeLocalRelationOriginalAccess {
  base : NativeLocalValuesOriginalAccess
  source : NativeLocalWorkSourceOriginal
}

///|
fn NativeLocalRelationOriginalAccess::current(
  self : NativeLocalRelationOriginalAccess,
) -> Bool {
  self.base.in_original_read(
    (_operations, current) => {
      if current() {
        Ok(())
      } else {
        Err(AuthorizationDenied)
      }
    },
    source=self.source,
  )
  is Ok(_)
}

///|
fn NativeLocalRelationOriginalAccess::lookup(
  self : NativeLocalRelationOriginalAccess,
) -> Result[NativeClientRunLookup, NativeClientValuesWorkIssue] {
  self.base.in_original_read(
    (operations, current) => {
      self.base.host.journal
      .lookup_with_reads(
        self.base.request,
        current(),
        reads=Some(operations.reads),
      )
      .map_err(issue => Journal(issue))
    },
    source=self.source,
  )
}

///|
fn NativeLocalRelationOriginalAccess::claim(
  self : NativeLocalRelationOriginalAccess,
) -> Result[NativeClientWorkFirstStart, NativeClientValuesWorkIssue] {
  self.base.in_original_read(
    (operations, current) => {
      claim_native_client_retained_work_first_start_with_operations(
        self.base.host.journal,
        self.base.request,
        current,
        operations=Some(operations),
      ).map_err(issue => Start(issue))
    },
    source=self.source,
  )
}

///|
fn NativeLocalRelationOriginalAccess::require_start_current(
  self : NativeLocalRelationOriginalAccess,
  start : NativeClientWorkFirstStart,
) -> Result[Unit, NativeClientValuesWorkIssue] {
  self.base.in_original_read(
    (operations, current) => {
      start
      .require_current(
        self.base.host.journal,
        self.base.request,
        current,
        reads=Some(operations.reads),
      )
      .map_err(issue => Start(issue))
    },
    source=self.source,
  )
}

///|
fn NativeLocalRelationOriginalAccess::poll_execution_original(
  self : NativeLocalRelationOriginalAccess,
  start : NativeClientWorkFirstStart,
) -> Bool {
  self.base.poll_execution_original(start)
}
