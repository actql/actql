# Calendar Event temporal projection

The Calendar provider interprets the original Event `start` and `end` objects.
It does not select an account, calendar, Site, read scope or Source acquisition.
The original response digest and selected CalendarProfile CID describe DATA;
neither substitutes for those owners or for a current Event version.

The [Calendar connector contract](../connectors/calendar.md#types) keeps one
timestamp representation for event endpoints. All-day `date` values denote
midnight in the original calendar's time zone. They are resolved independently,
so a day crossing a transition need not have a fixed millisecond duration.
Explicit RFC3339 offsets use the existing exact timestamp converter. An endpoint
without an offset requires its own explicit `timeZone`, as specified by the
[Event API](https://developers.google.com/workspace/calendar/api/v3/reference/events).
No process zone, calendar default or inferred UTC offset fills that field.

The caller supplies the original admitted CalendarProfile. Local conversion
uses only its exact selected table and existing `actql-calendar-boundaries/0.1`
law: the earliest exact occurrence at a fold and the earliest valid boundary
after a gap. Finer fractional precision survives exact resolution; it is not
added to a gap boundary. Both endpoints share one finite resolution-work bound.
Missing zones, unsupported coverage, malformed fields and exhausted bounds refuse.
No ambient timezone database or second conversion law is introduced.

Both endpoints must have the same date/dateTime form. A reversed original civil
date pair refuses even if a skipped date makes the converted instants equal.
The original end remains exclusive; this projection does not add a duration,
expand a recurrence or infer attendance. The complete row projection separately
handles unavailable cells, including an id-only deleted item. It validates every
declared cell before output selection. Unknown values become nullable cells;
present malformed values refuse. `endTimeUnspecified` suppresses the compatibility
end, without skipping validation of a supplied endpoint.

The [approved unavailable-cell policy](semantic-decisions.md#calendar-event-unavailable-cells)
keeps organizer email nullable without a fallback and retains either the complete
ordered attendee list or NULL. Missing email/status and pending/omitted list data
do not create attendee defaults. Validation still walks all supplied members.
The documented omitted `optional` boolean is false, while explicit null refuses.
Output values share finite node/text limits across the whole page. Endpoint
resolution shares the original page work limit. The page retains its same query
and CalendarProfile; copied row IDs and column-name arrays cannot mutate them.

The provider's pure fetch/decode hooks preserve the original query bounds and
opaque cursor, expand recurring instances and check cross-page IDs/cursor cycles.
Short or empty pages with a cursor are not completion. These hooks do not own
authorization, row/body charging, managed response custody or cleanup, and they
are not a normal installation factory. A matching original Profile getter and
the complete checked Source/parent/backing connection remain required. Raw API
time parameters do not by themselves establish exact SQL predicate pushdown.

The Events request adapter consumes the same parameter-bound `requestWire`
provided by the existing RowAcquisition caller. Its complete `request_schema`
body is an object contract with four required non-null strings: `calendar_id`,
`time_min`, `time_max` and `time_zone`. It is distinct from the response row's
column-schema map. Missing/null/extra fields do not select a calendar, timezone
or time bound by default. Original business strings are preserved, including
offsets, fractional seconds and non-normalized calendar identifiers. JSON
serialization is provider DATA, not the Request/Source identity or authority.

`prepareCalendarEventsRequestPages` consumes the caller's same original
CheckEnvironment, obtains its retained Profile and makes the synchronous query
projection in that same Common runtime, then supplies the query to the existing
pure page hooks. It captures methods/receiver and limits before use and performs
no exchange, accounting, grant or cleanup itself. Actual Source publication,
complete parent and original environment delivery must be connected by their
existing owners before this is a normal reader.

The Common runtime's `calendarEventsProfileFromEnvironment` bridge exposes
the exact Profile retained by the supplied original CheckEnvironment, through
the existing `checking_environment_calendar_profile` and
`selected_calendar_profile` accessors. An environment without a selected
artifact refuses; the getter does not admit bytes, select a profile or enable
Calendar. Supplying a different environment is not proof of correspondence to
the caller's Source or Run. The shared Host must retain and supply that same
checked-environment original at its actual preparation boundary. This keeps the
provider's request/page conversion independent of ambient timezone state.

The Profile's zone Map must be consumed by the same compiler namespace that
issued it. The pinned JS runtime's default string hash seed belongs to its
module; moving a retained Map to another compiled module does not move that
module's lookup seed. Calendar Events therefore keeps the Profile getter,
request/query and typed page/row operations together in the Common module.
The separate Calendar provider retains stateless schema/facts/column wire
projections, not a duplicate opaque Events API path. Do not serialize and
re-admit the Profile, fix a global seed, remap a namespace or infer authority
from equal CIDs to bypass this original-value boundary.

Publication and physical reading must still bind the actual original calendar,
timezone, selected profile and response to the same checked acquisition. The
shared Host owns current authorization, original request/response custody,
simultaneous constructor and output reservations, cancellation and cleanup.
The temporal projection neither issues that backing nor acknowledges retirement.
