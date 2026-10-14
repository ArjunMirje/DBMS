# Verification and current limits

## Automatic-input update checked on 2026-10-14

Nine Python checks passed using the installed Flask and MySQL Connector libraries with controlled database connections:

- The real worker produced three batches with measured intervals of 9.997 and 10.011 seconds. Starting it twice kept one worker.
- Each tick opened its own connection, began a transaction, committed its batch, and closed the connection through context teardown.
- A failed second insertion rolled back the batch and closed the cursor.
- Inactive status skipped automatic input; the deliberate rollback demonstration remained available without committing.
- A failed automatic batch retried successfully at the next tick.
- Read-only page/fragment requests preserved sensor and inclusive date filters; all dashboard queries and status/acknowledgement writes were restricted to Satellite-01.
- Current/all views chose the correct query limit and retained filters when switching.
- Alert rows displayed reading IDs while submitting the correct internal alert IDs.
- Background acknowledgement returned JSON without a redirect, including validation and database-failure responses.

JavaScript checks passed in Node for the ten-second refresh timer, retained URL filters, GET-only fetching, preservation of a focused alert button, retry after an HTTP failure, and background acknowledgement success/failure without navigation. Python compilation and JavaScript syntax checks also passed. The changed page rendered successfully through Flask's test client.

The updated schema was executed on an isolated MySQL Community Server 8.0.46 instance over local shared memory:

| Database check | Result |
|---|---|
| Fresh seed | 1 satellite, 2 sensors, 2 readings, 0 alerts |
| Abnormal committed batch | 4 total readings, 2 alerts |
| Second abnormal batch inside transaction | 6 readings, 4 alerts |
| After rollback | Back to 4 readings, 2 alerts |
| Status update | Satellite-01 became Inactive |
| Exact temperature boundaries | Both classified NORMAL |
| Current dashboard SQL | All five SELECTs and the scoped alert UPDATE executed |
| Reading history views | 207 stored rows: Current showed 100; All showed 207 |
| Linked IDs | Alerts 1/2 referred to readings 258/259; acknowledgement updated the matching alert |

The isolated server was stopped after verification. No user database or configuration was changed.

## Verification limits

This execution environment blocks local TCP sockets with Windows error 10013. Consequently, the complete Flask-to-MySQL Connector connection could not be exercised. Five additional integration tests requiring a separate TCP test server were skipped. The database checks above used the real MySQL command-line client, while the Python worker checks used controlled connection objects. These are separate checks, not a claim of a completed driver integration test.

A live browser visual check was not performed. Template rendering and JavaScript behavior were checked separately.

On your installation, keep MySQL running, restart Python, and follow the README demonstration to confirm automatic persistent inserts, live tables, pause/resume, alerts, and rollback through your own connection.

## Reproduce checks

From the project root:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
node tests\test_live.cjs
```

The Node check is optional if Node is not installed. The Python suite normally runs nine checks and skips the five database integration checks. To enable those five checks, start a disposable MySQL server with root/empty-password access on a separate local port, then set `SPACE_TELEMETRY_TEST_PORT` to that port before running the suite. Do not use port 3306 or your normal project server. The integration suite creates and drops only its uniquely named test database.
