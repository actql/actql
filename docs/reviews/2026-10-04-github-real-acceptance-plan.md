# Real GitHub acceptance plan (for approval)

This plan covers the first acceptance of the GitHub connector against the real GitHub API. The fixture acceptance is in #315, #319 and #330.

- **Nothing here has been run.** Each step needs the approval listed in section 6.
- **Merging this document approves nothing.** Writes to the real service are approved separately.

## 1. Target and credential

| Item | Plan |
| --- | --- |
| Repository | One dedicated **private** repository under the actql organization, for example `actql/connector-acceptance-github`. A human creates it, and it is used for nothing else. |
| Seed data | 3 Issues created by hand: 2 open, 1 closed. One has an empty body and one has a non-ASCII label. 1 pull request, to confirm it never appears as an Issue row. |
| Credential | A fine-grained PAT restricted to that single repository. Permissions: **Issues: Read and write**, plus the default **Metadata: Read**. Expiry: 7 days. |
| Secret handling | The token is supplied through the Site profile's `tokenEnvironment` variable at run time, from the existing 1Password vault. It is never written to a file, a log or a receipt. |
| API version | `X-GitHub-Api-Version: 2026-03-10`, the same as the fixtures. |

## 2. Read steps (no side effects)

The read path is the one in #319: GraphQL, bound to the published node ID.

1. **Explicit publication.** One `POST /graphql` with the fixed `ActqlRepository` document, which records `databaseId` and the global node `id`.
2. **Host start.** No provider I/O.
3. **Read.** The public Client runs the two-stage Program from the fixture acceptance. Expected requests:
   - one `POST /graphql` with the fixed `ActqlIssues` document per page;
   - `first` is 100, so the seed data is 1 page.
   - There are no REST listing or name lookups during the read.
4. **Expected result.**
   - The 2 open Issues.
   - The pull request is absent.
   - The empty body is published as `""`, not NULL.
   - Timestamps are in ActQL spelling.
5. **Recorded per request.**
   - Method, document name (`ActqlRepository` or `ActqlIssues`) and HTTP status.
   - Whether `errors` was present.
   - For `ActqlIssues`, whether the returned repository `databaseId` and `id` equal the publication.
   - Rate-limit observations: the parsed `x-ratelimit-remaining` and `x-ratelimit-reset` values only, never raw headers.
6. **Budget.**
   - 1 request for publication, plus 1 per read, totalling at most 5 requests for one publication and up to 4 reads.
   - Each GraphQL query costs at least 1 point of the 5,000-point hourly primary limit.

## 3. Write steps (side effects; separate approval)

| Item | Plan |
| --- | --- |
| Operation | Add one comment to one seeded Issue (`POST /repos/{owner}/{repo}/issues/{n}/comments`), through the Effect Ledger claim in #315. |
| Count | **Exactly 1 comment** under this approval. |
| Unknown outcome | If the reply is lost, or the outcome is otherwise unknown, that Effect stays **unknown**. **It is never re-sent.** A lost reply is not evidence that nothing was sent. |
| Reconciliation | An operator reads the Issue's comments by hand and records what was observed. A comment whose body matches is **not** taken as proof that the original Effect succeeded. The unknown Effect stays unresolved until reconciled under the existing Effect recovery rules. |
| A second comment | Not part of this approval. If needed, it is a **new, separately approved** Effect with its own body marker. It is never treated as a retry of the unresolved first one. |
| Content | A fixed ASCII marker, `actql-acceptance <run id>`, with no mentions. Watchers are notified, so the operator unwatches the private repository beforehand. |
| Pacing | At least 1 s between writes. |
| Precondition | Comment creation is currently a Site driver (#315), with the Effect installer table in place (#320, merged). The write runs only after the GitHub comment Effect is installed through that table. Until then, only section 2 can run. |

## 4. Cleanup

1. Delete the acceptance comment by hand in the web UI. The connector does not implement DELETE.
2. Revoke the PAT.
3. Keep the repository for later runs, or archive it.
4. Record the cleanup with the run ids and comment ids.

## 5. What is recorded separately from fixture results

Differences from the fixture are recorded on their own, for example:

- whether `nodes` include pull requests (they should not);
- the real form of `id` and `databaseId`, including any representation change between publication and read;
- the rate-limit headers and any `RATE_LIMITED` errors actually returned;
- the real timestamp and empty-body forms.

Fixture success is not evidence of real-service behavior, and real-service results are not evidence of fixture correctness.

## 6. Approval requested

1. Repository creation and seed data (human).
2. The PAT scope and 7-day expiry above.
3. Read steps (section 2).
4. Write steps (section 3), separately: exactly 1 comment, only after the GitHub comment Effect is installed.
