///|
#export_name("bindingHoldingPendingClose")
pub fn holding_pending_close() -> Int {
  @site.retained_site_holding_action_code(
    @site.prepare_retained_site_holding_step(
      true, false, false, false, false, false,
    ),
  )
}

///|
#export_name("bindingHoldingConfirmedClose")
pub fn holding_confirmed_close() -> Int {
  @site.retained_site_holding_action_code(
    @site.prepare_retained_site_holding_step(
      true, true, false, false, false, false,
    ),
  )
}

///|
#export_name("bindingPublicationCommitUnknown")
pub fn publication_commit_unknown() -> Int {
  @publication.publication_commit_failure_action_code(
    @publication.prepare_publication_commit_failure_step(
      true, true, false, false,
    ),
  )
}
