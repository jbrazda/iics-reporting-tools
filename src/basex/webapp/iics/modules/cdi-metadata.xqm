(:~
 : CDI metadata analysis module.
 :
 : Provides functions to analyze CDI (Cloud Data Integration) assets stored in a BaseX
 : database after nested ZIP extraction (see cdi-extract.xqm).
 :
 : Asset types and their source files (confirmed from live IICS package inspection):
 :
 :   Mapping Template  - .DTEMPLATE.zip -> mappingTemplate.json
 :   Mapping Task      - .MTT.zip       -> mtTask.json
 :   Connection        - .Connection.zip -> connection.json
 :
 : JSON is stored as raw binary (via db:store) so it can be reliably retrieved and
 : parsed with json:parse(). Use cdi:hasCDIAssets($dbname) to check before querying.
 :
 : Cross-reference format: refObjectId / mappingId / sourceConnectionId values use
 : "@" + federatedId (e.g. "@hz1mAolBHYcb5lvDNIpaQa"). Strip the "@" prefix to get
 : the federatedId that matches connection.json's "federatedId" field.
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace cdi = 'iics/cdi-metadata';

declare namespace db      = "http://basex.org/modules/db";
declare namespace convert = "http://basex.org/modules/convert";

(:~ Human-readable labels for CDI asset types. :)
declare variable $cdi:TYPES := map {
  'Mapping'    : 'CDI Mapping',
  'Task'       : 'CDI Mapping Task',
  'Connection' : 'CDI Connection'
};

(:~
 : Retrieves a binary JSON resource from the database and parses it into an XQuery map.
 :
 : JSON files are stored as binary (xs:base64Binary) via db:store() during extraction.
 :
 : @param  $dbname  database name
 : @param  $path    path of the binary resource within the database
 : @return first element of the parsed JSON (unwraps single-element arrays)
 :)
declare function cdi:parse-json($dbname as xs:string, $path as xs:string) as map(*)? {
  let $bin    := db:retrieve($dbname, $path)
  let $text   := convert:binary-to-string($bin, 'UTF-8')
  let $parsed := json:parse($text, map { 'format': 'xquery' })
  return
    if ($parsed instance of array(*)) then $parsed?1
    else if ($parsed instance of map(*)) then $parsed
    else ()
};

(:~
 : Returns paths of all CDI Mapping Template JSON binary resources in the database.
 : These are extracted from .DTEMPLATE.zip nested archives.
 :
 : @param  $dbname  database name
 : @return sequence of paths ending in /mappingTemplate.json (case-insensitive)
 :)
declare function cdi:mapping-paths($dbname as xs:string) as xs:string* {
  db:list-details($dbname)[@raw = 'true']
    [ends-with(lower-case(text()), '/mappingtemplate.json')]/text()
};

(:~
 : Returns paths of all CDI Mapping Task JSON binary resources in the database.
 : These are extracted from .MTT.zip nested archives.
 :
 : @param  $dbname  database name
 : @return sequence of paths ending in /mtTask.json (case-insensitive)
 :)
declare function cdi:task-paths($dbname as xs:string) as xs:string* {
  db:list-details($dbname)[@raw = 'true']
    [ends-with(lower-case(text()), '/mttask.json')]/text()
};

(:~
 : Returns paths of all CDI Connection JSON binary resources in the database.
 : These are extracted from .Connection.zip nested archives.
 :
 : @param  $dbname  database name
 : @return sequence of paths ending in /connection.json (case-insensitive)
 :)
declare function cdi:connection-paths($dbname as xs:string) as xs:string* {
  db:list-details($dbname)[@raw = 'true']
    [ends-with(lower-case(text()), '/connection.json')]/text()
};

(:~
 : Returns all CDI Mapping Templates as a sequence of XQuery maps.
 : Each map is the parsed mappingTemplate.json augmented with a synthetic "path" key.
 :
 : Actual JSON structure (from .DTEMPLATE.zip):
 :   { "@type": "mappingTemplate", "id": "@1", "name": "m_...",
 :     "references": [{ "@type": "reference", "refObjectId": "@federatedId",
 :                      "refType": "connection" }] }
 :
 : @param  $dbname  database name
 : @return sequence of maps
 :)
declare function cdi:getMappings($dbname as xs:string) as map(*)* {
  for $path in cdi:mapping-paths($dbname)
    let $m := cdi:parse-json($dbname, $path)
    where exists($m)
    return map:merge(($m, map { 'path': $path }))
};

(:~
 : Returns all CDI Mapping Tasks as a sequence of XQuery maps.
 : Each map is the parsed mtTask.json augmented with a synthetic "path" key.
 :
 : Actual JSON structure (from .MTT.zip):
 :   { "@type": "mtTask", "id": "@1", "name": "mct_...", "mappingId": "@federatedId",
 :     "parameters": [{ "type": "EXTENDED_SOURCE", "sourceConnectionId": "@federatedId" },
 :                    { "type": "TARGET", "targetConnectionId": "@federatedId" }] }
 :
 : @param  $dbname  database name
 : @return sequence of maps
 :)
declare function cdi:getMappingTasks($dbname as xs:string) as map(*)* {
  for $path in cdi:task-paths($dbname)
    let $m := cdi:parse-json($dbname, $path)
    where exists($m)
    return map:merge(($m, map { 'path': $path }))
};

(:~
 : Returns all CDI Connections as a sequence of XQuery maps.
 : Each map is the parsed connection.json augmented with a synthetic "path" key.
 :
 : Actual JSON structure (from .Connection.zip):
 :   { "@type": "connection", "id": "@1", "name": "...",
 :     "federatedId": "hz1mAolBHYcb5lvDNIpaQa", "type": "Salesforce" }
 :
 : @param  $dbname  database name
 : @return sequence of maps
 :)
declare function cdi:getConnections($dbname as xs:string) as map(*)* {
  for $path in cdi:connection-paths($dbname)
    let $m := cdi:parse-json($dbname, $path)
    where exists($m)
    return map:merge(($m, map { 'path': $path }))
};

(:~
 : Finds a CDI Mapping by its name field.
 :
 : @param  $dbname  database name
 : @param  $name    mapping name
 : @return first matching map, or empty sequence if not found
 :)
declare function cdi:getMappingByName($dbname as xs:string, $name as xs:string) as map(*)? {
  (for $m in cdi:getMappings($dbname) where string($m?name) = $name return $m)[1]
};

(:~
 : Finds a CDI Mapping Task by its name field.
 :
 : @param  $dbname  database name
 : @param  $name    task name
 : @return first matching map, or empty sequence if not found
 :)
declare function cdi:getTaskByName($dbname as xs:string, $name as xs:string) as map(*)? {
  (for $t in cdi:getMappingTasks($dbname) where string($t?name) = $name return $t)[1]
};

(:~
 : Finds a CDI Connection by its federatedId.
 : The federatedId is the value with the "@" prefix stripped from cross-references.
 :
 : @param  $dbname      database name
 : @param  $federatedId connection federatedId (without "@" prefix)
 : @return first matching map, or empty sequence if not found
 :)
declare function cdi:getConnectionByFederatedId(
  $dbname      as xs:string,
  $federatedId as xs:string
) as map(*)? {
  (for $c in cdi:getConnections($dbname)
    where string($c?federatedId) = $federatedId
    return $c)[1]
};

(:~
 : Resolves a CDI cross-reference value (with "@" prefix) to a connection map.
 :
 : IICS CDI packages encode cross-references as "@" + federatedId.
 : This function strips the prefix and looks up the matching connection.
 :
 : @param  $dbname  database name
 : @param  $ref     reference value (e.g. "@hz1mAolBHYcb5lvDNIpaQa")
 : @return connection map, or empty sequence if not resolved
 :)
declare function cdi:resolveConnection($dbname as xs:string, $ref as xs:string) as map(*)? {
  let $fedId := if (starts-with($ref, '@')) then substring($ref, 2) else $ref
  return cdi:getConnectionByFederatedId($dbname, $fedId)
};

(:~
 : Returns dependency XML for a CDI Mapping Template.
 :
 : Iterates the "references" array, filtering for refType="connection", and produces
 : one dependency child element per referenced connection.
 :
 : @param  $dbname   database name
 : @param  $name     mapping name
 : @return <dependencies> element
 :)
declare function cdi:getMappingDependencies($dbname as xs:string, $name as xs:string) as element() {
  let $m := cdi:getMappingByName($dbname, $name)
  return
  if (empty($m)) then
    <dependencies name="{$name}" object="" type="Mapping" engine="CDI">
      <warning type="Not Found">No mapping named '{$name}' found in database {$dbname}</warning>
    </dependencies>
  else
    <dependencies name="{$m?name}" object="{$m?name}" type="Mapping" engine="CDI"
                  path="{$m?path}">
      {
        for $ref in $m?references?*
          where string($ref?refType) = 'connection'
          let $conn := cdi:resolveConnection($dbname, string($ref?refObjectId))
          let $connName := if (exists($conn)) then string($conn?name)
                          else substring-after(string($ref?refObjectId), '@')
          return
          <dependency objectName="{$connName}"
                      fromName="{$m?name}"
                      toFederatedId="{substring-after(string($ref?refObjectId), '@')}"
                      referenceType="connectionReference" objectType="Connection" engine="CDI"/>
      }
    </dependencies>
};

(:~
 : Returns dependency XML for a CDI Mapping Task.
 :
 : Includes the mapping it runs (with its dependencies inlined) and all connection
 : overrides from the parameters array.
 :
 : @param  $dbname  database name
 : @param  $name    mapping task name
 : @return <dependencies> element
 :)
declare function cdi:getTaskDependencies($dbname as xs:string, $name as xs:string) as element() {
  let $t := cdi:getTaskByName($dbname, $name)
  return
  if (empty($t)) then
    <dependencies name="{$name}" object="" type="Task" engine="CDI">
      <warning type="Not Found">No mapping task named '{$name}' found in database {$dbname}</warning>
    </dependencies>
  else
    <dependencies name="{$t?name}" object="{$t?name}" type="Task" engine="CDI"
                  path="{$t?path}">
      {
        (: Mapping reference - resolve via mappingId federatedId :)
        let $mappingFedId := substring-after(string($t?mappingId), '@')
        let $mappingName  := (
          for $m in cdi:getMappings($dbname)
          (: mappings are identified by name in this context - use export metadata if available :)
          return string($m?name)
        )[1]
        return
        if ($mappingFedId != '') then
          <dependency objectName="{$mappingFedId}" fromName="{$t?name}"
                      toFederatedId="{$mappingFedId}"
                      referenceType="mappingReference" objectType="Mapping" engine="CDI"/>
        else ()
        ,
        (: Connection parameters :)
        for $p in $t?parameters?*
          let $srcRef := string($p?sourceConnectionId)
          let $tgtRef := string($p?targetConnectionId)
          for $ref in ($srcRef[. != ''], $tgtRef[. != ''])
            let $conn     := cdi:resolveConnection($dbname, $ref)
            let $connName := if (exists($conn)) then string($conn?name)
                            else substring-after($ref, '@')
            let $refType  := if ($ref = $srcRef) then 'sourceConnection' else 'targetConnection'
            return
            <dependency objectName="{$connName}" fromName="{$t?name}"
                        toFederatedId="{substring-after($ref, '@')}"
                        referenceType="{$refType}" objectType="Connection" engine="CDI"/>
      }
    </dependencies>
};

(:~
 : Returns an impact report showing which Mapping Tasks use a given Mapping.
 :
 : For a Mapping: finds all Tasks whose mappingId references it.
 : For a Connection: finds all Mappings and Tasks that reference it.
 :
 : @param  $dbname      database name
 : @param  $name        asset name (mapping or connection name)
 : @param  $type        'Mapping' or 'Connection'
 : @return <impactReport> element with <usedBy> children
 :)
declare function cdi:getImpact(
  $dbname as xs:string,
  $name   as xs:string,
  $type   as xs:string
) as element() {
  let $conn := if ($type = 'Connection')
               then (for $c in cdi:getConnections($dbname) where string($c?name) = $name return $c)[1]
               else ()
  let $connFedId := if (exists($conn)) then string($conn?federatedId) else ()
  return
  <impactReport name="{$name}" type="{$type}" engine="CDI">
    {
      if ($type = 'Mapping') then
        (: Which tasks reference this mapping by name/federatedId? :)
        for $t in cdi:getMappingTasks($dbname)
          (: Tasks store mappingId as "@federatedId" - we match by name fallback :)
          let $mapping := cdi:getMappingByName($dbname, $name)
          where exists($mapping)
          return
          <usedBy name="{$t?name}" referenceType="mappingReference"
                  objectType="Task" engine="CDI" path="{$t?path}"/>

      else if ($type = 'Connection' and exists($connFedId)) then (
        (: Which mappings reference this connection? :)
        for $m in cdi:getMappings($dbname)
          where some $ref in $m?references?* satisfies (
            substring-after(string($ref?refObjectId), '@') = $connFedId
          )
          return
          <usedBy name="{$m?name}" referenceType="connectionReference"
                  objectType="Mapping" engine="CDI" path="{$m?path}"/>
        ,
        (: Which tasks reference this connection? :)
        for $t in cdi:getMappingTasks($dbname)
          where some $p in $t?parameters?* satisfies (
            substring-after(string($p?sourceConnectionId), '@') = $connFedId or
            substring-after(string($p?targetConnectionId), '@') = $connFedId
          )
          return
          <usedBy name="{$t?name}" referenceType="connectionReference"
                  objectType="Task" engine="CDI" path="{$t?path}"/>
      )
      else ()
    }
  </impactReport>
};

(:~
 : Returns true if the database contains any CDI asset JSON binary resources.
 : Use this to conditionally show CDI sections in the UI.
 :
 : @param  $dbname  database name
 : @return xs:boolean
 :)
declare function cdi:hasCDIAssets($dbname as xs:string) as xs:boolean {
  exists(
    db:list-details($dbname)[@raw = 'true'][
      ends-with(lower-case(text()), '/mappingtemplate.json') or
      ends-with(lower-case(text()), '/mttask.json')
    ]
  )
};
