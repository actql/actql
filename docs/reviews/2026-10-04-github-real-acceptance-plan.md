# Real GitHub acceptance plan (for approval)

This plan covers the first acceptance of the GitHub connector against the real GitHub REST API. The fixture acceptance is already in #319, #315 and #330. **Nothing here has been run.** Each write needs this plan approved first.

## 1. Target and credential

| Item | Plan |
| --- | --- |
| Repository | One dedicated **private** repository under the actql organization, for example `actql/connector-acceptance-github`. It is created by a human and used for nothing else. |
| Seed data | 3 Issues created by hand: 2 open, 1 closed, one with a non-ASCII label. 1 pull request opened from a branch, to exercise PR exclusion. |
| Credential | A fine-grained PAT restricted to that single repository, with the **Issues: Read and write** permission and the **Metadata: Read** permission that GitHub adds by default. Expiry is 7 days. |
| Secret handling | The token is supplied through the Site profile's `tokenEnvironment` variable at run time, read from the existing 1Password vault. It is never written to a file, a log or a receipt. |
| API version | `X-GitHub-Api-Version: 2026-03-10`, the same as the fixtures. |

## 2. Read steps (no side effects)

1. Explicit publication: one `GET /repos/{owner}/{repo}`, which records the id and node_id.
2. Host start: no provider I/O.
3. The public Client runs the two-stage Program from the fixture acceptance. Expected requests:
   - 1 identity check;
   - ⌈items/100⌉ listing pages, so 1 for the seed data;
   - 1 identity check.
4. Expected result: the 2 open Issues. The PR is excluded, and timestamps are in ActQL spelling.
5. Recorded per request: method, path category and status only.
6. Budget: at most 10 requests in total, out of the primary limit of 5,000/h.

## 3. Write steps (needs explicit approval; side effects)

| Item | Plan |
| --- | --- |
| Operation | Add a comment to one seeded Issue (`POST /repos/{owner}/{repo}/issues/{n}/comments`). |
| Count | At most **2** comments in total: 1 normal send, and 1 reserved for a single re-run if the first is lost before the Ledger records it. No automatic resend. A lost reply stays unknown and is reconciled by reading the Issue's comments by hand. |
| Content | A fixed ASCII marker, `actql-acceptance <run id>`, with no mentions, so no user is notified beyond repository watchers. |
| Notifications | Repository watchers receive notifications. The repository is private and its only watcher is the operator, who should unwatch it before the run to avoid mail. |
| Pacing | At least 1 s between writes, as GitHub recommends. |
| Precondition | Comment creation is currently a Site driver only (#315). The write run happens only after the Effect installation is connected, which is the next unit after #320. Until then, only the read steps can run. |

## 4. Cleanup

1. Delete the acceptance comments by hand in the web UI. The connector does not implement DELETE.
2. Revoke the PAT.
3. Keep the repository for later runs, or archive it.

Record the cleanup in the acceptance record with the run ids and comment ids.

## 5. What is recorded separately from fixture results

- Differences from the fixture, for example:
  - the actual `Link` spelling of spaces (`%20` or `+`): the connector currently refuses `+`;
  - which rate-limit headers are present;
  - the real timestamp format.
- Fixture success is not taken as evidence of real-service behavior, and the reverse is also true.

## 6. Approval requested

1. Repository creation and seed data (human).
2. The PAT scope and 7-day expiry above.
3. Read steps (section 2).
4. Write steps (section 3): only after the Effect installation lands, at most 2 comments.
