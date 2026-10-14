///|
/// Private loan transport tags; these are not Run or execution outcomes.
pub(all) enum InstalledArenaBackingOperation {
  BorrowBacking
  ObserveBacking
  ReturnBacking
} derive(Eq)

///|
/// Data projection retaining the existing nominal Host and SharedBorrow. It
/// creates no lease, capacity reservation, transfer or independent lifecycle.
struct InstalledArenaBackingReply {
  operation : InstalledArenaBackingOperation
  original_result : InstalledArenaReply
  original_borrow : InstalledArenaBackingBorrow?
}

///|
/// Preserve the existing issue classification without another error checker.
fn backing_unit_reply(
  operation : InstalledArenaBackingOperation,
  borrow : InstalledArenaBackingBorrow,
  result : Result[Unit, @bootstrap.NativeBootstrapIssue],
) -> InstalledArenaBackingReply {
  {
    operation,
    original_result: original_unit_reply(Current, borrow.host, result),
    original_borrow: Some(borrow),
  }
}

///|
pub fn borrow_installed_arena_backing_reply(
  original : InstalledArenaHost,
) -> InstalledArenaBackingReply {
  match original.borrow_backing() {
    Ok(borrow) =>
      {
        operation: BorrowBacking,
        original_result: original_unit_reply(Current, original, Ok(())),
        original_borrow: Some(borrow),
      }
    Err(issue) =>
      {
        operation: BorrowBacking,
        original_result: original_unit_reply(Current, original, Err(issue)),
        original_borrow: None,
      }
  }
}

///|
/// A foreign target is refused by the existing Owner. Even that refusal keeps
/// the loan's actual original Host; it never replaces custody with the target.
pub fn current_installed_arena_backing_reply(
  original : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> InstalledArenaBackingReply {
  backing_unit_reply(
    ObserveBacking,
    borrow,
    original.require_backing_borrow_current(borrow),
  )
}

///|
/// The physical borrower supplies this only after its same use has stopped.
/// Return ACK is the existing loan return, not physical stop or Host close ACK.
pub fn return_installed_arena_backing_reply(
  original : InstalledArenaHost,
  borrow : InstalledArenaBackingBorrow,
) -> InstalledArenaBackingReply {
  backing_unit_reply(
    ReturnBacking,
    borrow,
    original.return_backing_borrow(borrow),
  )
}

///|
/// Typed accessors only; C must not read generated struct or option fields.
pub fn InstalledArenaBackingReply::original_host(
  self : InstalledArenaBackingReply,
) -> InstalledArenaHost? {
  self.original_result.original_host()
}

///|
pub fn InstalledArenaBackingReply::original_loan(
  self : InstalledArenaBackingReply,
) -> InstalledArenaBackingBorrow? {
  self.original_borrow
}

///|
pub fn InstalledArenaBackingReply::operation_tag(
  self : InstalledArenaBackingReply,
) -> Int {
  match self.operation {
    BorrowBacking => 1
    ObserveBacking => 2
    ReturnBacking => 3
  }
}

///|
pub fn InstalledArenaBackingReply::issue_family(
  self : InstalledArenaBackingReply,
) -> Int {
  self.original_result.issue_family()
}

///|
/// Explanation only; no caller may derive permission or ACK from this text.
pub fn InstalledArenaBackingReply::issue_description(
  self : InstalledArenaBackingReply,
) -> String {
  self.original_result.issue_description()
}
