(:~
 : Standalone XQuery job script for building the dependency cache.
 :
 : This file is executed via job:eval() from api.xqm and cdi-extract.xqm.
 : It is intentionally a standalone .xq file (not a module) to work around
 : a BaseX 12 limitation where imported %updating functions called from
 : job:eval do not reliably persist their database writes.
 :
 : The $db variable must be bound via the job:eval bindings map.
 :)
import module namespace imf   = 'iics/imf'          at 'ipd-metadata.xqm';
import module namespace cdi   = 'iics/cdi-metadata'  at 'cdi-metadata.xqm';

declare namespace rep = "http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd";

declare variable $db external;

declare variable $local:MIME_TO_GROUP := map {
  'processobject'     : 'processObject',
  'connection'        : 'connection',
  'screenflow'        : 'guide',
  'process'           : 'process',
  'businesssconnector': 'connector',
  'taskflow'          : 'taskflow'
};

declare variable $local:CDI_TO_GROUP := map {
  'Mapping'    : 'cdi-mapping',
  'Task'       : 'cdi-task',
  'Connection' : 'connection'
};

declare %updating function local:store-binary(
  $dbname as xs:string,
  $path   as xs:string,
  $text   as xs:string
) {
  db:put-binary($dbname, convert:string-to-base64($text, 'UTF-8'), $path)
};

declare function local:mime-to-group($mimeType as xs:string) as xs:string {
  let $suffix := substring-after($mimeType, 'application/xml+')
  return ($local:MIME_TO_GROUP($suffix), 'unknown')[1]
};

declare function local:extract-graph($tree as element(), $rootGroup as xs:string) as map(*) {
  let $rootId    := string($tree/@guid)
  let $rootLabel := (string($tree/@object), string($tree/@name), string($tree/@displayName))[. != ''][1]
  let $rootNode  := map { 'id': $rootId, 'label': $rootLabel, 'group': 'root', 'title': $rootGroup }
  let $allDeps   := $tree//(dependency | usedBy)
  let $depNodes  :=
    for $d in $allDeps
      let $toId    := (string($d/@toGuid), string($d/@toFederatedId))[. != ''][1]
      let $name    := string($d/@objectName)
      let $refType := string($d/@referenceType)
      let $objType := string($d/@objectType)
      let $engine  := string($d/@engine)
      let $group   :=
        if ($engine = 'CDI') then ($local:CDI_TO_GROUP($objType), 'cdi-asset')[. != ''][1]
        else local:mime-to-group(string($d/@mimeType))
      where $toId != '' and $name != ''
      return map { 'id': $toId, 'label': $name, 'group': $group, 'title': $refType }
  let $depEdges  :=
    for $d in $allDeps
      let $fromId := (string($d/@fromGuid), string($d/@fromName))[. != ''][1]
      let $toId   := (string($d/@toGuid),   string($d/@toFederatedId))[. != ''][1]
      let $label  := string($d/@referenceType)
      where $fromId != '' and $toId != '' and $fromId != $toId
      return map { 'from': $fromId, 'to': $toId, 'label': $label, 'arrows': 'to' }
  let $nodeMap := map:merge(
    ($rootNode, $depNodes) ! map:entry(.?id, .),
    map { 'duplicates': 'use-last' }
  )
  return map {
    'nodes': array { for $k in map:keys($nodeMap) return $nodeMap($k) },
    'edges': array { $depEdges }
  }
};

let $dbDocs := db:get($db)
let $items  := $dbDocs//rep:Item
let $count  := count($items)
return (
  for $item in $items
    let $guid  := string($item/rep:GUID)
    let $group := local:mime-to-group(string($item/rep:MimeType))
    where $guid != ''
    let $deps   := imf:getObjectDependencies($dbDocs, $item)
    let $impact := imf:getObjectImpact($dbDocs, $item, true())
    let $dGraph := local:extract-graph($deps,   $group)
    let $iGraph := local:extract-graph($impact, $group)
    return (
      local:store-binary($db, '_cache/deps/'   || $guid || '.json',
                         serialize($dGraph, map { 'method': 'json' })),
      local:store-binary($db, '_cache/impact/' || $guid || '.json',
                         serialize($iGraph, map { 'method': 'json' }))
    )
  ,
  local:store-binary($db, '_cache/meta/status.json',
    serialize(
      map { 'complete': true(), 'built': string(current-dateTime()), 'count': $count },
      map { 'method': 'json' }
    )
  )
  ,
  (: Build unified catalogue - inline CDI + CAI assets :)
  let $caiAssets :=
    for $item in $dbDocs//rep:Item
      return map {
        'guid'   : string($item/rep:GUID),
        'name'   : string($item/rep:Name),
        'display': string($item/rep:DisplayName),
        'type'   : substring-after(string($item/rep:MimeType), 'application/xml+'),
        'engine' : 'CAI',
        'path'   : db:path($item/parent::*)
      }
  let $cdiMappings :=
    for $m in cdi:getMappings($db)
      return map { 'guid': '', 'name': string($m?name), 'display': string($m?name),
                   'type': 'mapping', 'engine': 'CDI', 'path': string($m?path) }
  let $cdiTasks :=
    for $t in cdi:getMappingTasks($db)
      return map { 'guid': '', 'name': string($t?name), 'display': string($t?name),
                   'type': 'task', 'engine': 'CDI', 'path': string($t?path) }
  let $cdiConns :=
    for $c in cdi:getConnections($db)
      return map { 'guid': string($c?federatedId), 'name': string($c?name), 'display': string($c?name),
                   'type': 'connection', 'engine': 'CDI', 'path': string($c?path) }
  let $all := ($caiAssets, $cdiMappings, $cdiTasks, $cdiConns)
  let $catalogue := serialize(
    map { 'assets': array { $all } },
    map { 'method': 'json' }
  )
  return local:store-binary($db, '_meta/catalogue.json', $catalogue)
)
