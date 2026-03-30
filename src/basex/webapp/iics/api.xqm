(:~
 : IICS Reporting REST/JSON API.
 :
 : Provides JSON endpoints for databases, CAI designs, dependency graphs, impact
 : analysis, cache management, and CDI asset listings. All responses are
 : application/json (text output method with media-type override).
 :
 : Endpoints:
 :
 :   GET  /iics/api/databases                      - list databases
 :   GET  /iics/api/designs?database=X             - list CAI designs
 :   GET  /iics/api/design?database=X&guid=Y       - single CAI design metadata
 :   GET  /iics/api/design/dependencies?...        - dep graph (vis.js, cache-aware)
 :   GET  /iics/api/design/impact?...              - impact graph (vis.js, cache-aware)
 :   GET  /iics/api/cache/status?database=X        - cache build status
 :   POST /iics/api/cache/rebuild?database=X       - trigger cache rebuild job
 :   GET  /iics/api/cdi/mappings?database=X        - CDI mapping list
 :   GET  /iics/api/cdi/tasks?database=X           - CDI mapping task list
 :   GET  /iics/api/cdi/connections?database=X     - CDI connection list
 :   GET  /iics/api/catalogue?database=X           - unified asset catalogue
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace api = 'iics/api';

import module namespace imf   = 'iics/imf'             at 'modules/ipd-metadata.xqm';
import module namespace cdi   = 'iics/cdi-metadata'    at 'modules/cdi-metadata.xqm';
import module namespace cache = 'iics/cache'            at 'modules/cache.xqm';

declare namespace rep   = "http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd";
declare namespace db    = "http://basex.org/modules/db";
declare namespace file  = "http://expath.org/ns/file";
declare namespace job   = "http://basex.org/modules/job";
declare namespace convert = "http://basex.org/modules/convert";
declare namespace rest  = "http://exquery.org/ns/restxq";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";

(:~
 : Serializes any XQuery value to a JSON string.
 : Wraps the value in `{ "error": "..." }` if serialization fails.
 :)
declare %private function api:to-json($data as item()*) as xs:string {
  try {
    serialize($data, map { 'method': 'json' })
  } catch * {
    '{"error":"Serialization failed: ' || $err:description || '"}'
  }
};

(:~
 : Returns a JSON error response.
 :)
declare %private function api:error($msg as xs:string) as xs:string {
  serialize(map { 'error': $msg }, map { 'method': 'json' })
};

(: ============================================================
   Database endpoints
   ============================================================ :)

(:~
 : Returns a JSON array of available databases with resource counts.
 :
 : Response: [{ "name": "...", "resources": N, "modified": "..." }, ...]
 :)
declare
  %rest:path("/iics/api/databases")
  %rest:GET
  %output:method("text")
  %output:media-type("application/json")
function api:databases() as xs:string {
  let $dbs :=
    for $name in db:list()
      where not(starts-with($name, '.'))
      let $details := db:list-details($name)[1]
      return map {
        'name'     : $name,
        'resources': db:list-details($name) => count(),
        'modified' : string($details/@modified-date)
      }
  return api:to-json(array { $dbs })
};

(: ============================================================
   CAI Design endpoints
   ============================================================ :)

(:~
 : Returns a JSON array of all CAI design assets in a database.
 :
 : Response: [{ "guid": "...", "name": "...", "displayName": "...",
 :              "type": "...", "mimeType": "...", "path": "..." }, ...]
 :)
declare
  %rest:path("/iics/api/designs")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:designs($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $db := db:get($database)
    let $designs :=
      for $item in $db//rep:Item
        order by string($item/rep:Name)
        return map {
          'guid'       : string($item/rep:GUID),
          'name'       : string($item/rep:Name),
          'displayName': string($item/rep:DisplayName),
          'type'       : substring-after(string($item/rep:MimeType), 'application/xml+'),
          'mimeType'   : string($item/rep:MimeType),
          'path'       : db:path($item/parent::*)
        }
    return api:to-json(array { $designs })
};

(:~
 : Returns metadata for a single CAI design by GUID.
 :
 : Response: { "guid": "...", "name": "...", "displayName": "...",
 :             "type": "...", "mimeType": "...", "path": "..." }
 :)
declare
  %rest:path("/iics/api/design")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %rest:query-param("guid",     "{$guid}",     "")
  %output:method("text")
  %output:media-type("application/json")
function api:design($database as xs:string, $guid as xs:string) as xs:string {
  if ($database = '' or $guid = '') then api:error('database and guid parameters are required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $db   := db:get($database)
    let $item := imf:getDesignByGuid($db, $guid)
    return
    if (empty($item)) then api:error('Design not found: ' || $guid)
    else
      api:to-json(map {
        'guid'       : $guid,
        'name'       : string($item/rep:Name),
        'displayName': string($item/rep:DisplayName),
        'type'       : substring-after(string($item/rep:MimeType), 'application/xml+'),
        'mimeType'   : string($item/rep:MimeType),
        'path'       : db:path($item)
      })
};

(:~
 : Returns the dependency graph for a CAI design in vis.js nodes/edges format.
 : Serves from cache if available; computes on demand otherwise.
 :
 : Response: { "cached": true|false, "nodes": [...], "edges": [...] }
 :)
declare
  %rest:path("/iics/api/design/dependencies")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %rest:query-param("guid",     "{$guid}",     "")
  %output:method("text")
  %output:media-type("application/json")
function api:dependencies($database as xs:string, $guid as xs:string) as xs:string {
  if ($database = '' or $guid = '') then api:error('database and guid parameters are required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $cached := cache:getDeps($database, $guid)
    return
    if (exists($cached)) then
      api:to-json(map:merge(($cached, map { 'cached': true() })))
    else
      let $db   := db:get($database)
      let $item := imf:getDesignByGuid($db, $guid)
      return
      if (empty($item)) then api:error('Design not found: ' || $guid)
      else
        let $mtype := string($item//rep:MimeType)
        let $group := cache:mime-to-group($mtype)
        let $deps  := imf:getObjectDependencies($db, $item)
        let $graph := cache:extract-graph($deps, $group)
        return api:to-json(map:merge(($graph, map { 'cached': false() })))
};

(:~
 : Returns the impact graph for a CAI design in vis.js nodes/edges format.
 : Serves from cache if available; computes on demand otherwise.
 :
 : Response: { "cached": true|false, "nodes": [...], "edges": [...] }
 :)
declare
  %rest:path("/iics/api/design/impact")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %rest:query-param("guid",     "{$guid}",     "")
  %output:method("text")
  %output:media-type("application/json")
function api:impact($database as xs:string, $guid as xs:string) as xs:string {
  if ($database = '' or $guid = '') then api:error('database and guid parameters are required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $cached := cache:getImpact($database, $guid)
    return
    if (exists($cached)) then
      api:to-json(map:merge(($cached, map { 'cached': true() })))
    else
      let $db   := db:get($database)
      let $item := imf:getDesignByGuid($db, $guid)
      return
      if (empty($item)) then api:error('Design not found: ' || $guid)
      else
        let $mtype  := string($item//rep:MimeType)
        let $group  := cache:mime-to-group($mtype)
        let $impact := imf:getObjectImpact($db, $item, true())
        let $graph  := cache:extract-graph($impact, $group)
        return api:to-json(map:merge(($graph, map { 'cached': false() })))
};

(: ============================================================
   Cache management endpoints
   ============================================================ :)

(:~
 : Returns the cache build status for a database.
 :
 : Response: { "complete": true|false, "built": "...", "count": N }
 :)
declare
  %rest:path("/iics/api/cache/status")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:cache-status($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else api:to-json(cache:status($database))
};

(:~
 : Triggers an asynchronous cache rebuild job for a database.
 : Returns the job ID so callers can poll for completion.
 :
 : Response: { "jobId": "...", "database": "..." }
 :)
declare
  %rest:path("/iics/api/cache/rebuild")
  %rest:POST
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:cache-rebuild($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $jobId := job:eval(
      "declare variable $db external;" ||
      "import module namespace cache = 'iics/cache' at 'modules/cache.xqm';" ||
      " cache:build($db)",
      map { 'db': $database },
      map { 'base-uri': file:base-dir() }
    )
    return api:to-json(map { 'jobId': $jobId, 'database': $database })
};

(: ============================================================
   CDI asset endpoints
   ============================================================ :)

(:~
 : Returns a JSON array of all CDI Mappings in a database.
 :
 : Response: [{ "name": "...", "connections": N, "path": "..." }, ...]
 :)
declare
  %rest:path("/iics/api/cdi/mappings")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:cdi-mappings($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $mappings :=
      for $m in cdi:getMappings($database)
        order by string($m?name)
        return map {
          'name'       : string($m?name),
          'connections': count($m?references?*[string(.?refType) = 'connection']),
          'path'       : string($m?path)
        }
    return api:to-json(array { $mappings })
};

(:~
 : Returns a JSON array of all CDI Mapping Tasks in a database.
 :
 : Response: [{ "name": "...", "mappingFederatedId": "...", "path": "..." }, ...]
 :)
declare
  %rest:path("/iics/api/cdi/tasks")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:cdi-tasks($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $tasks :=
      for $t in cdi:getMappingTasks($database)
        order by string($t?name)
        return map {
          'name'              : string($t?name),
          'mappingFederatedId': substring-after(string($t?mappingId), '@'),
          'path'              : string($t?path)
        }
    return api:to-json(array { $tasks })
};

(:~
 : Returns a JSON array of all CDI Connections in a database.
 :
 : Response: [{ "name": "...", "federatedId": "...", "type": "...", "path": "..." }, ...]
 :)
declare
  %rest:path("/iics/api/cdi/connections")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:cdi-connections($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else
    let $conns :=
      for $c in cdi:getConnections($database)
        order by string($c?name)
        return map {
          'name'       : string($c?name),
          'federatedId': string($c?federatedId),
          'type'       : string($c?type),
          'path'       : string($c?path)
        }
    return api:to-json(array { $conns })
};

(: ============================================================
   Unified catalogue endpoint
   ============================================================ :)

(:~
 : Returns the unified CAI+CDI asset catalogue for a database.
 :
 : Reads from the pre-built `_meta/catalogue.json` if available;
 : computes on demand otherwise (slower).
 :
 : Response: { "database": "...", "built": "...", "assets": [...] }
 :)
declare
  %rest:path("/iics/api/catalogue")
  %rest:GET
  %rest:query-param("database", "{$database}", "")
  %output:method("text")
  %output:media-type("application/json")
function api:catalogue($database as xs:string) as xs:string {
  if ($database = '') then api:error('database parameter is required')
  else if (not(db:exists($database))) then api:error('Database not found: ' || $database)
  else if (db:exists($database, '_meta/catalogue.json')) then
    let $bin  := db:get-binary($database, '_meta/catalogue.json')
    return convert:binary-to-string($bin, 'UTF-8')
  else
    (: Compute on demand - no cache :)
    let $db := db:get($database)
    let $cai :=
      for $item in $db//rep:Item
        order by string($item/rep:Name)
        return map {
          'guid'   : string($item/rep:GUID),
          'name'   : string($item/rep:Name),
          'display': string($item/rep:DisplayName),
          'type'   : substring-after(string($item/rep:MimeType), 'application/xml+'),
          'engine' : 'CAI',
          'path'   : db:path($item/parent::*)
        }
    let $cdi-m :=
      for $m in cdi:getMappings($database)
        order by string($m?name)
        return map {
          'guid': '', 'name': string($m?name), 'display': string($m?name),
          'type': 'DTEMPLATE', 'engine': 'CDI', 'path': string($m?path)
        }
    let $cdi-t :=
      for $t in cdi:getMappingTasks($database)
        order by string($t?name)
        return map {
          'guid': '', 'name': string($t?name), 'display': string($t?name),
          'type': 'MTT', 'engine': 'CDI', 'path': string($t?path)
        }
    let $cdi-c :=
      for $c in cdi:getConnections($database)
        order by string($c?name)
        return map {
          'guid': string($c?federatedId), 'name': string($c?name),
          'display': string($c?name), 'type': 'Connection',
          'engine': 'CDI', 'path': string($c?path)
        }
    return api:to-json(map {
      'database': $database,
      'built'   : '',
      'assets'  : array { ($cai, $cdi-m, $cdi-t, $cdi-c) }
    })
};
