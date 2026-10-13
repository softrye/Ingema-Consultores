# InGe+ internal beta diagnostics V01

This internal beta collects sanitized technical diagnostics: device/runtime
capabilities, lifecycle and navigation milestones, aggregate performance,
safe network operation status, and controlled application errors.

It does not collect passwords, tokens, authorization headers, request or
response bodies, emails, phone numbers, full names, typed text, clipboard
content, exact GPS coordinates, documents, photos, attachments, private notes,
Calicata contents, Renditions expense contents, or financial amounts.

Events are appended first to the app-private file
`diagnostics/beta_diagnostics_v01.jsonl`, capped at 2 MiB or 2000 events. They
are uploaded only after successful authentication through the three dedicated
`SECURITY DEFINER` RPCs. The server derives the actor exclusively from
`auth.uid()` and grants clients no direct table DML.
