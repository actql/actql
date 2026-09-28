# Journal initialization and cleanup closure

Base: `2822bbd851333f6d91074b7df63ba9ceaa5a55ec` (`origin/main`).
This change is independent of the in-progress namespace correction.

## Owned boundaries

- The credential journal uses the same synchronous SQLite transaction owner as
  the Coordinator, Transfer, and Checkpoint journals. A failed COMMIT remains
  unknown even if the connection is usable; body, rollback, and state-inspection
  failures remain separate. An unusable connection refuses new journal work.
- The first credential journal close forbids new operations. Database release
  and directory sync have distinct completion states. A sync failure after
  database release retries only sync; it never reopens the database or repeats
  credential use, Run, or Effect work.
- Initialization protection covers statement preparation after schema COMMIT in
  all four journals. A failed release retains the primary cause, cleanup errors,
  and a retryable owner. The initialization cleanup boundary runs once.
- The installed Host constructs its diagnostic observer inside the existing
  initialization cleanup boundary. Invalid observer configuration cannot strand
  an already acquired Source or Effect owner.

## Evidence and limits

Real SQLite fault injection covers post-schema prepare failure with both close
outcomes for each journal, credential directory-sync retry, and the wrapped Host
cleanup owner. A real installed Site test verifies that a sync failure leaves
the Site closed to new work and that retry finishes without a second database
close or provider request. A standard Host test covers invalid observer
configuration after Source acquisition; the shared cleanup-owner test covers
independent Source and Effect release failures.

The changed-file tests and the `host` and `client` local CI jobs passed. The
first `host` attempt stopped on a local npm cache permission error; the same
job passed with a checkout-local cache. Linux CI and its final SHA are recorded
in the PR after push. No live Salesforce org was used.

Effect index optimization and Local resource-checker maintenance remain separate
P3 work. This change does not add automatic Run or Effect replay, a new cleanup
framework, or a shortcut around directory durability.
