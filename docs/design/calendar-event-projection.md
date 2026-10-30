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
expand a recurrence, infer attendance or turn a cancelled tombstone into a
complete Event. Full event-row projection must separately interpret cancelled
items whose original response has no temporal pair, and preserve the complete
declared cells before query projection.

Publication and physical reading must still bind the actual original calendar,
timezone, selected profile and response to the same checked acquisition. The
shared Host owns current authorization, original request/response custody,
simultaneous constructor and output reservations, cancellation and cleanup.
The temporal projection neither issues that backing nor acknowledges retirement.
