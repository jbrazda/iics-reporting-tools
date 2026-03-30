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
  'Mapping'     : 'CDI Mapping',
  'MappingTask' : 'CDI Mapping Task',
  'Taskflow'    : 'CDI Taskflow',
  'Connection'  : 'CDI Connection'
};

(:~ CSS icon class for CDI asset types. :)
declare variable $chtml:CDI_TYPE_CLASS := map {
  'Mapping'     : 'cdi-mapping',
  'MappingTask' : 'cdi-task',
  'Taskflow'    : 'cdi-taskflow',
  'Connection'  : 'connection'
};

(:~ CSS icon class for CDI dependency reference types. :)
declare variable $chtml:CDI_REF_CLASS := map {
  'source'            : 'connection',
  'target'            : 'connection',
  'lookup'            : 'connection',
  'mappingReference'  : 'cdi-mapping',
  'connectionOverride': 'connection',
  'taskStep'          : 'cdi-task',
  'subflowStep'       : 'cdi-taskflow'
};

(:~
 : Renders a labeled icon div for a CDI asset. Falls back gracefully when icon is missing.
 :
 : @param  $type  CDI asset type ('Mapping', 'MappingTask', 'Taskflow', 'Connection')
 : @param  $name  display name
 : @return HTML div element
 :)
declare function chtml:objectWithIcon($type as xs:string?, $name as xs:string?) as item()* {
  let $imageUrl :=
    switch ($type)
      case 'Mapping'     return '/iics/static/icons/cdi-mapping.svg'
      case 'MappingTask' return '/iics/static/icons/cdi-task.svg'
      case 'Taskflow'    return '/iics/static/icons/cdi-taskflow.svg'
      default            return '/iics/static/icons/connections.svg'
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
          <th>ID</th>
          <th>Sources</th>
          <th>Targets</th>
          <th>Lookups</th>
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
              <td><code>{ string($m?id) }</code></td>
              <td>{ count($m?sources?*) }</td>
              <td>{ count($m?targets?*) }</td>
              <td>{ count($m?lookups?*) }</td>
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
          <th>ID</th>
          <th>Mapping</th>
          <th>Path</th>
        </tr>
      </thead>
      <tbody>
        {
          for $t in $tasks
            order by $t?name
            return
            <tr>
              <td>{ chtml:objectWithIcon('MappingTask', string($t?name)) }</td>
              <td><code>{ string($t?id) }</code></td>
              <td>{ string($t?mappingName) }</td>
              <td><small>{ string($t?path) }</small></td>
            </tr>
        }
      </tbody>
    </table>
};

(:~
 : Renders an HTML table listing all CDI Taskflows in the database.
 :
 : Columns: Name, ID, Steps, Path.
 : Table id "cdi_taskflows_table" is wired up for DataTables init.
 :
 : @param  $dbname  database name
 : @return HTML table, or info message if no taskflows exist
 :)
