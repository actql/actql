# Tableau job request and response projections

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
