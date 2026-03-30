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

## Root Cause Analysis - CDI Assets Not Appearing (2024-03-30)

Direct inspection of the running BaseX server and available IICS packages on this host
revealed three separate bugs:

### Bug 1 - `db:create` + `db:store` transaction conflict

`iics:create-db-from-zip` issues `db:create($dbname, ...)` and then
`db:store($dbname, $path, $binary)` in the **same updating transaction**.
In BaseX XQuery Update, all pending updates are applied at the end of the transaction.
`db:store` internally calls `db:open` during evaluation - but the database does not
exist yet (it is only in the pending update list). This causes a silent failure:

```
[db:open] Database '...' was not found.
```

**Fix**: Remove nested ZIP `db:store` calls from `iics:create-db-from-zip`.
Write nested ZIP content to the filesystem temp file that is already created
by the upload handler. The background job reads from the filesystem ZIP, not the DB.

### Bug 2 - Wrong nested ZIP JSON file names

`cdi-metadata.xqm` looks for paths ending in `/mapping.json`, `/mappingtask.json`,
`/taskflow.json`. Actual IICS CDI package structure uses different file names:

| Asset type | Nested ZIP extension | JSON file inside |
|-----------|---------------------|-----------------|
| Mapping Template | `.DTEMPLATE.zip` | `mappingTemplate.json` |
| Mapping Task | `.MTT.zip` | `mtTask.json` |
| Connection | `.Connection.zip` | `connection.json` |
| Mapplet | `.MAPPLET.zip` | (complex binary format) |
| B2B Customer | `.B2BGW_CUSTOMER.zip` | - |

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

| Area | Current | Gap |
|------|---------|-----|
| Upload | Extracts `.xml` files from top-level ZIP only | Nested ZIPs, JSON files ignored |
| Metadata analysis | `ipd-metadata.xqm` - full CAI XML support | No CDI JSON support |
| Dependency traversal | Recursive on every page load - expensive | No caching; blocks HTTP response |
| API | All endpoints return HTML only | No JSON API for graph UIs or external consumers |
| Visualization | DataTables + jQuery UI tabs | No graph/network visualization |

---

## Architecture Overview (revised)

```
Upload ZIP
   |
   +-- iics:create-db-from-zip (Transaction 1 - sync)
   |     +-- Extract .xml -> parse-xml() -> db:create()
   |     +-- Write original ZIP to temp file (already done by iics:upload)
   |     +-- Schedule background job -> jobs:eval(zipPath)
   |
   +-- Background Job: cdi:extract-from-package($dbname, $zipPath) (Transaction 2 - async)
         +-- Store top-level JSON via db:store()
         |    (exportMetadata.v2.json, *.Folder.json)
         +-- For each nested .zip entry:
         |    +-- archive:extract-binary() -> cdi:index-nested-zip()
         |    +-- JSON files: db:store() as binary (for json:parse later)
         +-- Delete temp ZIP file
         +-- (Future) Trigger cache pre-computation job
```

---

## Phase 1 — Nested ZIP Extraction Background Job (revised)

### Files to change
- `databases/databases.xqm` — trigger background job after DB creation
- `modules/cdi-extract.xqm` (NEW) — background extraction logic

### Approach

**Step 1a – Extend `iics:create-db-from-zip`** to also store nested ZIPs as binary:

```xquery
let $allEntries   := archive:entries($zip)/string()
let $xmlEntries   := $allEntries[ends-with(lower-case(.), '.xml')]
let $zipEntries   := $allEntries[ends-with(lower-case(.), '.zip')]
let $xmlDocs      := archive:extract-text($zip, $xmlEntries)
let $_            := db:create($dbname, $xmlDocs, $xmlEntries)
let $zipBinaries  := archive:extract-binary($zip, $zipEntries)
(: Store nested ZIPs as binary documents :)
let $_            := for-each-pair($zipEntries, $zipBinaries,
                       function($path, $bin) { db:put-binary($dbname, $bin, $path) })
(: Schedule extraction job :)
return jobs:eval(
  "import module namespace cdi = 'iics/cdi-extract' at 'modules/cdi-extract.xqm';
   cdi:process-nested-zips($dbname)",
  map { 'dbname': $dbname },
  map { 'base-uri': file:base-dir() }
)
```

**Step 1b – `cdi-extract.xqm`** background processing:

```xquery
declare %updating function cdi:process-nested-zips($dbname as xs:string) {
  let $db := db:open($dbname)
  for $path in db:list-details($dbname)[ends-with(@path, '.zip')]/@path/string()
    let $zip     := db:get-binary($dbname, $path)
    let $entries := archive:entries($zip)/string()
    let $jsonEntries := $entries[ends-with(lower-case(.), '.json')]
    let $xmlEntries  := $entries[ends-with(lower-case(.), '.xml')]
    let $basePath    := replace($path, '\.zip$', '') || '/'
    return (
      for-each-pair($jsonEntries, archive:extract-text($zip, $jsonEntries),
        function($p, $content) {
          db:add($dbname, $content, $basePath || $p)
        }),
      for-each-pair($xmlEntries, archive:extract-text($zip, $xmlEntries),
        function($p, $content) {
          db:add($dbname, $content, $basePath || $p)
        }),
      db:delete($dbname, $path)  (: Remove raw binary after extraction :)
    )
};
```

### CDI JSON Path Conventions (based on known package structure)

```
Explore/
  CDI/
    MP_SomeMapping/
      mapping.json          ← Mapping definition
    MT_SomeTask/
      mappingtask.json      ← Mapping Task
    TF_SomeFlow/
      taskflow.json         ← Taskflow
    connections.json        ← Connection catalog
```

---

## Phase 2 (revised) — CDI Metadata Module

