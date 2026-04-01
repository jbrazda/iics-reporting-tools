# Plan: CDI Support, Nested ZIP Extraction, Caching & REST API

## Problem Statement

The current tool only supports IICS CAI (Cloud Application Integration) assets stored as XML.
Exported IICS packages also contain **nested ZIP files** holding **CDI (Cloud Data Integration)**
assets (Mappings, Mapping Tasks, Taskflows) stored as JSON. This plan adds:

1. Extraction and indexing of nested ZIPs from an uploaded package
2. A new CDI metadata analysis module (JSON-based, parallel to `ipd-metadata.xqm`)
3. A dependency graph cache to avoid repeated expensive recursive traversals
4. A JSON REST API layer to decouple data from HTML rendering
5. Visualization of dependency graphs using vis.js (already in sample-data)

---

## IICS Asset Type Reference

Full asset type list from the
[IICS Platform REST API v3 - Finding an Asset](https://docs.informatica.com/cloud-common-services/administrator/current-version/rest-api-reference/platform-rest-api-version-3-resources/objects/finding-an-asset.html).

### Data Integration (CDI) Asset Types

| API Type       | Display Name               | Nested ZIP Extension | JSON file                 | Support Status |
|----------------|----------------------------|----------------------|---------------------------|----------------|
| `DTEMPLATE`    | Mapping                    | `.DTEMPLATE.zip`     | `mappingTemplate.json`    | SUPPORTED      |
| `MTT`          | Mapping Task               | `.MTT.zip`           | `mtTask.json`             | SUPPORTED      |
| `DSS`          | Synchronization Task       | `.DSS.zip`           | (not verified)            | INDEXED only   |
| `DMASK`        | Masking Task               | `.DMASK.zip`         | (not verified)            | INDEXED only   |
| `DRS`          | Replication Task           | `.DRS.zip`           | (not verified)            | INDEXED only   |
| `DMAPPLET`     | Mapplet (Data Integration) | `.DMAPPLET.zip`      | (not verified)            | INDEXED only   |
| `MAPPLET`      | PowerCenter Mapplet        | `.MAPPLET.zip`       | `mappingTemplate.json`    | INDEXED only   |
| `BSERVICE`     | Business Service           | `.BSERVICE.zip`      | `businessService.json`    | INDEXED only   |
| `HSCHEMA`      | Hierarchical Schema        | `.HSCHEMA.zip`       | `hschema.json`            | INDEXED only   |
| `PCS`          | PowerCenter Task           | `.PCS.zip`           | (not verified)            | INDEXED only   |
| `FWCONFIG`     | Fixed Width Configuration  | `.FWCONFIG.zip`      | `fwConfig.json`           | INDEXED only   |
| `CUSTOMSOURCE` | Saved Query                | `.CUSTOMSOURCE.zip`  | (not verified)            | INDEXED only   |
| `MI_TASK`      | Mass Ingestion Task        | `.MI_TASK.zip`       | (not verified)            | INDEXED only   |
| `WORKFLOW`     | Linear Taskflow            | `.WORKFLOW.zip`      | (not verified)            | INDEXED only   |
| `TASKFLOW`     | Taskflow                   | `.TASKFLOW.zip`      | (not verified)            | INDEXED only   |
| `UDF`          | User-Defined Function      | `.UDF.zip`           | (not verified)            | INDEXED only   |
| `Connection`   | CDI Connection             | `.Connection.zip`    | `connection.json`         | SUPPORTED      |
| `AgentGroup`   | Secure Agent Group         | `.AgentGroup.zip`    | `runtimeEnvironment.json` | INDEXED only   |

> "INDEXED only" means `cdi:index-nested-zip` stores the JSON as binary in the DB,
> but no query functions or UI tables exist for those types yet.
> "not verified" means the nested ZIP extension is an assumption based on the API type code;
> no package with that type has been inspected yet.

### Application Integration (CAI) Asset Types

| API Type               | Display Name       | MIME Type                            | XML Extension               | Support Status |
|------------------------|--------------------|--------------------------------------|-----------------------------|----------------|
| `PROCESS`              | Process            | `application/xml+process`            | `.PROCESS.xml`              | SUPPORTED      |
| `GUIDE`                | Guide (Screenflow) | `application/xml+screenflow`         | `.GUIDE.xml`                | SUPPORTED      |
| `AI_CONNECTION`        | Connection         | `application/xml+connection`         | `.AI_CONNECTION.xml`        | SUPPORTED      |
| `AI_SERVICE_CONNECTOR` | Service Connector  | `application/xml+businesssconnector` | `.AI_SERVICE_CONNECTOR.xml` | SUPPORTED      |
| `PROCESS_OBJECT`       | Process Object     | `application/xml+processobject`      | `.PROCESS_OBJECT.xml`       | SUPPORTED      |
| `TASKFLOW`             | Task Flow          | `application/xml+taskflow`           | `.TASKFLOW.xml`             | SUPPORTED      |

### B2B Gateway Asset Types

| API Type         | Display Name | Format     | Support Status |
|------------------|--------------|------------|----------------|
| `B2BGW_CUSTOMER` | B2B Customer | Nested ZIP | NOT SUPPORTED  |
| `B2BGW_SUPPLIER` | B2B Supplier | Nested ZIP | NOT SUPPORTED  |
| `B2BGW_MONITOR`  | B2B Monitor  | Unknown    | NOT SUPPORTED  |

### Other Asset Types (MDM, Data Quality, Profiling)

MDM SaaS, Data Quality, and Data Profiling types (`MDM_*`, `CLEANSE`, `DEDUPLICATE`,
`DICTIONARY`, `EXCEPTION`, `LABELER`, `PARSE`, `RULE_SPECIFICATION`, `VERIFIER`,
`PROFILE`) are out of scope for this plan.

---

## Test Package

Primary test package for CDI functionality:

- **Linux path**: `/home/jbrazda/Downloads/NATL_ClaimCenter_GW.zip`
- Upload via the web UI at `http://localhost:8984/iics/database`
  or run: `ant basex.create.db -Dbasex.source=/home/jbrazda/Downloads/NATL_ClaimCenter_GW.zip`

### Package Contents (NATL_ClaimCenter_GW.zip - verified 2026-03-30)

| Category       | Count | Notes                                             |
|----------------|-------|---------------------------------------------------|
| Total entries  | 547   | -                                                 |
| XML documents  | 364   | CAI assets (Processes, Guides, Connections, etc.) |
| Nested ZIPs    | 73    | CDI assets (see breakdown below)                  |
| Top-level JSON | 1     | `exportMetadata.v2.json` only                     |

Nested ZIP breakdown by type:

| Extension         | Count | JSON file inside          | Asset type                  |
|-------------------|-------|---------------------------|-----------------------------|
| `.DTEMPLATE.zip`  | 25    | `mappingTemplate.json`    | CDI Mapping Template        |
| `.MTT.zip`        | 23    | `mtTask.json`             | CDI Mapping Task            |
| `.Connection.zip` | 17    | `connection.json`         | CDI Connection              |
| `.BSERVICE.zip`   | 4     | `businessService.json`    | CDI Business Service        |
| `.FWCONFIG.zip`   | 2     | `fwConfig.json`           | CDI Format/Framework Config |
| `.HSCHEMA.zip`    | 1     | `hschema.json`            | CDI Hierarchical Schema     |
| `.AgentGroup.zip` | 1     | `runtimeEnvironment.json` | Secure Agent Group          |

Folder structure (top-level projects under `Explore/`):
`ClaimCenter_GW`, `PerceptiveContent`, `Connections`, `Esignature`, `DAS`, `Connectors`,
`Logging`, `Tools`

Secondary test packages on the Linux server:

- `/home/jbrazda/Downloads/s3_test/CI-CD-Demo_2021-04-07-172924_a5f9150d.zip`
  Used for Phase 1 and Phase 2 verification (1 mapping, 1 task, 2 connections confirmed)

---

## Root Cause Analysis - CDI Assets Not Appearing (2024-03-30)

Direct inspection of the running BaseX server and available IICS packages on this host
revealed three separate bugs:

### Bug 1 - `db:create` + `db:store` transaction conflict

`iics:create-db-from-zip` issues `db:create($dbname, ...)` and then
`db:store($dbname, $path, $binary)` in the **same updating transaction**.
In BaseX XQuery Update, all pending updates are applied at the end of the transaction.
`db:store` internally calls `db:open` during evaluation - but the database does not
exist yet (it is only in the pending update list). This causes a silent failure:

```text
[db:open] Database '...' was not found.
```

**Fix**: Remove nested ZIP `db:store` calls from `iics:create-db-from-zip`.
Write nested ZIP content to the filesystem temp file that is already created
by the upload handler. The background job reads from the filesystem ZIP, not the DB.

### Bug 2 - Wrong nested ZIP JSON file names

`cdi-metadata.xqm` looks for paths ending in `/mapping.json`, `/mappingtask.json`,
`/taskflow.json`. Actual IICS CDI package structure uses different file names.
See [IICS Asset Type Reference](#iics-asset-type-reference) for the full type list.
Key types verified in surveyed packages:

| API Type     | Nested ZIP extension | JSON file inside       |
|--------------|----------------------|------------------------|
| `DTEMPLATE`  | `.DTEMPLATE.zip`     | `mappingTemplate.json` |
| `MTT`        | `.MTT.zip`           | `mtTask.json`          |
| `Connection` | `.Connection.zip`    | `connection.json`      |
| `BSERVICE`   | `.BSERVICE.zip`      | `businessService.json` |
| `FWCONFIG`   | `.FWCONFIG.zip`      | `fwConfig.json`        |
| `HSCHEMA`    | `.HSCHEMA.zip`       | `hschema.json`         |

No standalone CDI Taskflow nested ZIPs were found in the surveyed packages.
CAI Taskflows remain as `.TASKFLOW.xml` files in the top-level ZIP.

**Fix**: Update all path filters and JSON field names.

### Bug 3 - Top-level JSON files not indexed

Packages contain useful JSON at the top level that is currently ignored:

- `exportMetadata.v2.json` - maps `objectGuid` (federatedId) to `objectName` and `objectType`
- `*.Folder.json` - folder metadata

**Fix**: Store top-level JSON files via the background job (after DB exists).

### Actual CDI JSON Structures (verified from package inspection)

**`mappingTemplate.json`** (inside `.DTEMPLATE.zip`):

```json
{
  "@type": "mappingTemplate",
  "id": "@1",
  "name": "m_SFDC_FF_Accounts",
  "references": [
    { "@type": "reference", "refObjectId": "@5l6TgukGvc1h0NhBtswVGw", "refType": "connection" }
  ]
}
```

**`mtTask.json`** (inside `.MTT.zip`):

```json
{
  "@type": "mtTask",
  "id": "@1",
  "name": "mct_SFDC_FF_Accounts",
  "mappingId": "@536izJoEyCkfW49hApXpMN",
  "parameters": [
    { "type": "EXTENDED_SOURCE", "sourceConnectionId": "@hz1mAolBHYcb5lvDNIpaQa" },
    { "type": "TARGET", "targetConnectionId": "@5l6TgukGvc1h0NhBtswVGw" }
  ]
}
```

**`connection.json`** (inside `.Connection.zip`):

```json
{
  "@type": "connection",
  "id": "@1",
  "name": "Salesforce",
  "federatedId": "hz1mAolBHYcb5lvDNIpaQa"
}
```

**Cross-reference format**: `refObjectId` / `mappingId` / `sourceConnectionId` values are
`"@" + federatedId`. Strip the leading `@` to resolve to the connection's `federatedId`.

**`exportMetadata.v2.json`** (top-level):

```json
{
  "exportedObjects": [
    { "objectGuid": "5l6TgukGvc1h0NhBtswVGw", "objectName": "Salesforce", "objectType": "Connection" }
  ]
}
```

---

## Current State Summary

| Area                 | Previous                                 | Current                                                           | Gap                                  |
|----------------------|------------------------------------------|-------------------------------------------------------------------|--------------------------------------|
| Upload               | Extracts `.xml` from top-level ZIP only  | XML + nested ZIP JSON extracted in background job                 | -                                    |
| CDI extraction       | Not supported                            | `cdi:extract-from-package` indexes JSON as binary, XML as docs    | -                                    |
| CDI metadata         | Not supported                            | `cdi-metadata.xqm` queries mappings, tasks, connections           | Cross-package federatedId resolution |
| CDI HTML             | Not supported                            | `cdi-metadata-html.xqm` renders Mappings/Tasks/Connections tables | Detail pages not yet wired           |
| Dependency traversal | Recursive on every page load - expensive | Still recursive                                                   | Phase 3 cache needed                 |
| API                  | All endpoints return HTML only           | Still HTML only                                                   | Phase 4                              |
| Visualization        | DataTables + jQuery UI tabs              | Same                                                              | Phase 5                              |

---

## Architecture Overview (implemented)

```text
Upload ZIP
   |
   +-- iics:create-db-from-zip (Transaction 1 - sync) [IMPLEMENTED]
   |     +-- Extract .xml -> fn:parse-xml() -> db:create()
   |     +-- Write original ZIP to temp file (iics:upload / iics:upload-overwrite)
   |     +-- Schedule background job -> jobs:eval(dbname, zipPath)
   |
   +-- Background Job: cdi:extract-from-package($dbname, $zipPath) (Transaction 2 - async) [IMPLEMENTED]
         +-- Store top-level JSON via db:store() as binary
         |    (exportMetadata.v2.json, *.Folder.json)
         +-- For each nested .zip entry:
         |    +-- archive:extract-binary() -> cdi:index-nested-zip()
         |    +-- JSON: db:store() as xs:base64Binary (for json:parse later)
         |    +-- XML: fn:parse-xml() -> db:add()
         +-- Delete temp ZIP file
         +-- (Future Phase 3) Trigger cache pre-computation job
```

---

## Phase 1 - Nested ZIP Extraction Background Job [COMPLETE - commit 60cdd0d, 559903a, c86754e]

### Files changed

- `databases/databases.xqm`
- `modules/cdi-extract.xqm` (new)

### What was implemented

**`databases.xqm` - `iics:create-db-from-zip`** now creates an XML-only database:

```xquery
let $allEntries := archive:entries($zip)/string()
let $xmlEntries := $allEntries[ends-with(lower-case(.), '.xml')
                                and not(starts-with(., '__MACOSX/'))]
let $xmlDocs    := archive:extract-text($zip, $xmlEntries)
return db:create($dbname, $xmlDocs, $xmlEntries)
```

**`databases.xqm` - `iics:upload` and `iics:upload-overwrite`** write temp file and schedule job:

```xquery
let $tmpfile := file:temp-dir() || '_iics_upload_' || $name || '.zip'
return (
  file:write-binary($tmpfile, $zip),
  iics:create-db-from-zip($name, $zip),
  update:output(
    let $_ := jobs:eval(
      "import module namespace cdi = 'iics/cdi-extract' at '../modules/cdi-extract.xqm';" ||
      " cdi:extract-from-package($db, $zip)",
      map { 'db': $name, 'zip': $tmpfile },
      map { 'base-uri': file:base-dir() }
    )
    return web:redirect('/iics/report', map { 'database': $name })
  )
)
```

**`cdi-extract.xqm` - `cdi:extract-from-package($dbname, $zipPath)`**:

- Reads ZIP from filesystem via `file:read-binary($zipPath)`
- Stores top-level JSON as binary via `db:store()`
- Expands each nested `.zip` entry via `cdi:index-nested-zip()`
- Deletes the temp file when done

**`cdi-extract.xqm` - `cdi:index-nested-zip($dbname, $zipPath, $zip)`**:

- JSON entries: `db:store($dbname, $basePath || $entry, convert:string-to-base64(...))`
- XML entries: `db:add($dbname, fn:parse-xml($content), $basePath || $entry)`
- Base path derived by stripping `.zip` extension: `replace($zipPath, '\.zip$', '', 'i') || '/'`

### Key technical constraints (BaseX 9.x)

- `db:create` and `db:store` **cannot** be in the same updating transaction
- `db:store` calls `db:open` during evaluation - fails if DB is still in pending update list
- Solution: `db:create` in Transaction 1, `db:store` in Transaction 2 (background job)
- Binary read: `db:retrieve($name, $path)` returns `xs:base64Binary`
- Binary store: `db:store($name, $path, xs:base64Binary)`
- List binary resources: `db:list-details($name)[@raw='true']/text()`
- XQuery regex - no PCRE `(?i)` inline flags; use `replace($s, $pat, $rep, 'i')`

---

## Phase 2 - CDI Metadata Module [COMPLETE - commit fabe799, c86754e]

### Files changed

- `modules/cdi-metadata.xqm` (new)
- `modules/cdi-metadata-html.xqm` (new)
- `designs_report.xqm` (CDI tab added)
- `static/iics-reporting.js` (CDI sub-tabs DataTables init)

### Actual CDI package structure (verified from live packages)

Verified from CI-CD-Demo and NATL_ClaimCenter_GW packages. See the
[IICS Asset Type Reference](#iics-asset-type-reference) table above for the complete
official API type list.

| Asset type          | API Type     | Nested ZIP extension | JSON file inside          | In NATL package |
|---------------------|--------------|----------------------|---------------------------|-----------------|
| Mapping Template    | `DTEMPLATE`  | `.DTEMPLATE.zip`     | `mappingTemplate.json`    | 25              |
| Mapping Task        | `MTT`        | `.MTT.zip`           | `mtTask.json`             | 23              |
| Connection          | `Connection` | `.Connection.zip`    | `connection.json`         | 17              |
| Business Service    | `BSERVICE`   | `.BSERVICE.zip`      | `businessService.json`    | 4               |
| Fixed Width Config  | `FWCONFIG`   | `.FWCONFIG.zip`      | `fwConfig.json`           | 2               |
| Hierarchical Schema | `HSCHEMA`    | `.HSCHEMA.zip`       | `hschema.json`            | 1               |
| Secure Agent Group  | `AgentGroup` | `.AgentGroup.zip`    | `runtimeEnvironment.json` | 1               |
| PC Mapplet          | `MAPPLET`    | `.MAPPLET.zip`       | `mappingTemplate.json`    | 0               |

No standalone CDI Taskflow nested ZIPs found in any surveyed package.
CAI Taskflows remain as `.TASKFLOW.xml` in the top-level ZIP.

> `BSERVICE`, `FWCONFIG`, and `HSCHEMA` assets are indexed by `cdi:index-nested-zip`
> (JSON stored as binary) but have no query functions or UI tables yet.
> Adding UI support is a candidate for Phase 2b or Phase 6 (Unified Catalogue).

### Path patterns (implemented)

```xquery
(: Mappings - inside .DTEMPLATE.zip :)
db:list-details($db)[@raw='true']
  [ends-with(lower-case(text()), '/mappingtemplate.json')]/text()

(: Tasks - inside .MTT.zip :)
db:list-details($db)[@raw='true']
  [ends-with(lower-case(text()), '/mttask.json')]/text()

(: Connections - inside .Connection.zip :)
db:list-details($db)[@raw='true']
  [ends-with(lower-case(text()), '/connection.json')]/text()
```

### JSON parsing (critical: must use `format:'xquery'`)

```xquery
(: WRONG - returns XML document, not XQuery map :)
let $parsed := json:parse($text)

(: CORRECT - returns XQuery map/array :)
let $parsed := json:parse($text, map { 'format': 'xquery' })
```

### Dependency extraction (implemented)

```xquery
(: Mapping -> Connections via references array :)
for $ref in $m?references?*
  where string($ref?refType) = 'connection'
  let $fedId := substring-after(string($ref?refObjectId), '@')
  let $conn  := cdi:getConnectionByFederatedId($dbname, $fedId)
  return <dependency objectName="{$conn?name}" .../>

(: Task -> Mapping via mappingId (strip @ prefix to get federatedId) :)
let $mappingFedId := substring-after(string($t?mappingId), '@')

(: Task -> Connections via parameters array :)
for $p in $t?parameters?*
  let $srcRef := string($p?sourceConnectionId)
  let $tgtRef := string($p?targetConnectionId)
  for $ref in ($srcRef[. != ''], $tgtRef[. != ''])
    ...
```

### CDI Dependency types (implemented)

| From         | Depends On                                                           | Dependency Type                         |
|--------------|----------------------------------------------------------------------|-----------------------------------------|
| Mapping      | Connection (via `references[refType=connection]`)                    | `connectionReference`                   |
| Mapping Task | Mapping (via `mappingId`)                                            | `mappingReference`                      |
| Mapping Task | Connection (via `parameters[sourceConnectionId/targetConnectionId]`) | `sourceConnection` / `targetConnection` |

### HTML rendering (`cdi-metadata-html.xqm`)

Three tabs rendered by `chtml:CDISection($dbname)`:

- **Mappings** - table: Name, Connections count, Path
- **Mapping Tasks** - table: Name, Mapping FederatedId, Path
- **Connections** - table: Name, FederatedId, Type, Path

Detail functions `chtml:MappingDetail` and `chtml:TaskDetail` use name-based lookup.

### Verification (CI-CD-Demo_2021-04-07-172924_a5f9150d.zip)

```text
XML docs: 4
Binary (JSON) resources: 13
  - mappingTemplate.json -> m_SFDC_FF_Accounts (1 mapping)
  - mtTask.json -> mct_SFDC_FF_Accounts (1 task)
  - connection.json -> FF_NA_Staging_Salesforce, Salesforce (2 connections)
Dependencies resolved: m_SFDC_FF_Accounts -> [FF_NA_Staging_Salesforce, Salesforce]
```

### Expected results for NATL_ClaimCenter_GW.zip (pending upload test)

```text
XML docs: 364
Binary (JSON) resources: 73+ (one per nested ZIP entry, plus top-level exportMetadata.v2.json)
CDI assets expected:
  - Mappings: 25 (DTEMPLATE)
  - Mapping Tasks: 23 (MTT)
  - Connections: 17 (Connection)
  - Business Services: 4 (BSERVICE) - indexed but not yet shown in UI
  - Format Configs: 2 (FWCONFIG) - indexed but not yet shown in UI
  - Hierarchical Schemas: 1 (HSCHEMA) - indexed but not yet shown in UI
  - Agent Groups: 1 (AgentGroup) - indexed but not yet shown in UI
```

To run the extraction test directly on the Linux server:

```bash
# Create DB from XML (transaction 1)
/opt/java/library/basex/bin/basex -q "
  let \$zip := file:read-binary('/home/jbrazda/Downloads/NATL_ClaimCenter_GW.zip')
  let \$all := archive:entries(\$zip)/string()
  let \$xml := \$all[ends-with(lower-case(.), '.xml') and not(starts-with(., '__MACOSX/'))]
  return db:create('NATL_ClaimCenter_GW', archive:extract-text(\$zip, \$xml), \$xml)"

# Run CDI extraction (transaction 2)
/opt/java/library/basex/bin/basex -u -q "
  import module namespace cdi = 'iics/cdi-extract'
    at '/opt/java/library/basex/webapp/iics/modules/cdi-extract.xqm';
  cdi:extract-from-package('NATL_ClaimCenter_GW',
    '/home/jbrazda/Downloads/NATL_ClaimCenter_GW.zip')"

# Verify counts
/opt/java/library/basex/bin/basex -q "
  import module namespace cdi = 'iics/cdi-metadata'
    at '/opt/java/library/basex/webapp/iics/modules/cdi-metadata.xqm';
  let \$db := 'NATL_ClaimCenter_GW'
  return ('Mappings: '    || count(cdi:getMappings(\$db)),
          'Tasks: '       || count(cdi:getMappingTasks(\$db)),
          'Connections: ' || count(cdi:getConnections(\$db)))"
```

---

## Phase 3 - Dependency Graph Cache [PENDING]

### Problem

`imf:getObjectDependencies()` and `imf:getObjectImpact()` perform full recursive traversal
on every page load. For large databases (100s of designs) this causes timeouts and poor UX.

### Strategy: Pre-compute on Database Load

After the background extraction job completes, schedule a second job to pre-compute all
dependency and impact trees and store them as JSON in `_cache/` paths.

### Cache Storage Format

```text
_cache/
  deps/{guid}.json     ← Pre-computed dependency tree as JSON
  impact/{guid}.json   ← Pre-computed impact tree as JSON
  graph/{guid}.json    ← vis.js-ready { nodes: [...], edges: [...] } format
  meta/status.json     ← Cache build status { complete: true, built: "2024-...", count: 42 }
```

### Cache Invalidation

- Cache is per-database: when a DB is dropped/replaced, the cache entries go with it
  (they live inside the same BaseX database collection)
- A forced refresh can be triggered via a REST endpoint `POST /iics/api/cache/rebuild?database=X`

### Cache Build Job (new `modules/cache.xqm`)

```xquery
declare %updating function cache:build($dbname as xs:string) {
  let $db := db:open($dbname)
  for $item in $db//rep:Item
    let $guid  := $item/rep:GUID/text()
    let $deps  := imf:getObjectDependencies($db, $item)
    let $impact:= imf:getObjectImpact($db, $item, true())
    let $graph := cache:to-vis-graph($deps, $impact)
    return (
      db:put($dbname, json:serialize($deps),   '_cache/deps/'   || $guid || '.json'),
      db:put($dbname, json:serialize($impact), '_cache/impact/' || $guid || '.json'),
      db:put($dbname, json:serialize($graph),  '_cache/graph/'  || $guid || '.json')
    )
};
```

### Cache Read Pattern (in REST API)

```xquery
declare function api:get-dependencies($dbname, $guid) {
  let $cachePath := '_cache/deps/' || $guid || '.json'
  return
  if (db:exists($dbname, $cachePath)) then
    db:get($dbname, $cachePath)   (: fast: ~1ms :)
  else
    let $db   := db:open($dbname)
    let $item := imf:getDesignByGuid($db, $guid)
    return imf:getObjectDependencies($db, $item)   (: fallback: slow :)
};
```

---

## Phase 4 - REST/JSON API Layer [PENDING]

### New file: `api.xqm`

All endpoints return `application/json`. These serve the vis.js graph UI and can support
future external consumers.

### Endpoint Design

| Method | Path                                              | Returns                                      |
|--------|---------------------------------------------------|----------------------------------------------|
| GET    | `/iics/api/databases`                             | `[{name, resources, modified}]`              |
| GET    | `/iics/api/designs?database=X`                    | `[{guid, name, displayName, type, status}]`  |
| GET    | `/iics/api/design?database=X&guid=Y`              | `{guid, name, type, mimeType, ...}`          |
| GET    | `/iics/api/design/dependencies?database=X&guid=Y` | `{nodes:[...], edges:[...]}` (vis.js format) |
| GET    | `/iics/api/design/impact?database=X&guid=Y`       | `{nodes:[...], edges:[...]}` (vis.js format) |
| GET    | `/iics/api/cache/status?database=X`               | `{complete, built, count}`                   |
| POST   | `/iics/api/cache/rebuild?database=X`              | `{jobId}` (triggers background job)          |
| GET    | `/iics/api/cdi/mappings?database=X`               | CDI mapping list                             |
| GET    | `/iics/api/cdi/tasks?database=X`                  | CDI task list                                |
| GET    | `/iics/api/cdi/taskflows?database=X`              | CDI taskflow list                            |

### Response Format for Graph Endpoints

```json
{
  "nodes": [
    {"id": "guid1", "label": "MP_SFtoSAP",  "group": "mapping",  "title": "Mapping"},
    {"id": "guid2", "label": "Salesforce",   "group": "connection","title": "Connection"}
  ],
  "edges": [
    {"from": "guid1", "to": "guid2", "label": "SOURCE", "arrows": "to"}
  ]
}
```

### XQuery JSON serialization

```xquery
declare
  %rest:path("/iics/api/design/dependencies")
  %rest:query-param("database", "{$db}")
  %rest:query-param("guid",     "{$guid}")
  %output:method("text")
  %output:media-type("application/json")
function api:dependencies($db as xs:string, $guid as xs:string) {
  let $data := api:get-dependencies($db, $guid)  (: cache-aware :)
  return serialize($data, map { 'method': 'json' })
};
```

---

## Phase 5 - Visualization with vis.js [PENDING]

### Recommendation: vis.js Network (already chosen)

The project already has `sample-data/graph-vis/basic.html` with vis.js. This is the right choice:

- **vis.js Network**: ideal for dependency graphs (directed graphs with arrows, groups, clustering)
- **Layout options**: `hierarchical` for dependency tree top-down; `force-directed` for full network
- Already used in the project's prototype

### Alternative Options (for awareness)

| Library              | Strength                                     | Weakness                         |
|----------------------|----------------------------------------------|----------------------------------|
| **vis.js Network**   | Already adopted; good defaults; interactive  | Large bundle (~600KB)            |
| **Cytoscape.js**     | Purpose-built for graphs; fast; DAGRE layout | More complex API                 |
| **D3.js**            | Maximum flexibility                          | Requires significant custom code |
| **Mermaid.js**       | Simple DSL; easy static diagrams             | Poor for interactive exploration |

**Recommendation**: Keep vis.js for interactive graph views. Add Mermaid.js as a secondary
simple tree renderer for lightweight dependency summary views.

### New endpoint: `/iics/graph`

New `graph.xqm` serving a single-page graph explorer:

- Loads vis.js + `iics-reporting.js` additions
- Fetches graph data from `/iics/api/design/dependencies?database=X&guid=Y`
- Controls: layout toggle (hierarchical ↔ network), zoom, highlight path to root
- Sidebar: design metadata, click node to navigate to its design detail

### UI Changes to `design_detail.xqm`

Add a 4th tab "Dependency Graph" to the existing tabs:

- Renders `<div id="dep-graph" style="height:500px">` via vis.js
- Async data load via `fetch('/iics/api/design/dependencies?...')` 
- No page reload needed — graph data comes from the JSON API

---

## Phase 6 - Unified Asset Registry [PENDING]

To support both CAI and CDI in the same reporting views, create a unified asset catalogue
stored in `_meta/catalogue.json` per database:

```json
{
  "assets": [
    {"guid": "...", "name": "...", "type": "PROCESS",       "engine": "CAI", "path": "..."},
    {"guid": "...", "name": "...", "type": "MAPPING",       "engine": "CDI", "path": "..."},
    {"guid": "...", "name": "...", "type": "MAPPING_TASK",  "engine": "CDI", "path": "..."},
    {"guid": "...", "name": "...", "type": "TASKFLOW_CDI",  "engine": "CDI", "path": "..."}
  ]
}
```

This catalogue is built once at load time by the background job and updated incrementally.
The `databases.xqm` list page and REST API both read from it for fast asset enumeration.

---

## Implementation Priority / Phasing

| Phase                     | St  atus       | Priority | Effort | Value                              |
|---------------------------|----------------|----------|--------|------------------------------------|
| 1 - Nested ZIP extraction | DONE (c86754e) | HIGH     | Medium | Unlocks CDI                        |
| 2 - CDI metadata module   | DONE (c86754e) | MEDIUM   | High   | New asset type support             |
| 3 - Dependency cache      | PENDING        | HIGH     | Medium | Performance fix for existing pages |
| 4 - REST API (`api.xqm`)  | PENDING        | HIGH     | Medium | Foundation for graph UI            |
| 5 - vis.js graph view     | PENDING        | MEDIUM   | Medium | UX improvement                     |
| 6 - Unified catalogue     | PENDING        | LOW      | Low    | Polish                             |

---

## Key Technical Notes

### BaseX JSON Support

- JSON stored as **binary** via `db:store($name, $path, xs:base64Binary)`
  (storing as text/XML causes parsing issues at retrieval time)
- Retrieve: `let $bin := db:retrieve($name, $path)`
- Parse to XQuery map: `json:parse(convert:binary-to-string($bin, 'UTF-8'), map{'format':'xquery'})`
  - **Critical**: must use `map{'format':'xquery'}` - default format returns XML, not maps
- Array iteration: `$map?arrayKey?*`
- Serialize to JSON: `serialize($data, map{'method':'json'})`

### BaseX Background Jobs

- `jobs:eval($query, $bindings, $options)` → returns job ID
- `jobs:finished($id)` → check completion
- Jobs run in separate transactions — database writes need `%updating`
- Use `jobs:result($id)` to retrieve results if needed

### BaseX RESTXQ JSON Response

- `%output:method("text")` + `%output:media-type("application/json")`
- Or use BaseX's `%output:method("json")` with serialization parameters

### Dependency Graph → vis.js Conversion

Convert the existing XML dependency structure to vis.js nodes/edges:

```xquery
declare function cache:to-vis-graph($deps as element()) as map(*) {
  let $nodes := map:merge((
    map:entry($deps/@guid/string(), map {
      'id': $deps/@guid/string(), 'label': $deps/@object/string(), 'group': 'root'
    }),
    for $d in $deps//dependency
      return map:entry($d/@toGuid/string(), map {
        'id': $d/@toGuid/string(), 'label': $d/@objectName/string(),
        'group': lower-case($d/@referenceType/string())
      })
  ))
  let $edges := for $d in $deps//dependency
    return map {
      'from': $d/@fromGuid/string(), 'to': $d/@toGuid/string(),
      'label': $d/@referenceType/string(), 'arrows': 'to'
    }
  return map { 'nodes': map:values($nodes), 'edges': array { $edges } }
};
```

---

## Todos

| ID            | Phase                                              | Status  |
|---------------|----------------------------------------------------|---------|
| p1-extract    | Phase 1 - Nested ZIP extraction                    | DONE    |
| p2-cdi-module | Phase 2 - CDI metadata module                      | DONE    |
| p3-cache      | Phase 3 - Dependency cache (`modules/cache.xqm`)   | PENDING |
| p4-api        | Phase 4 - JSON REST API layer (`api.xqm`)          | PENDING |
| p5-vis        | Phase 5 - vis.js graph visualization (`graph.xqm`) | PENDING |
| p6-catalogue  | Phase 6 - Unified CAI+CDI asset catalogue          | PENDING |
