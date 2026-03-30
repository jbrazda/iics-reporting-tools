(:~
 : CDI metadata analysis module.
 :
 : Provides functions to analyze CDI (Cloud Data Integration) assets stored in a BaseX
 : database after nested ZIP extraction (see cdi-extract.xqm).
 :
 : CDI assets — Mappings, Mapping Tasks, and Taskflows — are stored as binary JSON
 : resources at paths like:
 :
 :   Explore/CDI/MP_SomeMapping/mapping.json
 :   Explore/CDI/MT_SomeTask/mappingtask.json
 :   Explore/CDI/TF_SomeFlow/taskflow.json
 :
 : JSON is stored as raw binary (via db:store) so it can be reliably retrieved and
 : parsed with json:parse(). Use cdi:hasCDIAssets($dbname) to check before querying.
 :
 : Dependency output format mirrors the XML structure produced by ipd-metadata.xqm
 : so that the same rendering functions can be used or adapted for both CAI and CDI.
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace cdi = 'iics/cdi-metadata';

declare namespace db      = "http://basex.org/modules/db";
declare namespace convert = "http://basex.org/modules/convert";

(:~ Human-readable labels for CDI asset types. :)
declare variable $cdi:TYPES := map {
  'Mapping'     : 'CDI Mapping',
  'MappingTask' : 'CDI Mapping Task',
  'Taskflow'    : 'CDI Taskflow',
  'Connection'  : 'CDI Connection'
};

(:~ Human-readable labels for CDI dependency reference types. :)
declare variable $cdi:REF_TYPES := map {
  'source'            : 'Source Connection',
  'target'            : 'Target Connection',
  'lookup'            : 'Lookup Connection',
  'mappingReference'  : 'Mapping Reference',
  'connectionOverride': 'Connection Override',
  'taskStep'          : 'Task Step',
  'subflowStep'       : 'Nested Taskflow'
};

(:~
 : Retrieves a binary JSON resource from the database and parses it into an XQuery map.
 :
 : JSON files are stored as binary (xs:base64Binary) via db:store() during extraction.
 : This function retrieves and decodes the binary, then parses the JSON text.
 :
 : @param  $dbname  database name
 : @param  $path    path of the binary resource within the database
 : @return parsed JSON as XQuery map(*)
 :)
declare function cdi:parse-json($dbname as xs:string, $path as xs:string) as map(*) {
  let $bin  := db:retrieve($dbname, $path)
  let $text := convert:binary-to-string($bin, 'UTF-8')
  return json:parse($text)
};

(:~
 : Returns paths of all CDI Mapping JSON binary resources in the database.
 :
 : @param  $dbname  database name
 : @return sequence of paths ending in /mapping.json
 :)
declare function cdi:mapping-paths($dbname as xs:string) as xs:string* {
  db:list-details($dbname)[@raw = 'true']
    [ends-with(lower-case(text()), '/mapping.json')]/text()
};

(:~
 : Returns paths of all CDI Mapping Task JSON binary resources in the database.
 :
 : @param  $dbname  database name
 : @return sequence of paths ending in /mappingtask.json
 :)
declare function cdi:task-paths($dbname as xs:string) as xs:string* {
  db:list-details($dbname)[@raw = 'true']
    [ends-with(lower-case(text()), '/mappingtask.json')]/text()
};

(:~
 : Returns paths of all CDI Taskflow JSON binary resources in the database.
 :
 : @param  $dbname  database name
 : @return sequence of paths ending in /taskflow.json
 :)
declare function cdi:taskflow-paths($dbname as xs:string) as xs:string* {
  db:list-details($dbname)[@raw = 'true']
    [ends-with(lower-case(text()), '/taskflow.json')]/text()
};

(:~
 : Returns all CDI Mappings in the database as a sequence of XQuery maps.
 : Each map is the parsed mapping.json content augmented with a synthetic "path" key.
 :
 : Expected JSON structure:
 :   { "id": "...", "name": "MP_...",
 :     "sources": [{"connectionId": "...", "connectionName": "..."}],
 :     "targets": [{"connectionId": "...", "connectionName": "..."}],
 :     "lookups": [{"connectionId": "...", "connectionName": "..."}] }
 :
 : @param  $dbname  database name
 : @return sequence of maps
 :)
declare function cdi:getMappings($dbname as xs:string) as map(*)* {
  for $path in cdi:mapping-paths($dbname)
    let $m := cdi:parse-json($dbname, $path)
    return map:merge(($m, map { 'path': $path }))
};

(:~
 : Returns all CDI Mapping Tasks in the database as a sequence of XQuery maps.
 : Each map is the parsed mappingtask.json content augmented with a synthetic "path" key.
 :
 : Expected JSON structure:
 :   { "id": "...", "name": "MT_...", "mappingId": "...", "mappingName": "...",
 :     "connections": [{"type": "SOURCE", "connectionId": "...", "connectionName": "..."}] }
 :
 : @param  $dbname  database name
 : @return sequence of maps
 :)
declare function cdi:getMappingTasks($dbname as xs:string) as map(*)* {
  for $path in cdi:task-paths($dbname)
    let $m := cdi:parse-json($dbname, $path)
    return map:merge(($m, map { 'path': $path }))
};

(:~
 : Returns all CDI Taskflows in the database as a sequence of XQuery maps.
 : Each map is the parsed taskflow.json content augmented with a synthetic "path" key.
 :
 : Expected JSON structure:
 :   { "id": "...", "name": "TF_...",
 :     "steps": [{"type": "TASK", "taskId": "...", "taskName": "..."}, ...] }
 :
 : @param  $dbname  database name
 : @return sequence of maps
 :)
declare function cdi:getTaskflows($dbname as xs:string) as map(*)* {
  for $path in cdi:taskflow-paths($dbname)
    let $m := cdi:parse-json($dbname, $path)
    return map:merge(($m, map { 'path': $path }))
};

(:~
 : Finds a CDI Mapping by its id field.
 :
 : @param  $dbname  database name
 : @param  $id      mapping id
 : @return first matching map, or empty sequence if not found
 :)
declare function cdi:getMappingById($dbname as xs:string, $id as xs:string) as map(*)? {
  (for $m in cdi:getMappings($dbname) where $m?id = $id return $m)[1]
};

(:~
 : Finds a CDI Mapping Task by its id field.
 :
 : @param  $dbname  database name
 : @param  $id      mapping task id
 : @return first matching map, or empty sequence if not found
 :)
declare function cdi:getTaskById($dbname as xs:string, $id as xs:string) as map(*)? {
  (for $t in cdi:getMappingTasks($dbname) where $t?id = $id return $t)[1]
};

(:~
 : Finds a CDI Taskflow by its id field.
 :
 : @param  $dbname  database name
 : @param  $id      taskflow id
 : @return first matching map, or empty sequence if not found
 :)
declare function cdi:getTaskflowById($dbname as xs:string, $id as xs:string) as map(*)? {
  (for $tf in cdi:getTaskflows($dbname) where $tf?id = $id return $tf)[1]
};

(:~
 : Returns dependency XML for a CDI Mapping.
 :
 : Produces one dependency child element per source, target, and lookup connection.
 : Output XML format mirrors ipd-metadata.xqm <dependencies> structure.
 :
 : @param  $dbname     database name
 : @param  $mappingId  mapping id
 : @return <dependencies> element
 :)
declare function cdi:getMappingDependencies($dbname as xs:string, $mappingId as xs:string) as element() {
  let $m := cdi:getMappingById($dbname, $mappingId)
  return
  if (empty($m)) then
    <dependencies id="{$mappingId}" object="" type="Mapping" engine="CDI">
      <warning type="Not Found">No mapping with id {$mappingId} found in database {$dbname}</warning>
    </dependencies>
  else
    <dependencies id="{$m?id}" object="{$m?name}" type="Mapping" engine="CDI" path="{$m?path}">
      {
        for $src in $m?sources?*
          return
          <dependency objectName="{$src?connectionName}" fromId="{$m?id}" toId="{$src?connectionId}"
                      fromName="{$m?name}" referenceType="source" objectType="Connection" engine="CDI"/>
        ,
        for $tgt in $m?targets?*
          return
          <dependency objectName="{$tgt?connectionName}" fromId="{$m?id}" toId="{$tgt?connectionId}"
                      fromName="{$m?name}" referenceType="target" objectType="Connection" engine="CDI"/>
        ,
        for $lkp in $m?lookups?*
          return
          <dependency objectName="{$lkp?connectionName}" fromId="{$m?id}" toId="{$lkp?connectionId}"
                      fromName="{$m?name}" referenceType="lookup" objectType="Connection" engine="CDI"/>
      }
    </dependencies>
};

(:~
 : Returns dependency XML for a CDI Mapping Task.
 :
 : Includes the mapping it executes (with its own dependencies inlined) and any
 : connection overrides defined on the task.
 :
 : @param  $dbname  database name
 : @param  $taskId  mapping task id
 : @return <dependencies> element
 :)
declare function cdi:getTaskDependencies($dbname as xs:string, $taskId as xs:string) as element() {
  let $t := cdi:getTaskById($dbname, $taskId)
  return
  if (empty($t)) then
    <dependencies id="{$taskId}" object="" type="MappingTask" engine="CDI">
      <warning type="Not Found">No mapping task with id {$taskId} found in database {$dbname}</warning>
    </dependencies>
  else
    <dependencies id="{$t?id}" object="{$t?name}" type="MappingTask" engine="CDI" path="{$t?path}">
      {
        if (exists($t?mappingId) and string($t?mappingId) != '') then
          <dependency objectName="{$t?mappingName}" fromId="{$t?id}" toId="{$t?mappingId}"
                      fromName="{$t?name}" referenceType="mappingReference" objectType="Mapping" engine="CDI">
            { cdi:getMappingDependencies($dbname, string($t?mappingId))/* }
          </dependency>
        else ()
        ,
        for $con in $t?connections?*
          return
          <dependency objectName="{$con?connectionName}" fromId="{$t?id}" toId="{$con?connectionId}"
                      fromName="{$t?name}" referenceType="connectionOverride" objectType="Connection" engine="CDI"/>
      }
    </dependencies>
};

(:~
 : Returns dependency XML for a CDI Taskflow.
 :
 : Recursively expands TASK steps (mapping tasks) and TASKFLOW steps (nested taskflows).
 : Cycle detection uses the $visited stack of already-seen taskflow ids.
 :
 : @param  $dbname   database name
 : @param  $tfId     taskflow id
 : @param  $visited  sequence of taskflow ids already on the call stack (cycle guard)
 : @return <dependencies> element
 :)
declare function cdi:getTaskflowDependencies(
  $dbname  as xs:string,
  $tfId    as xs:string,
  $visited as xs:string*
) as element() {
  let $tf := cdi:getTaskflowById($dbname, $tfId)
  return
  if (empty($tf)) then
    <dependencies id="{$tfId}" object="" type="Taskflow" engine="CDI">
      <warning type="Not Found">No taskflow with id {$tfId} found in database {$dbname}</warning>
    </dependencies>
  else
    let $newVisited := ($visited, $tfId)
    return
    <dependencies id="{$tf?id}" object="{$tf?name}" type="Taskflow" engine="CDI" path="{$tf?path}">
      {
        for $step in $tf?steps?*
          let $stepType := upper-case(string($step?type))
          return
          switch ($stepType)
            case 'TASK' return
              <dependency objectName="{$step?taskName}" fromId="{$tf?id}" toId="{$step?taskId}"
                          fromName="{$tf?name}" referenceType="taskStep" objectType="MappingTask" engine="CDI">
                { cdi:getTaskDependencies($dbname, string($step?taskId))/* }
              </dependency>
            case 'TASKFLOW' return
              if (string($step?taskId) = $newVisited) then
                <dependency objectName="{$step?taskName}" fromId="{$tf?id}" toId="{$step?taskId}"
                            fromName="{$tf?name}" referenceType="subflowStep" objectType="Taskflow" engine="CDI">
                  <warning type="Cycle Detected">Circular taskflow reference to {$step?taskId} prevented</warning>
                </dependency>
              else
                <dependency objectName="{$step?taskName}" fromId="{$tf?id}" toId="{$step?taskId}"
                            fromName="{$tf?name}" referenceType="subflowStep" objectType="Taskflow" engine="CDI">
                  { cdi:getTaskflowDependencies($dbname, string($step?taskId), $newVisited)/* }
                </dependency>
            default return ()
      }
    </dependencies>
};

(:~
 : Convenience wrapper for cdi:getTaskflowDependencies with an empty visited stack.
 :
 : @param  $dbname  database name
 : @param  $tfId    taskflow id
 : @return <dependencies> element
 :)
declare function cdi:getTaskflowDependencies($dbname as xs:string, $tfId as xs:string) as element() {
  cdi:getTaskflowDependencies($dbname, $tfId, ())
};

(:~
 : Dispatches dependency analysis to the correct type-specific function.
 :
 : Detects the asset type by searching all type collections for $id, then calls
 : getMappingDependencies, getTaskDependencies, or getTaskflowDependencies accordingly.
 :
 : @param  $dbname  database name
 : @param  $id      any CDI asset id
 : @return <dependencies> element
 :)
declare function cdi:getAssetDependencies($dbname as xs:string, $id as xs:string) as element() {
  let $mapping  := cdi:getMappingById($dbname, $id)
  let $task     := if (empty($mapping)) then cdi:getTaskById($dbname, $id)     else ()
  let $taskflow := if (empty($mapping) and empty($task)) then cdi:getTaskflowById($dbname, $id) else ()
  return
    if (exists($mapping))  then cdi:getMappingDependencies($dbname, $id)
    else if (exists($task)) then cdi:getTaskDependencies($dbname, $id)
    else if (exists($taskflow)) then cdi:getTaskflowDependencies($dbname, $id)
    else
      <dependencies id="{$id}" object="" engine="CDI">
        <warning type="Not Found">No CDI asset with id {$id} found in database {$dbname}</warning>
      </dependencies>
};

(:~
 : Returns an impact report showing which higher-level CDI assets reference a given asset.
 :
 : - Mapping  → finds Mapping Tasks that reference it via mappingId
 : - MappingTask → finds Taskflows that include it as a TASK step
 : - Taskflow    → finds Taskflows that include it as a TASKFLOW step
 :
 : @param  $dbname  database name
 : @param  $id      CDI asset id
 : @return <impactReport> element with <usedBy> children
 :)
declare function cdi:getImpact($dbname as xs:string, $id as xs:string) as element() {
  let $mapping  := cdi:getMappingById($dbname, $id)
  let $task     := if (empty($mapping)) then cdi:getTaskById($dbname, $id)     else ()
  let $taskflow := if (empty($mapping) and empty($task)) then cdi:getTaskflowById($dbname, $id) else ()
  let $name   := (string($mapping?name), string($task?name), string($taskflow?name), $id)[. != ''][1]
  let $type   :=
    if (exists($mapping))  then 'Mapping'
    else if (exists($task)) then 'MappingTask'
    else if (exists($taskflow)) then 'Taskflow'
    else 'Unknown'
  return
  <impactReport id="{$id}" name="{$name}" type="{$type}" engine="CDI">
    {
      if ($type = 'Mapping') then
        for $t in cdi:getMappingTasks($dbname)
          where string($t?mappingId) = $id
          return
          <usedBy name="{$t?name}" id="{$t?id}" referenceType="mappingReference"
                  objectType="MappingTask" engine="CDI" path="{$t?path}"/>

      else if ($type = 'MappingTask') then
        for $tf in cdi:getTaskflows($dbname)
          where some $s in $tf?steps?* satisfies (
            upper-case(string($s?type)) = 'TASK' and string($s?taskId) = $id
          )
          return
          <usedBy name="{$tf?name}" id="{$tf?id}" referenceType="taskStep"
                  objectType="Taskflow" engine="CDI" path="{$tf?path}"/>

      else if ($type = 'Taskflow') then
        for $tf in cdi:getTaskflows($dbname)
          where some $s in $tf?steps?* satisfies (
            upper-case(string($s?type)) = 'TASKFLOW' and string($s?taskId) = $id
          )
          return
          <usedBy name="{$tf?name}" id="{$tf?id}" referenceType="subflowStep"
                  objectType="Taskflow" engine="CDI" path="{$tf?path}"/>

      else ()
    }
  </impactReport>
};

(:~
 : Returns true if the database contains any CDI asset JSON binary resources.
 :
 : Use this to conditionally show CDI sections in the UI.
 :
 : @param  $dbname  database name
 : @return xs:boolean
 :)
declare function cdi:hasCDIAssets($dbname as xs:string) as xs:boolean {
  exists(
    db:list-details($dbname)[@raw = 'true'][
      ends-with(lower-case(text()), '/mapping.json')     or
      ends-with(lower-case(text()), '/mappingtask.json') or
      ends-with(lower-case(text()), '/taskflow.json')
    ]
  )
};