declare function chtml:TaskflowsTable($dbname as xs:string) as item()* {
  let $taskflows := cdi:getTaskflows($dbname)
  return
  if (empty($taskflows)) then
    <p class="infoMessage">No CDI Taskflows found in this database.</p>
  else
    <table id="cdi_taskflows_table" class="display compact">
      <thead>
        <tr>
          <th>Name</th>
          <th>ID</th>
          <th>Steps</th>
          <th>Path</th>
        </tr>
      </thead>
      <tbody>
        {
          for $tf in $taskflows
            order by $tf?name
            return
            <tr>
              <td>{ chtml:objectWithIcon('Taskflow', string($tf?name)) }</td>
              <td><code>{ string($tf?id) }</code></td>
              <td>{ count($tf?steps?*) }</td>
              <td><small>{ string($tf?path) }</small></td>
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
  let $label   := ($cdi:REF_TYPES($refType), $refType)[1]
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
 : Renders a full CDI Mapping detail section: metadata table, source/target/lookup lists,
 : dependency tree, and impact report.
 :
 : @param  $dbname  database name
 : @param  $id      mapping id
 : @return HTML section element
 :)
declare function chtml:MappingDetail($dbname as xs:string, $id as xs:string) as item()* {
  let $m      := cdi:getMappingById($dbname, $id)
  let $deps   := cdi:getMappingDependencies($dbname, $id)
  let $impact := cdi:getImpact($dbname, $id)
  return
  if (empty($m)) then
    <p class="warningMessage">No mapping with id { $id } found in { $dbname }.</p>
  else
  <div class="reportSection cdi-asset-detail">
    <h2>CDI Mapping — { string($m?name) }</h2>
    <table class="simpleTable">
      <tbody>
        <tr><td>ID</td>    <td><code>{ string($m?id) }</code></td></tr>
        <tr><td>Type</td>  <td>CDI Mapping</td></tr>
        <tr><td>Path</td>  <td><small>{ string($m?path) }</small></td></tr>
        <tr><td>Sources</td>
            <td>{ string-join(for $s in $m?sources?* return string($s?connectionName), ', ') }</td></tr>
        <tr><td>Targets</td>
            <td>{ string-join(for $t in $m?targets?* return string($t?connectionName), ', ') }</td></tr>
        {
          if (exists($m?lookups?*)) then
          <tr><td>Lookups</td>
              <td>{ string-join(for $l in $m?lookups?* return string($l?connectionName), ', ') }</td></tr>
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
 : Renders a full CDI Mapping Task detail section.
 :
 : @param  $dbname  database name
 : @param  $id      mapping task id
 : @return HTML section element
 :)
declare function chtml:TaskDetail($dbname as xs:string, $id as xs:string) as item()* {
  let $t      := cdi:getTaskById($dbname, $id)
  let $deps   := cdi:getTaskDependencies($dbname, $id)
  let $impact := cdi:getImpact($dbname, $id)
  return
  if (empty($t)) then
    <p class="warningMessage">No mapping task with id { $id } found in { $dbname }.</p>
  else
  <div class="reportSection cdi-asset-detail">
    <h2>CDI Mapping Task — { string($t?name) }</h2>
    <table class="simpleTable">
      <tbody>
        <tr><td>ID</td>      <td><code>{ string($t?id) }</code></td></tr>
        <tr><td>Type</td>    <td>CDI Mapping Task</td></tr>
        <tr><td>Mapping</td> <td>{ string($t?mappingName) }</td></tr>
        <tr><td>Path</td>    <td><small>{ string($t?path) }</small></td></tr>
      </tbody>
    </table>
    <h3>Dependencies</h3>
    { chtml:DependencyTree($deps) }
    <h3>Impact (Used By)</h3>
    { chtml:ImpactTree($impact) }
  </div>
};

(:~
 : Renders a full CDI Taskflow detail section.
 :
 : @param  $dbname  database name
 : @param  $id      taskflow id
 : @return HTML section element
 :)
declare function chtml:TaskflowDetail($dbname as xs:string, $id as xs:string) as item()* {
  let $tf     := cdi:getTaskflowById($dbname, $id)
  let $deps   := cdi:getTaskflowDependencies($dbname, $id)
  let $impact := cdi:getImpact($dbname, $id)
  return
  if (empty($tf)) then
    <p class="warningMessage">No taskflow with id { $id } found in { $dbname }.</p>
  else
  <div class="reportSection cdi-asset-detail">
    <h2>CDI Taskflow — { string($tf?name) }</h2>
    <table class="simpleTable">
      <tbody>
        <tr><td>ID</td>    <td><code>{ string($tf?id) }</code></td></tr>
        <tr><td>Type</td>  <td>CDI Taskflow</td></tr>
        <tr><td>Steps</td> <td>{ count($tf?steps?*) }</td></tr>
        <tr><td>Path</td>  <td><small>{ string($tf?path) }</small></td></tr>
      </tbody>
    </table>
    <h3>Step Sequence</h3>
    <ol>
      {
        for $step in $tf?steps?*
          let $stepType := upper-case(string($step?type))
          let $class    :=
            if ($stepType = 'TASK') then 'cdi-task'
            else if ($stepType = 'TASKFLOW') then 'cdi-taskflow'
            else 'cdi-asset'
          return
          <li><span class="icon {$class}">{ string($step?taskName) } [{ string($step?type) }]</span></li>
      }
    </ol>
    <h3>Dependencies</h3>
    { chtml:DependencyTree($deps) }
    <h3>Impact (Used By)</h3>
    { chtml:ImpactTree($impact) }
  </div>
};

(:~
 : Renders tabs containing all three CDI asset tables (Mappings, Tasks, Taskflows)
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
        <li><a href="#cdi-tab-taskflows">Taskflows</a></li>
      </ul>
      <div id="cdi-tab-mappings">
        { chtml:MappingsTable($dbname) }
      </div>
      <div id="cdi-tab-tasks">
        { chtml:TasksTable($dbname) }
      </div>
      <div id="cdi-tab-taskflows">
        { chtml:TaskflowsTable($dbname) }
      </div>
    </div>
  </div>
};
