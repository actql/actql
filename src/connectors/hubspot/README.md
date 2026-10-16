# HubSpot property observation

`catalog` projects one bounded, complete HubSpot properties response into
Connector metadata and the existing Common value contracts. It does not perform
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
IDs and positively enforced custom unique keys retain their supported path. Mutable name/option projections are copies; they cannot
modify the original observation.

The parse/admission limits cover the original complete response before
projection. A truncated response, duplicate property/JSON key, malformed flag or
exhausted bound is refused rather than becoming a partial Catalog. These are
physical bounds, not language limits or a numeric-profile adoption.

Provider reference:
[HubSpot properties API](https://developers.hubspot.com/docs/api-reference/legacy/crm/properties/guide),
[API company deduplication exception](https://knowledge.hubspot.com/records/deduplication-of-records?content_language=English).
Record paging, exact value conversion, authenticated discovery/current binding,
installed publication, record Effects, associations and enrolment still need
their physical caller connections; these pure metadata checks do not establish
ordinary installed or real-service acceptance.
