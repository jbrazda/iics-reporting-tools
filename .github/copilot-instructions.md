# Copilot Instructions — IICS Reporting Tools

## Project Overview

This is an **IICS (Informatica Intelligent Cloud Services) Design Reporting Tool** — a web application deployed on [BaseX](https://basex.org/) (an XML database and HTTP server) that generates HTML reports from exported IICS asset packages. Reports cover design statistics, dependency trees, and impact analysis for IICS object types (Service Connectors, Connections, Process Objects, Processes, Guides, Task Flows).

The primary language is **XQuery** (RESTXQ for HTTP endpoints). The build/deploy system is **Apache Ant**.

---

## Build & Deploy Commands

All commands use Apache Ant. Run from the repository root.

| Command                      | Purpose                                                                          |
| ---------------------------- | -------------------------------------------------------------------------------- |
| `ant install.all`            | Install BaseX, deploy the web app, and start the HTTP server                     |
| `ant basex.install`          | Install BaseX DB and tools only                                                  |
| `ant basex.deploy.webapps`   | Deploy/redeploy the XQuery app to a running BaseX instance                       |
| `ant basex.configure`        | Interactive configuration wizard (writes `~/.iics.reporting.properties`)         |
| `ant basexhttp.start`        | Start the BaseX HTTP server (available at `http://localhost:8984`)               |
| `ant basexhttp.stop`         | Stop the BaseX HTTP server                                                       |
| `ant basex.sample.db.create` | Load the bundled sample IICS design package into a demo database                 |
| `ant basex.create.db`        | Create a new BaseX database from a source file, archive, or directory            |
| `ant basex.drop.db`          | Drop an existing database by name                                                |
| `ant basex.gui`              | Launch the BaseX GUI (useful for inspecting databases and running ad-hoc XQuery) |
| `ant basex.upgrade`          | Upgrade the BaseX runtime to the latest version                                  |
| `ant help`                   | Print available targets with descriptions                                        |

> **Key properties** are in `build.properties`. User-specific overrides (install paths, Java home) go in `~/.iics.reporting.properties`. The default BaseX install location is `/opt/java/library/basex` and the server listens on port **8984**.

There are no automated test or lint commands — validation is done by running the app and verifying report output.

---

## Architecture

### Runtime: BaseX RESTXQ

The app runs inside BaseX's embedded HTTP server. XQuery modules annotated with `%rest:*` annotations define HTTP endpoints (RESTXQ). BaseX serves them automatically when the `.xqm` files are deployed to its `webapp/` directory.

### Source Layout (`src/basex/webapp/iics/`)

```
common.xqm              — Static file serving and shared RESTXQ entry points
designs_report.xqm      — Main overview report (all designs in a database)
design_detail.xqm       — Per-design detail report with dependency/impact trees
databases/
  databases.xqm         — Database/catalog management UI
modules/
  html.xqm              — Page layout wrapper (HTML shell, nav, CSS links)
  ipd-metadata.xqm      — Core analysis logic: parses IICS XML schemas, builds dependency maps
  ipd-metadata-html.xqm — Renders dependency/impact trees and design tables as HTML
  util.xqm              — Small utilities (string helpers, etc.)
static/                 — CSS, JS, SVG icons, and bundled DataTables/Plotly libraries
```

`ipd-metadata.xqm` is the analytical core — it understands the Informatica Cloud XML schemas and extracts relationships between design objects. All report modules depend on it.

### Data Flow

1. User uploads or points BaseX at an IICS export ZIP/directory.
2. Ant creates a BaseX database from that source (`basex.create.db`).
3. The web app queries that database at request time using XQuery.
4. HTML reports are generated server-side and returned directly (no client-side rendering framework).

---

## Key Conventions

### XQuery Module Pattern

Every module begins with a namespace declaration that maps to its URL alias:

```xquery
module namespace mhtml = 'iics/ipd-metadata-html';
```

Imports use explicit `at` paths relative to the module location:

```xquery
import module namespace html = 'iics/html' at 'modules/html.xqm';
```

### RESTXQ Endpoints

HTTP endpoints are declared with BaseX RESTXQ annotations on XQuery functions:

```xquery
declare
  %rest:path("/iics/report")
  %output:method("html")
  %rest:query-param("database", "{$database}", "")
function report:start($database as xs:string) as element(html) { ... };
```

### Informatica XML Namespaces

The IICS design files use several Informatica/Active Endpoints XML namespaces. These are declared at the top of `ipd-metadata.xqm` and must be consistent across modules:

```xquery
declare namespace sfd = "http://schemas.active-endpoints.com/appmodules/screenflow/2010/10/avosScreenflow.xsd";
declare namespace svc = "http://schemas.informatica.com/socrates/data-services/2014/05/business-connector-model.xsd";
```
When adding support for new IICS object types, declare the appropriate namespace here and in any module that needs it.

### Function Documentation

Use XQuery's doc-comment style for public functions:

```xquery
(:~
 : Generates the design detail report.
 : @param  $database  name of the BaseX database to query
 : @return HTML report element
 :)
```

### Variable Declarations for Constants/Maps

Shared constants and type maps are declared as module-level variables:
```xquery
declare variable $mhtml:IPD_TYPES := map {
  "process" : "Process",
  "guide"   : "Guide",
  ...
};
```

### Static Assets

Third-party libraries (DataTables, Plotly) are vendored under `src/basex/webapp/iics/static/external/` — do not reference CDN URLs.

## Markdown Authoring Rules

- Follow [Markdown Lint](https://github.com/DavidAnson/markdownlint) rules in all generated Markdown.
- Do not use em dashes (--) in generated Markdown; use a regular hyphen (-) instead.
- Do not use emojis in generated Markdown; they may not render correctly in all environments.
