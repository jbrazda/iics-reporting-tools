(:~
 : Dependency graph cache module.
 :
 : Pre-computes CAI and CDI dependency trees as vis.js-ready JSON stored as binary
 : resources inside the database under a `_cache/` prefix. This avoids repeated
 : expensive recursive traversals on every page load.
 :
 : Cache layout inside the BaseX database:
 :
 :   _cache/deps/{guid}.json    - CAI dependency tree (vis.js nodes/edges)
 :   _cache/impact/{guid}.json  - CAI impact tree (vis.js nodes/edges)
 :   _cache/meta/status.json    - build status { complete, built, count }
 :
 : Cache invalidation:
 :   Cache lives inside the same BaseX database - dropping/replacing the DB
 :   clears the cache automatically. Force-rebuild via POST /iics/api/cache/rebuild.
 :
 : CDI assets (mappings, tasks, connections) currently have name-based IDs rather
 : than GUIDs, so they are included in the vis.js graph as nodes but are not cached
 : individually with their own cache paths.
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace cache = 'iics/cache';

import module namespace imf   = 'iics/imf'      at 'ipd-metadata.xqm';
import module namespace cdi   = 'iics/cdi-metadata' at 'cdi-metadata.xqm';

declare namespace rep     = "http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd";
(:~ Group name used for the root node in a dependency/impact graph. :)
declare variable $cache:GROUP_ROOT := 'root';

(:~ Maps MIME type suffix to a vis.js group name. :)
declare variable $cache:MIME_TO_GROUP := map {
  'processobject'     : 'processObject',
  'connection'        : 'connection',
  'screenflow'        : 'guide',
  'process'           : 'process',
  'businesssconnector': 'connector',
  'taskflow'          : 'taskflow'
};

(:~ Maps CDI objectType to a vis.js group name. :)
declare variable $cache:CDI_TO_GROUP := map {
  'Mapping'    : 'cdi-mapping',
  'Task'       : 'cdi-task',
  'Connection' : 'connection'
};

(: ============================================================
   Public read API (non-updating)
   ============================================================ :)

(:~
 : Returns the cache build status for a database.
 :
 : @param  $dbname  database name
 : @return XQuery map with keys: complete (xs:boolean), built (xs:string), count (xs:integer)
 :         or empty map if cache has not been built yet
 :)
declare function cache:status($dbname as xs:string) as map(*) {
  if (db:exists($dbname, '_cache/meta/status.json')) then
    let $bin  := db:get-binary($dbname, '_cache/meta/status.json')
    let $text := convert:binary-to-string($bin, 'UTF-8')
    return json:parse($text, map { 'format': 'w3' })
  else
    map { 'complete': false(), 'built': '', 'count': 0 }
};

(:~
 : Returns true if a pre-computed dependency graph exists for the given GUID.
 :
 : @param  $dbname  database name
 : @param  $guid    CAI design GUID
 :)
declare function cache:hasDeps($dbname as xs:string, $guid as xs:string) as xs:boolean {
  db:exists($dbname, '_cache/deps/' || $guid || '.json')
};

(:~
 : Returns true if a pre-computed impact graph exists for the given GUID.
 :
 : @param  $dbname  database name
 : @param  $guid    CAI design GUID
 :)
declare function cache:hasImpact($dbname as xs:string, $guid as xs:string) as xs:boolean {
  db:exists($dbname, '_cache/impact/' || $guid || '.json')
};

(:~
 : Returns the pre-computed dependency graph for a GUID as a vis.js XQuery map.
 : Returns empty sequence if no cache entry exists.
 :
 : @param  $dbname  database name
 : @param  $guid    CAI design GUID
 : @return map { 'nodes': array(*), 'edges': array(*) } or empty sequence
 :)
declare function cache:getDeps($dbname as xs:string, $guid as xs:string) as map(*)? {
  if (cache:hasDeps($dbname, $guid)) then
    let $bin  := db:get-binary($dbname, '_cache/deps/' || $guid || '.json')
    let $text := convert:binary-to-string($bin, 'UTF-8')
    return json:parse($text, map { 'format': 'w3' })
  else ()
};

(:~
 : Returns the pre-computed impact graph for a GUID as a vis.js XQuery map.
 : Returns empty sequence if no cache entry exists.
 :
 : @param  $dbname  database name
 : @param  $guid    CAI design GUID
 : @return map { 'nodes': array(*), 'edges': array(*) } or empty sequence
 :)
declare function cache:getImpact($dbname as xs:string, $guid as xs:string) as map(*)? {
  if (cache:hasImpact($dbname, $guid)) then
    let $bin  := db:get-binary($dbname, '_cache/impact/' || $guid || '.json')
    let $text := convert:binary-to-string($bin, 'UTF-8')
    return json:parse($text, map { 'format': 'w3' })
  else ()
};

(: ============================================================
   Graph conversion utilities
   ============================================================ :)

(:~
 : Converts a MIME type string to a vis.js group name.
 : For example, "application/xml+process" becomes "process".
 :
 : @param  $mimeType  MIME type string from rep:MimeType
 : @return group name string
 :)
declare function cache:mime-to-group($mimeType as xs:string) as xs:string {
  let $suffix := substring-after($mimeType, 'application/xml+')
  return ($cache:MIME_TO_GROUP($suffix), 'unknown')[1]
};

(:~
 : Extracts all unique nodes and edges from a CAI dependency XML tree.
 : Handles both `<dependencies>` (root) and `<dependency>` (children) elements.
 :
 : Nodes are keyed by GUID. The root node is given group "root".
 : If a dependency has no toGuid attribute (missing), it is skipped.
 :
 : @param  $tree     root <dependencies> or <impactReport> element
 : @param  $rootGroup  vis.js group name for the root node
 : @return map { 'nodes': map(*), 'edges': array(*) }
 :         where nodes map is keyed by id for deduplication
 :)
declare function cache:extract-graph($tree as element(), $rootGroup as xs:string) as map(*) {
  let $rootId    := string($tree/@guid)
  let $rootLabel := (string($tree/@object), string($tree/@name), string($tree/@displayName))[. != ''][1]
  let $rootNode  := map {
    'id'    : $rootId,
    'label' : $rootLabel,
    'group' : $cache:GROUP_ROOT,
    'title' : $rootGroup
  }
  let $allDeps := $tree//(dependency | usedBy)
  let $depNodes :=
    for $d in $allDeps
      let $toId    := (string($d/@toGuid), string($d/@toFederatedId))[. != ''][1]
      let $name    := string($d/@objectName)
      let $refType := string($d/@referenceType)
      let $objType := string($d/@objectType)
      let $engine  := string($d/@engine)
      let $group   :=
        if ($engine = 'CDI') then ($cache:CDI_TO_GROUP($objType), 'cdi-asset')[. != ''][1]
        else cache:mime-to-group(string($d/@mimeType))
      where $toId != '' and $name != ''
      return map {
        'id'    : $toId,
        'label' : $name,
        'group' : $group,
        'title' : $refType
      }
  let $depEdges :=
    for $d in $allDeps
      let $fromId := (string($d/@fromGuid), string($d/@fromName))[. != ''][1]
      let $toId   := (string($d/@toGuid),   string($d/@toFederatedId))[. != ''][1]
      let $label  := string($d/@referenceType)
      where $fromId != '' and $toId != '' and $fromId != $toId
      return map {
        'from'  : $fromId,
        'to'    : $toId,
        'label' : $label,
        'arrows': 'to'
      }
  (: Deduplicate nodes by id :)
  let $nodeMap := map:merge(
    ($rootNode, $depNodes) ! map:entry(.?id, .),
    map { 'duplicates': 'use-last' }
  )
  return map {
    'nodes': array { for $k in map:keys($nodeMap) return $nodeMap($k) },
    'edges': array { $depEdges }
  }
};

(:~
 : Serializes a vis.js graph map to a JSON string.
 :
 : @param  $graph  map { 'nodes': array(*), 'edges': array(*) }
 : @return JSON string
 :)
declare function cache:graph-to-json($graph as map(*)) as xs:string {
  serialize($graph, map { 'method': 'json' })
};

(:~
 : Stores a JSON string as a binary resource in the database.
 :
 : @param  $dbname  database name
 : @param  $path    storage path within the database
 : @param  $json    JSON string content
 :)
declare %updating function cache:store-json(
  $dbname as xs:string,
  $path   as xs:string,
  $json   as xs:string
) {
  db:put-binary($dbname, convert:string-to-base64($json, 'UTF-8'), $path)
};

(: ============================================================
   Cache build (updating)
   ============================================================ :)

(:~
 : Builds the dependency cache for all CAI assets in a database.
 :
 : Iterates over all rep:Item entries (CAI designs), computes dependency and impact
 : trees using imf:getObjectDependencies and imf:getObjectImpact, converts each to
 : vis.js JSON, and stores them as binary resources under `_cache/`.
 :
 : Also builds the unified asset catalogue at `_meta/catalogue.json`.
 :
 : Should be invoked as a background job after the database is created and CDI
 : extraction is complete.
 :
 : @param  $dbname  database name
 :)
declare %updating function cache:build($dbname as xs:string) {
  let $db    := db:get($dbname)
  let $items := $db//rep:Item
  let $count := count($items)
  return (
    (: Pre-compute CAI deps and impact for every design item :)
    for $item in $items
      let $guid  := string($item/rep:GUID)
      let $mtype := string($item/rep:MimeType)
      let $group := cache:mime-to-group($mtype)
      where $guid != ''
      let $deps   := imf:getObjectDependencies($db, $item)
      let $impact := imf:getObjectImpact($db, $item, true())
      let $dGraph := cache:extract-graph($deps,   $group)
      let $iGraph := cache:extract-graph($impact, $group)
      return (
        cache:store-json($dbname, '_cache/deps/'   || $guid || '.json',
                         cache:graph-to-json($dGraph)),
        cache:store-json($dbname, '_cache/impact/' || $guid || '.json',
                         cache:graph-to-json($iGraph))
      )
    ,
    (: Write cache status :)
    cache:store-json($dbname, '_cache/meta/status.json',
      serialize(
        map {
          'complete': true(),
          'built'   : string(current-dateTime()),
          'count'   : $count
        },
        map { 'method': 'json' }
      )
    ),
    (: Build unified catalogue :)
    cache:build-catalogue($dbname, $db)
  )
};

(:~
 : Builds the unified asset catalogue combining CAI and CDI assets.
 : Stored at `_meta/catalogue.json` as binary JSON.
 :
 : CAI assets are sourced from rep:Item elements (XML docs).
 : CDI assets are sourced from binary JSON resources via cdi-metadata functions.
 :
 : @param  $dbname  database name
 : @param  $db      open database (result of db:get)
 :)
declare %updating function cache:build-catalogue(
  $dbname as xs:string,
  $db     as document-node()*
) {
  let $caiAssets :=
    for $item in $db//rep:Item
      return map {
        'guid'   : string($item/rep:GUID),
        'name'   : string($item/rep:Name),
        'display': string($item/rep:DisplayName),
        'type'   : substring-after(string($item/rep:MimeType), 'application/xml+'),
        'engine' : 'CAI',
        'path'   : db:path($item/parent::*)
      }
  let $cdiMappings :=
    for $m in cdi:getMappings($dbname)
      return map {
        'guid'   : '',
        'name'   : string($m?name),
        'display': string($m?name),
        'type'   : 'DTEMPLATE',
        'engine' : 'CDI',
        'path'   : string($m?path)
      }
  let $cdiTasks :=
    for $t in cdi:getMappingTasks($dbname)
      return map {
        'guid'   : '',
        'name'   : string($t?name),
        'display': string($t?name),
        'type'   : 'MTT',
        'engine' : 'CDI',
        'path'   : string($t?path)
      }
  let $cdiConns :=
    for $c in cdi:getConnections($dbname)
      return map {
        'guid'   : string($c?federatedId),
        'name'   : string($c?name),
        'display': string($c?name),
        'type'   : 'Connection',
        'engine' : 'CDI',
        'path'   : string($c?path)
      }
  let $catalogue := map {
    'database': $dbname,
    'built'   : string(current-dateTime()),
    'assets'  : array { ($caiAssets, $cdiMappings, $cdiTasks, $cdiConns) }
  }
  return
  cache:store-json($dbname, '_meta/catalogue.json',
                   serialize($catalogue, map { 'method': 'json' }))
};