### Files to change

- `modules/cdi-metadata.xqm` - fix path patterns and JSON field accessors
- `modules/cdi-metadata-html.xqm` - update table columns and detail view field names

### Corrected path patterns

```xquery
(: Mappings - inside .DTEMPLATE.zip :)
cdi:mapping-paths($db) :=
  db:list-details($db)[@raw='true']
    [ends-with(lower-case(text()), '/mappingtemplate.json')]/text()

(: Tasks - inside .MTT.zip :)
cdi:task-paths($db) :=
  db:list-details($db)[@raw='true']
    [ends-with(lower-case(text()), '/mttask.json')]/text()

(: Connections - inside .Connection.zip :)
cdi:connection-paths($db) :=
  db:list-details($db)[@raw='true']
    [ends-with(lower-case(text()), '/connection.json')]/text()

(: Package export metadata :)
cdi:metadata-path($db) :=
  db:list-details($db)[@raw='true']
    [ends-with(lower-case(text()), 'exportmetadata.v2.json')]/text()
```

### Corrected dependency extraction

```xquery
(: Mapping -> Connections via references array :)
for $ref in $m?references?*
  where $ref?refType = 'connection'
  let $fedId := substring-after(string($ref?refObjectId), '@')
  let $conn  := cdi:getConnectionByFederatedId($dbname, $fedId)
  return <dependency objectName="{$conn?name}" .../>

(: Task -> Mapping via mappingId (cross-package federatedId) :)
let $mappingFedId := substring-after(string($t?mappingId), '@')

(: Task -> Connections via parameters array :)
for $p in $t?parameters?*
  let $connFedId :=
    substring-after(
      string(($p?sourceConnectionId, $p?targetConnectionId)[. != ''][1]),
      '@')
  return <dependency .../>
```

### CDI Dependency Types (revised)

| From | Depends On | Dependency Type |
|------|-----------|-----------------|
| Mapping | Connection (via `references[refType=connection]`) | connection reference |
| Mapping Task | Mapping (via `mappingId`) | mapping reference |
| Mapping Task | Connection (via `parameters[sourceConnectionId/targetConnectionId]`) | connection override |

No standalone CDI Taskflow ZIPs found. CAI Taskflows (`.TASKFLOW.xml`) remain in the
existing analysis path via `ipd-metadata.xqm`.

---

## Phase 3 — Dependency Graph Cache

### Problem
`imf:getObjectDependencies()` and `imf:getObjectImpact()` perform full recursive traversal
on every page load. For large databases (100s of designs) this causes timeouts and poor UX.

### Strategy: Pre-compute on Database Load

After the background extraction job completes, schedule a second job to pre-compute all
dependency and impact trees and store them as JSON in `_cache/` paths.

### Cache Storage Format

```
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

## Phase 4 — REST/JSON API Layer

### New file: `api.xqm`

All endpoints return `application/json`. These serve the vis.js graph UI and can support
future external consumers.

### Endpoint Design

| Method | Path | Returns |
|--------|------|---------|
| GET | `/iics/api/databases` | `[{name, resources, modified}]` |
| GET | `/iics/api/designs?database=X` | `[{guid, name, displayName, type, status}]` |
| GET | `/iics/api/design?database=X&guid=Y` | `{guid, name, type, mimeType, ...}` |
| GET | `/iics/api/design/dependencies?database=X&guid=Y` | `{nodes:[...], edges:[...]}` (vis.js format) |
| GET | `/iics/api/design/impact?database=X&guid=Y` | `{nodes:[...], edges:[...]}` (vis.js format) |
| GET | `/iics/api/cache/status?database=X` | `{complete, built, count}` |
| POST | `/iics/api/cache/rebuild?database=X` | `{jobId}` (triggers background job) |
| GET | `/iics/api/cdi/mappings?database=X` | CDI mapping list |
| GET | `/iics/api/cdi/tasks?database=X` | CDI task list |
| GET | `/iics/api/cdi/taskflows?database=X` | CDI taskflow list |

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

## Phase 5 — Visualization with vis.js

### Recommendation: vis.js Network (already chosen)

The project already has `sample-data/graph-vis/basic.html` with vis.js. This is the right choice:
- **vis.js Network**: ideal for dependency graphs (directed graphs with arrows, groups, clustering)
- **Layout options**: `hierarchical` for dependency tree top-down; `force-directed` for full network
- Already used in the project's prototype

### Alternative Options (for awareness)

| Library | Strength | Weakness |
|---------|----------|---------|
| **vis.js Network** ✅ | Already adopted; good defaults; interactive | Large bundle (~600KB) |
| **Cytoscape.js** | Purpose-built for graphs; fast; DAGRE layout | More complex API |
| **D3.js** | Maximum flexibility | Requires significant custom code |
| **Mermaid.js** | Simple DSL; easy static diagrams | Poor for interactive exploration |

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

## Phase 6 — Unified Asset Registry

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

| Phase | Priority | Effort | Value |
|-------|----------|--------|-------|
| 1 — Nested ZIP extraction | HIGH | Medium | Unlocks CDI |
| 3 — Dependency cache | HIGH | Medium | Performance fix for existing pages |
| 4 — REST API (`api.xqm`) | HIGH | Medium | Foundation for graph UI |
| 2 — CDI metadata module | MEDIUM | High | New asset type support |
| 5 — vis.js graph view | MEDIUM | Medium | UX improvement |
| 6 — Unified catalogue | LOW | Low | Polish |

---

## Key Technical Notes

### BaseX JSON Support
- JSON documents stored natively: `db:add($name, $text, 'path.json')` 
- Query: `json:parse(db:get($name, 'path.json')/text())` → returns XQuery map
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
