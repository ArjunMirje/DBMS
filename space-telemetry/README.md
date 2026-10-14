# Space Telemetry Database Management System

A small mid-semester DBMS project using Python, Flask, MySQL, and server-rendered HTML. A simulator automatically generates temperature and battery readings for **Satellite-01 every 10 seconds**. MySQL stores the readings, creates alerts through a trigger, and supplies filtered records and statistics to the frontend.

All data is simulated. The sensor limits are classroom examples. The app does not connect to a real satellite or implement orbital physics. Everything runs locally; no paid service, API key, or token-based system is needed.

## Start here on Windows

Requirements: Python 3.11 or newer, MySQL Server 8.0.16 or newer, and MySQL Workbench (or the MySQL command-line client). Workbench is the editor; MySQL Server must also be running.

1. Extract the ZIP. Open the `space-telemetry` folder in VS Code.
2. In MySQL Workbench, connect to your local MySQL server using your normal account. Open `database/schema.sql` with File > Open SQL Script. Execute the whole script once, including procedures, function, trigger, and sample data. Refresh Schemas. You should see `space_telemetry`.
3. If a database named `space_telemetry` already exists, stop and inspect it. This script intentionally does not delete or overwrite an existing database. After a partial first run, fix the error and run the remaining statements individually; do not blindly rerun the whole script.
4. Open a PowerShell terminal **inside the extracted project folder** and run:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item config.example.ini config.ini
notepad config.ini
```

5. Replace `YOUR_MYSQL_PASSWORD` with the password you use in Workbench. Set the host/port/user if your installation uses different values. Save the file. `%` in a password is accepted because interpolation is disabled. Keep this file private.
6. Start the application:

```powershell
.\.venv\Scripts\python.exe app.py
```

7. Open **http://127.0.0.1:5000** in your browser. Do not double-click the HTML template: Python must render it and connect it to MySQL. Press Ctrl+C in the terminal when you want to stop the app.

### If you already set up the previous version

Restart Python using the same command above. Your existing `config.ini` and database still work; **do not rerun schema.sql**. Existing Satellite-02 records remain stored, but this version displays and generates data only for Satellite-01. A new setup seeds just one satellite with two sensors and two sample readings.

### Reading views and alert IDs

MySQL retains every committed reading. **Current 100 readings** displays the latest 100 matching rows. **All past readings** displays every matching saved row, including the latest ones, with no 100-row limit. Both views preserve sensor/date filters and refresh automatically. With two sensors, each automatic batch adds two reading rows.

The alerts table has its own `alert_id` primary key and a `reading_id` foreign key. They are different identifiers: alert 6 can belong to reading 182. The frontend now labels and displays **Reading ID**, so the alert row and reading row match. Acknowledgement still updates the alert using its internal alert ID.

With JavaScript enabled, Acknowledge sends a background POST and changes that row to Acknowledged. It keeps the page, filters, and scroll position. If a request fails, a short error appears and the button becomes usable again. Without JavaScript, the existing form submission remains available and reloads the page.

### Automatic input

The first batch is saved when Python starts, followed by one batch every 10 seconds. Each batch contains one temperature reading and one battery reading, using the configured sensor limits. Both readings commit together through the existing `add_reading` procedure. The database trigger still handles abnormal readings.

Input continues while the browser is closed. Keep Python and MySQL running. Browser JavaScript fetches the saved readings, alerts, and summaries every 10 seconds without reloading forms or clearing filters; fetching data does not generate it. Multiple browser tabs use the same server simulator.

Set Satellite-01 to **Inactive** and save to pause new input. Set it back to **Active** to resume at the next scheduled interval. Stop Python with Ctrl+C to stop the simulator entirely. If a database connection or batch fails, the simulator retries at the next interval. Slow or failed batches do not cause a burst of missed readings.

Use the documented `python app.py` entry point, with one local Python server process. Importing `app` for tests or launching only `flask run` does not start the simulator. The development reloader is disabled to avoid starting another simulator.

No virtual-environment activation is required, so PowerShell execution-policy issues are avoided. If `python` is unavailable but `py` works, use `py -3` for the first command. Package installation needs an internet connection; the running project does not.

## What is included

- One monitored satellite, with its mission and sensor settings displayed.
- Automatic temperature and battery input every 10 seconds, with live table updates.
- Satellite status updates; Inactive pauses automatic input and committed manual batches.
- Normal and deliberately abnormal readings, one per configured sensor.
- Atomic batch insertion using a stored procedure and a trigger.
- A rollback demonstration that discards both inserted readings and generated alerts.
- Reading filters by sensor and inclusive start/end date, scoped to Satellite-01.
- Alert acknowledgement without a page reload and all-time per-sensor statistics.
- Current 100 readings and All past readings views, preserving sensor/date filters.
- Alerts display the associated reading ID; their separate internal alert ID remains the update key.
- Five InnoDB tables with keys, constraints, and a sensor/time index.
- Additional SQL review queries, an ER/normalization explanation, and a line-by-line code guide.

## Five-minute review demonstration

1. Show the five tables in Workbench and explain their relationships.
2. Open the page. New setups have one satellite, two sensors, two sample readings, and no seed alerts. Existing setups retain their earlier data.
3. Wait 20 seconds. Two new readings arrive every 10 seconds, and the tables refresh automatically.
4. Choose Abnormal readings and click Generate once. Two readings and two alerts are committed.
5. Set Satellite-01 to Inactive. Note the summary counts and alert IDs, then choose Rollback demonstration. The counts and rows remain unchanged, although MySQL may consume auto-increment IDs during a rolled-back transaction. Rollback mode works while Inactive because it saves nothing.
6. Filter by one of its sensors. Acknowledge an alert to show persistence.
7. Keep it Inactive for at least 10 seconds and confirm no new readings appear.
8. Set Active and save. Automatic input resumes at the next interval.
9. Show `database/review_queries.sql` for JOIN, GROUP BY/HAVING, subquery, UNION, rollback, and EXPLAIN examples.

## Read the code in this order

1. `database/schema.sql`: what data exists and how MySQL manages it.
2. `app.py`: how form submissions become database operations.
3. `templates/index.html`: what the user sees and submits.
4. `static/style.css`: basic layout only.
5. `docs/LINE_BY_LINE.md`: explanation of every source line.
6. `docs/DATABASE_DESIGN.md`: ER model, dependencies, normalization, and Unit 1–4 mapping.

The frontend uses HTML forms and Flask's Jinja templates, with a small `static/live.js` script for automatic table refresh and background acknowledgement. `templates/_telemetry.html` holds the shared tables used by the initial page and the read-only `/live` endpoint. There is no JavaScript framework or separate frontend build. `{{ ... }}` prints a value, `{% for ... %}` repeats markup, and `{% if ... %}` conditionally includes markup. Flask escapes displayed user text by default.

## Mid-semester scope

The original core was estimated at roughly 65% of the agreed classroom scope. Timed simulation and pause/resume are now implemented, so that original percentage needs reassessment. Remaining final-review work: CSV export and richer reports, a two-session concurrency experiment, and a tested backup/restore workflow with a larger query-optimization dataset.

## Troubleshooting

- **Cannot complete the database request:** check that MySQL Server is running; verify the credentials and port in `config.ini`; confirm that all schema statements ran successfully. Check the terminal for the MySQL error code.
- **Copy config.example.ini message:** create `config.ini` beside `app.py`.
- **Database already exists (1007):** the script protects existing data. Use the already-created project database if complete, or inspect a partial setup before continuing.
- **Unknown function/procedure or missing table:** run the corresponding remaining statements from `schema.sql` in Workbench.
- **Function privilege error during setup:** run setup using your normal local MySQL administrator account. The function is declared `DETERMINISTIC NO SQL`; do not change global server settings just to bypass a privilege error.
- **Duplicate name/sensor:** mission and spacecraft names must be unique. Each spacecraft can have one Temperature sensor and one Battery sensor.
- **No sensors or missing satellite:** check that Satellite-01 and its Temperature/Battery sensors exist in the database. Existing setups already contain them; inspect the seed section of schema.sql if setup was incomplete.
- **Tables do not refresh:** enable JavaScript or refresh the page manually. Automatic insertion runs on the server independently of JavaScript.
- **Port 5000 occupied:** stop an older copy of this app, or change the port in the final `app.run` line and open the matching URL.

This is a localhost classroom prototype without login or internet deployment. Keep its scope local. Deleting telemetry and editing historical readings are intentionally excluded from the frontend; DELETE is demonstrated in the separate review SQL file.

## Official references

- Flask quickstart: https://flask.palletsprojects.com/en/stable/quickstart/
- MySQL Connector/Python installation: https://dev.mysql.com/doc/connector-python/en/ch04s04s01.html
- MySQL transactions: https://dev.mysql.com/doc/refman/8.0/en/commit.html
- MySQL stored routines: https://dev.mysql.com/doc/refman/8.0/en/create-procedure.html
