# HubSpot account, property and record observations

`catalog` projects bounded, complete account-details, properties and record-page
responses into observations and the existing Common value contracts. It does not perform
I/O or declare an installed Source, Effect, current authorization or executable
Mapping. The approved complete Connector target remains
[the public HubSpot page](../../../docs/connectors/hubspot.md).

The physical caller must retain the original account/object request and response
through the existing credential and observation Owners. The properties response
does not echo that account/object binding; the `object_type` argument is only a
projection label. Its response digest is provenance, not authority. This package
does not make a provider response current or establish publication, cleanup or
capacity ACKs.

Property carriers use Common `value_contract`: exact `decimal(38,10)`, boolean,
date, timestamp, strings and string arrays. Enumeration choices keep internal
values instead of labels. Unknown native types remain explicit refusals when
selected, without discarding unrelated supported properties. Missing write
metadata stays unconfirmed. Value-readonly, calculated and archived properties
cannot become writable through definition-editability metadata. Alternate keys
require an enforced provider key or positive uniqueness metadata. An observed
company `domain` with false or missing `hasUniqueValue` is not a candidate key:
HubSpot explicitly does not deduplicate API-created companies by domain. Lookup
syntax and UI/import deduplication are not a global uniqueness guarantee. Record
IDs and positively enforced custom unique keys retain their supported path.
Mutable name/option projections are copies; they cannot modify the original observation.

`object_schema_wire` projects explicitly selected observed properties and the
original non-null string record key into Common's full relation field-map.
It calls the same `property_contract` and Common name/order/emission Owners;
decimal precision and array element contracts are not lowered to primitive
fields or inferred from example rows. Duplicate or reserved record-key
selections, unknown/unsupported selected properties and exhausted output/name
bounds are refused without a partial schema. The independent name-byte and
complete output bounds are physical caller inputs, not numerical funding.
The existing Common declaration Owner must admit that schema and its identity
again; this projection alone establishes no Catalog publication, current
account binding, permission or installed Source support.

The parse/admission limits cover the original complete response before
projection. A truncated response, duplicate property/JSON key, malformed flag or
exhausted bound is refused rather than becoming a partial Catalog. These are
physical bounds, not language limits or a numeric-profile adoption.

`project_object_page` consumes that exact property projection and uses Common
admission for each selected value. Provider numbers stay decimal text; the
shared exact source-text normalizer emits the fixed-scale Common spelling
without binary64 or rounding. Boolean text, explicit unset/null values,
semicolon-separated checkbox values and UTC/millisecond date/time values keep
their respective typed meanings. Missing selected fields, inexact decimals,
archived/duplicate records and malformed continuation cursors refuse the complete
page. The continuation contains only the opaque `after` token: a returned URL
is never permission to follow another origin. Input parsing and simultaneous
output-value budgets remain distinct from physical funding.

Provider reference:
[HubSpot properties API](https://developers.hubspot.com/docs/api-reference/legacy/crm/properties/guide),
[API company deduplication exception](https://knowledge.hubspot.com/records/deduplication-of-records?content_language=English).
Normal installed discovery/current binding, publication,
record Effects, associations and enrolment still need their physical caller
connections; these pure observations do not establish ordinary installed or
real-service acceptance.

The account-details projection reads the complete original response through
Source and Decode. Its `portalId` follows the provider's int32 declaration;
Common's exact source-text conversion also checks the original numeric token,
so binary64 rounding cannot turn a fractional identifier into another account.
Original response bytes determine the provenance digest. Other account metadata,
including `accountType`, is not interpreted as policy or permission. The same
observation must match the original canonical portal identifier; it is never a
grant or a substitute for the private Credential acquisition binding.

The private `host_node` bridge supplies this projection to
`adapters/connectors/hubspot/site/hubspot-account-read.mjs`. That entry requires
an existing binding, a separately authorized `hubspot:account:details` operation,
current read callbacks, and original response-charge/consumption callbacks before
starting I/O. It does not create an acquisition or authorize an identity probe
implicitly. Complete success and rejection bodies are charged before decoding;
current read checks surround disclosure and awaited charge consumption. A later
refusal retains the original bounded response on the private error carrier with
the original cause/code. A lost reply keeps the Credential journal's Unknown,
without automatic re-probing or a replacement-token request.

The component fixtures use actual Common/Credential/Account owners, SQLite and
loopback TLS. Complete responses use the same actual RowRun/Ledger. The lost-reply
case separately qualifies Credential/transport Unknown, not unreported RowRun
transfer funding. Normal Source installer/discovery/publication,
wholephase retained/scratch/cleanup funding, ordinary artifact adoption and live
service acceptance are still required. No normal numerical profile is adopted.
The original binding and any same-owner cleanup responsibility must remain with
the acquisition; this observation entry does not close or replace that owner.

Provider account shape reference:
[HubSpot's published account-info v3 specification](https://github.com/HubSpot/HubSpot-public-api-spec-collection/blob/main/PublicApiSpecs/Account/Account%20Info/Rollouts/136890/v3/accountInfo.json).
The selected endpoint/shape is research input, not evidence of live token scope,
account rights, server enforcement, or support for another API version.


`hubspot-object-read.mjs` sequences the same private binding's explicit identity,
properties and object-list operations. Every operation needs its own originally
authorized nominal use and current Host check; data access does not imply an
identity or schema grant. The original complete properties observation is
rechecked before the first page and after the last one through its metadata
Owner. Property-list ordering and display labels do not substitute for internal
names/types/options, uniqueness or write facts. Derived metadata equality covers
all admitted fields; it does not assert permission or provider snapshot isolation.

Each complete response is charged to the original accounted RowRun before
projection. Observation tickets are consumed without fabricating data pages;
projected data pages consume their exact original tickets. The bounded wire uses
Common's existing value emitter, preserving fixed-scale decimal strings, exact
record IDs and array values across the JS boundary. The existing Host alone owns
finish, physical transport verification, capture and cleanup. This driver never
returns an acquired Source or makes a close ACK.

The installer supplies independent positive response, parse, value/output,
request/page/row and cursor limits. Identity and both schema observations count
as real requests in that same bound. Returned continuation URLs are ignored;
only bounded opaque cursors are used on the original origin/object path. A
cycle, duplicate record, drift, bound failure or authority loss stops without
retry, deduplication, fallback or a successful partial result. Original complete
responses remain on the private failure carrier. A lost response remains the
Credential journal's original Unknown; no unobserved byte count or full funding
proof is fabricated. Simultaneous original bodies, page wire/parsed rows,
metadata/maps and error-carrier aliases still require the normal wholephase
supplier. These component paths do not adopt a numerical profile or ordinary
installed/public/live-service support.
