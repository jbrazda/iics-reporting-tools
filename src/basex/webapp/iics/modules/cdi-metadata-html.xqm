(:~
 : CDI HTML rendering module.
 :
 : Provides functions to render CDI (Cloud Data Integration) asset tables, dependency
 : trees, and impact reports as HTML.
 :
 : Mirrors ipd-metadata-html.xqm in structure and naming conventions so both CAI and CDI
 : sections can coexist naturally in the same page layout.
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace chtml = 'iics/cdi-metadata-html';

import module namespace cdi = 'iics/cdi-metadata' at 'cdi-metadata.xqm';

declare namespace db = "http://basex.org/modules/db";

(:~ Human-readable labels for CDI asset types. :)
declare variable $chtml:CDI_TYPES := map {
  'Mapping'    : 'CDI Mapping',
  'Task'       : 'CDI Mapping Task',
  'Connection' : 'CDI Connection'
};

(:~ CSS icon class for CDI asset types. :)
declare variable $chtml:CDI_TYPE_CLASS := map {
  'Mapping'    : 'cdi-mapping',
  'Task'       : 'cdi-task',
  'Connection' : 'connection'
};

(:~ CSS icon class for CDI dependency reference types. :)
declare variable $chtml:CDI_REF_CLASS := map {
  'connectionReference' : 'connection',
  'mappingReference'    : 'cdi-mapping',
  'sourceConnection'    : 'connection',
  'targetConnection'    : 'connection'
};

(:~
 : Renders a labeled icon div for a CDI asset. Falls back gracefully when icon is missing.
 :
 : @param  $type  CDI asset type ('Mapping', 'Task', 'Connection')
 : @param  $name  display name
 : @return HTML div element
 :)
declare function chtml:objectWithIcon($type as xs:string?, $name as xs:string?) as item()* {
  let $imageUrl :=
    switch ($type)
      case 'Mapping'    return '/iics/static/icons/cdi-mapping.svg'
      case 'Task'       return '/iics/static/icons/cdi-task.svg'
      case 'Connection' return '/iics/static/icons/connections.svg'
      default           return '/iics/static/icons/connections.svg'
  return
  <div title="{$name}" class="noWrapLabel">
    <img class="shellLibNameImage" src="{$imageUrl}" onerror="this.style.display='none'"/>
    <span class="shellLibNameMargin">{$name}</span>
  </div>
};

(:~
 : Renders an HTML table listing all CDI Mappings in the database.
 :
 : Columns: Name, ID, Sources, Targets, Lookups, Path.
 : Table id "cdi_mappings_table" is wired up for DataTables init in iics-reporting.js.
 :
 : @param  $dbname  database name
 : @return HTML table, or info message if no mappings exist
 :)
declare function chtml:MappingsTable($dbname as xs:string) as item()* {
  let $mappings := cdi:getMappings($dbname)
  return
  if (empty($mappings)) then
    <p class="infoMessage">No CDI Mappings found in this database.</p>
  else
    <table id="cdi_mappings_table" class="display compact">
      <thead>
        <tr>
          <th>Name</th>
          <th>Connections</th>
          <th>Path</th>
        </tr>
      </thead>
      <tbody>
        {
          for $m in $mappings
            order by $m?name
            return
            <tr>
              <td>{ chtml:objectWithIcon('Mapping', string($m?name)) }</td>
              <td>{ count($m?references?*[string(.?refType) = 'connection']) }</td>
              <td><small>{ string($m?path) }</small></td>
            </tr>
        }
      </tbody>
    </table>
};

(:~
 : Renders an HTML table listing all CDI Mapping Tasks in the database.
 :
 : Columns: Name, ID, Mapping, Path.
 : Table id "cdi_tasks_table" is wired up for DataTables init.
 :
 : @param  $dbname  database name
 : @return HTML table, or info message if no tasks exist
 :)
declare function chtml:TasksTable($dbname as xs:string) as item()* {
  let $tasks := cdi:getMappingTasks($dbname)
  return
  if (empty($tasks)) then
    <p class="infoMessage">No CDI Mapping Tasks found in this database.</p>
  else
    <table id="cdi_tasks_table" class="display compact">
      <thead>
        <tr>
          <th>Name</th>
          <th>Mapping FederatedId</th>
          <th>Path</th>
        </tr>
      </thead>
      <tbody>
        {
          for $t in $tasks
            order by $t?name
            return
            <tr>
              <td>{ chtml:objectWithIcon('Task', string($t?name)) }</td>
              <td><code>{ substring-after(string($t?mappingId), '@') }</code></td>
              <td><small>{ string($t?path) }</small></td>
            </tr>
        }
      </tbody>
    </table>
};

(:~
 : Renders an HTML table listing all CDI Connections in the database.
 :
 : Columns: Name, FederatedId, Type, Path.
 : Table id "cdi_connections_table" is wired up for DataTables init.
 :
 : @param  $dbname  database name
 : @return HTML table, or info message if no connections exist
 :)
declare function chtml:ConnectionsTable($dbname as xs:string) as item()* {
  let $connections := cdi:getConnections($dbname)
  return
  if (empty($connections)) then
    <p class="infoMessage">No CDI Connections found in this database.</p>
  else
    <table id="cdi_connections_table" class="display compact">
      <thead>
        <tr>
          <th>Name</th>
          <th>FederatedId</th>
          <th>Type</th>
          <th>Path</th>
        </tr>
      </thead>
      <tbody>
        {
          for $c in $connections
            order by $c?name
            return
            <tr>
              <td>{ chtml:objectWithIcon('Connection', string($c?name)) }</td>
              <td><code>{ string($c?federatedId) }</code></td>
              <td>{ string($c?type) }</td>
              <td><small>{ string($c?path) }</small></td>
            </tr>
        }
      </tbody>
    </table>
};

(:~
 : Renders a CDI dependency tree as a nested HTML unordered list.
 : Mirrors mhtml:DependencyTree from ipd-metadata-html.xqm.
 :
 : @param  $node  <dependencies> or <dependency> element
 : @return HTML <ul> element, or empty sequence if no dependency children
 :)
declare function chtml:DependencyTree($node as element()) as item()* {
  let $children :=
    for $dep in $node/dependency
      return chtml:DependencyTreeNode($dep)
  return
    if (empty($children)) then ()
    else <ul>{ $children }</ul>
};

(:~
 : Renders a single CDI dependency element as an HTML list item with type icon.
 :
 : @param  $dep  <dependency> element
 : @return HTML <li> element
 :)
declare function chtml:DependencyTreeNode($dep as element()) as item()* {
  let $name    := string($dep/@objectName)
  let $refType := string($dep/@referenceType)
  let $objType := string($dep/@objectType)
  let $label   := $refType
  let $class   := ($chtml:CDI_REF_CLASS($refType), $chtml:CDI_TYPE_CLASS($objType), 'cdi-asset')[. != ''][1]
  return
  <li>
    <span class="icon {$class}">{ $name } [{ $label }]</span>
    { chtml:DependencyTree($dep) }
    {
      for $w in $dep/warning
        return <span class="warningMessage">{ string($w/@type) }: { string($w) }</span>
    }
  </li>
};

(:~
 : Renders a CDI impact report as a nested HTML list.
 :
 : @param  $report  <impactReport> element from cdi:getImpact()
 : @return HTML list, or info message if no impact detected
 :)
declare function chtml:ImpactTree($report as element()) as item()* {
  let $items :=
    for $u in $report/usedBy
      let $type  := string($u/@objectType)
      let $class := ($chtml:CDI_TYPE_CLASS($type), 'cdi-asset')[. != ''][1]
      return
      <li>
        <span class="icon {$class}">{ string($u/@name) } [{ string($u/@referenceType) }]</span>
      </li>
  return
    if (empty($items)) then
      <p class="infoMessage">No impact detected — this asset is not referenced by other CDI assets.</p>
    else
      <ul>{ $items }</ul>
};

(:~
 : Renders a full CDI Mapping detail section: metadata table, connection references,
 : dependency tree, and impact report.
 :
 : @param  $dbname  database name
 : @param  $name    mapping name
 : @return HTML section element
 :)
declare function chtml:MappingDetail($dbname as xs:string, $name as xs:string) as item()* {
  let $m      := cdi:getMappingByName($dbname, $name)
  let $deps   := cdi:getMappingDependencies($dbname, $name)
  let $impact := cdi:getImpact($dbname, $name, 'Mapping')
  return
  if (empty($m)) then
    <p class="warningMessage">No mapping named '{ $name }' found in { $dbname }.</p>
  else
  <div class="reportSection cdi-asset-detail">
    <h2>CDI Mapping - { string($m?name) }</h2>
    <table class="simpleTable">
      <tbody>
        <tr><td>Type</td> <td>CDI Mapping</td></tr>
        <tr><td>Path</td> <td><small>{ string($m?path) }</small></td></tr>
        <tr>
          <td>Connections</td>
          <td>
            {
              string-join(
                for $ref in $m?references?*
                  where string($ref?refType) = 'connection'
                  let $conn := cdi:resolveConnection($dbname, string($ref?refObjectId))
                  return if (exists($conn)) then string($conn?name)
                         else substring-after(string($ref?refObjectId), '@'),
                ', '
              )
            }
          </td>
        </tr>
      </tbody>
    </table>
    <h3>Dependencies</h3>
    { chtml:DependencyTree($deps) }
    <h3>Impact (Used By)</h3>
    { chtml:ImpactTree($impact) }
  </div>
};

(:~
 : Renders a full CDI Mapping Task detail section.
 :
 : @param  $dbname  database name
 : @param  $name    mapping task name
 : @return HTML section element
 :)
declare function chtml:TaskDetail($dbname as xs:string, $name as xs:string) as item()* {
  let $t      := cdi:getTaskByName($dbname, $name)
  let $deps   := cdi:getTaskDependencies($dbname, $name)
  let $impact := cdi:getImpact($dbname, $name, 'Task')
  return
  if (empty($t)) then
    <p class="warningMessage">No mapping task named '{ $name }' found in { $dbname }.</p>
  else
  <div class="reportSection cdi-asset-detail">
    <h2>CDI Mapping Task - { string($t?name) }</h2>
    <table class="simpleTable">
      <tbody>
        <tr><td>Type</td>       <td>CDI Mapping Task</td></tr>
        <tr><td>Mapping ID</td> <td><code>{ substring-after(string($t?mappingId), '@') }</code></td></tr>
        <tr><td>Path</td>       <td><small>{ string($t?path) }</small></td></tr>
        {
          let $conns :=
            for $p in $t?parameters?*
              let $src := string($p?sourceConnectionId)
              let $tgt := string($p?targetConnectionId)
              for $ref in ($src[. != ''], $tgt[. != ''])
                let $conn := cdi:resolveConnection($dbname, $ref)
                return if (exists($conn)) then string($conn?name)
                       else substring-after($ref, '@')
          return
          if (exists($conns)) then
          <tr><td>Connections</td><td>{ string-join($conns, ', ') }</td></tr>
          else ()
        }
      </tbody>
    </table>
    <h3>Dependencies</h3>
    { chtml:DependencyTree($deps) }
    <h3>Impact (Used By)</h3>
    { chtml:ImpactTree($impact) }
  </div>
};

(:~
 : Renders tabs containing CDI asset tables (Mappings, Mapping Tasks, Connections)
 : for the database overview report.
 :
 : Returns an empty sequence if the database has no CDI assets.
 :
 : @param  $dbname  database name
 : @return HTML div element with jQuery UI tabs, or empty sequence
 :)
declare function chtml:CDISection($dbname as xs:string) as item()* {
  if (not(cdi:hasCDIAssets($dbname))) then ()
  else
  <div class="reportSection">
    <h2>CDI Assets</h2>
    <div id="cdi-tabs">
      <ul>
        <li><a href="#cdi-tab-mappings">Mappings</a></li>
        <li><a href="#cdi-tab-tasks">Mapping Tasks</a></li>
        <li><a href="#cdi-tab-connections">Connections</a></li>
      </ul>
      <div id="cdi-tab-mappings">
        { chtml:MappingsTable($dbname) }
      </div>
      <div id="cdi-tab-tasks">
        { chtml:TasksTable($dbname) }
      </div>
      <div id="cdi-tab-connections">
        { chtml:ConnectionsTable($dbname) }
      </div>
    </div>
  </div>
};
