# Tableau catalog and job projections

This portable Connector module projects bounded provider DATA. It prepares the
exact site/LUID paths for full data-source refresh and all-output flow runs,
admits their distinct complete success responses, and permits Query Job only
for the original returned job id/site/API version. It does not search for a
recent job on the same target. A missing/lost initial job response supplies no
`StartedJob`; the existing Effect transport and journal keep Unknown and own
persistence and non-resend decisions.

The returned response hash identifies the original bytes, not authenticated
custody, approval, credentials, a send claim, or a completed job. Lookup checks
identity and type only. Tableau has job-type-specific `finishCode` semantics,
so progress/finish fields are not promoted to completion here. An installed
adapter still needs actual credential/current permission, sealed Preview,
original claim/outcome persistence, bounded physical I/O and cleanup through
existing Owners. This module does not establish installed/provider acceptance.

Strong conditional metadata update/delete stays unavailable: no adopted
atomic `updatedAt`/`If-Match` provider profile has been demonstrated. Tag add
and delete would be separate physical operations with their own partial and
Unknown custody, not an atomic replacement. Catalog, view data, publication,
physical job dispatch and installed acceptance remain necessary work.

## Provider contracts

- [Update Data Source Now](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_data_sources.htm#update_data_source_now): target refresh POST, default full refresh, response202 and original refresh job/target.
- [Run Flow Now](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_flow.htm#run_flow_now): flow POST, omitted output selection runs all outputs, response200 and original flow job/target.
- [Query Job](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_jobs_tasks_and_schedules.htm#query_job): exact site/job GET and job-specific status semantics. The provider's administrator/read restrictions remain independent of an admitted response.

The API version is selected by the eventual installed provider profile; syntax
validation of a version does not assert server support. JSON response bodies
must come from a complete `application/json` response to the exact physical
request; XML response decoding is not implemented by this JSON projection.


## Catalog pages

The catalog page projection prepares GET requests for workbooks, published data
sources, views and flows in one explicitly selected site/API version. The source
profile requests 100 records per page and view usage statistics. It admits a
complete JSON response through the same bounded duplicate-rejecting reader as
jobs, validates the selected pagination, projects every returned record, rejects
duplicate identities, and derives only the next request of that same listing.

Missing/null optional metadata remains unknown. Explicit empty tags and zero
usage remain distinct. Present malformed metadata refuses the entire page,
including a malformed nonfirst record. Documented UTC whole seconds receive exact zero milliseconds; all timestamps
then use the existing Values calendar/instant admission. An updated timestamp is DATA, never an atomic conditional-write token.
Catalog timestamps do not stand in for last refresh, last viewed or last flow
run observations; those require their actual provider suppliers.

The provider body does not identify the actual site or server. The physical
Source/Host transport must independently preserve the selected endpoint/TLS,
credentials, current permission, complete bounded response and cleanup. A page
does not attest any of these, a stable cross-page snapshot, source capability,
physical funding, or installed acceptance. No filters/sort/field pushdown is
advertised by this first paging projection.

Provider references: [Query Workbooks for Site](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_workbooks_and_views.htm#query_workbooks_for_site),
[Query Views for Site](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_workbooks_and_views.htm#query_views_for_site),
[Query Data Sources](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_data_sources.htm#query_data_sources),
[Query Flows for a Site](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_ref_flow.htm#query_flows_for_site).

The view projection also retains the returned `workbook.id` as `workbook_id`.
It uses the same bounded LUID admission as project/owner references; a missing or
null workbook stays unknown, and a malformed present workbook refuses the whole
page. A name or `contentUrl` is not a substitute for that identity. This is the
provider relationship needed by the documented views-to-workbooks JOIN, not a
completed Source, physical capture, or inferred relation from matching names.
