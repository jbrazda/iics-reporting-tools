module namespace report = 'iics/report';

import module namespace html   = 'iics/html' at 'modules/html.xqm';
import module namespace mhtml  = 'iics/ipd-metadata-html' at 'modules/ipd-metadata-html.xqm';

(:ICAI namespaces:)
declare namespace sfd = "http://schemas.active-endpoints.com/appmodules/screenflow/2010/10/avosScreenflow.xsd";
declare namespace svc = "http://schemas.informatica.com/socrates/data-services/2014/05/business-connector-model.xsd";
declare namespace con = "http://schemas.informatica.com/socrates/data-services/2014/04/avosConnections.xsd";
declare namespace cnt = "http://schemas.informatica.com/appmodules/screenflow/2014/04/avosConnectors.xsd";
declare namespace hen = "http://schemas.active-endpoints.com/appmodules/screenflow/2011/06/avosHostEnvironment.xsd";
declare namespace rep = "http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd";

(:basex namespaces:)
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace math   = "http://www.w3.org/2005/xpath-functions/math";
declare namespace db     = "http://basex.org/modules/db";
declare namespace rest   = "http://exquery.org/ns/restxq";


declare
  %rest:path("/iics/report")
  %output:method("html")
  %output:omit-xml-declaration("yes")
  %rest:query-param("database",    "{$database}")
function report:start(
   $database as xs:string
) as element(html) {
    let $error := ()
    let $db := db:open($database)

    let $connectors     := $db//rep:Item[exists(//svc:businessConnector)]
    let $connections    := $db//rep:Item[exists(//con:connection)]
    let $processObjects := $db//rep:Item[exists(rep:Entry/hen:processObject)]
    let $processes      := $db//rep:Item[exists(//sfd:process)]
    let $guides         := $db//rep:Item[exists(//sfd:avosScreenflow)]
    let $pathPrefix     := concat("/rest/",$database)
                            
    let $objects := $db//*:Item
    let $summary :=  <summary
                total-items="{count($objects)}" 
                distinct-Status="{count(distinct-values($objects/*:MimeType))}">
            {
            for $item in $objects
            let $g := $item/*:MimeType/text()
            group by $g 
            order by $g
            count $id
            return 
            <object type="{$g}" count="{count($item)}"/>
            }
        </summary>

    (: Excludimg process Object from Publication statius stats as thesse are not being published:)
    let $items := $db//*:Item[*:MimeType != 'application/xml+processobject']
    let $deploymentStatusStats :=
        <stats 
                total-items="{count($items)}" 
                distinct-Status="{count(distinct-values($items/*:PublicationStatus))}">
            {
            for $item in $items
            let $ps := $item/*:PublicationStatus/text()
            group by $ps 
            order by $ps
            count $id
            return 
            <deploymentStatus status="{$ps}" count="{count($item)}"/>
            }
        </stats>

    let $createdByStats :=
        <stats 
            total-items="{count($items)}" 
            distinct-CreatedBy="{count(distinct-values($items/*:CreatedBy))}">
            {
            for $item in $items
            let $g := $item/*:CreatedBy/text()
            group by $g 
            order by $g
            count $id
            return 
            <createdBy name="{$g}" count="{count($item)}"/>
            }
        </stats>
    let $countModifiers :=  $db//*:Item[*:MimeType != 'application/xml+processobject' and not(empty(*:ModifiedBy)) ]
    let $modifiedByStats :=
        <stats 
            total-items="{count($items)}" 
            distinct-ModifiedBy="{count(distinct-values($items/*:ModifiedBy))}">
            {
            for $item in $items
            let $g := $item/*:ModifiedBy/text()
            group by $g 
            order by $g
            count $id
            return 
            <modifiedBy name="{$g}" count="{count($item)}"/>
            }
        </stats>
    
    
    return html:wrap(map { 
      'header' : ($database),  
      'error'  : $error, 
      'css'    : ('https://cdn.datatables.net/v/ju-1.11.4/jq-2.2.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.css'),
      'scripts': ('https://cdn.datatables.net/v/ju-1.11.4/jq-2.2.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.js', 
                  'https://cdn.plot.ly/plotly-latest.min.js'),
      'inlineScripts' : 
      <script type="text/javascript" charset="utf-8">
          $(document).ready(function() {{
            $("table.display" ).DataTable({{
                jQueryUI : true,
                scrollX : true,
                scrollY : false,
                lengthMenu : [[10, 25, 50, 100,  -1], [10, 25, 50, 100, "All"]],
                paging : true,
                dom: 'BlfrtFip',
                buttons: [
                    'colvis',
                    'copy',
                    {{
                        extend: 'excel',
                        filename: 'designs_report',
                    }},
                    'csvHtml5',
                    'print'
                ]
                }});
            $("#tabs" ).tabs(); 
            var objectStats = [{{
                values: [{string-join(data($summary/object/@count),",")} ],
                labels: [{string-join(for $item in data($summary/object/@type) return concat("'",$mhtml:IPD_TYPES($item),"'"),",")}],
                type: 'pie',
                title: 'Object Types'
                }}];

            var deploymentStats = [{{
                values: [{string-join(data($deploymentStatusStats/deploymentStatus/@count),",")}],
                labels: [{string-join(for $item in $deploymentStatusStats/deploymentStatus/@status return concat("'",$item,"'"),",")}],
                type: 'pie',
                title: 'Deployment Status'
            }}];

            var createdByStats = [{{
                values: [{string-join(data($createdByStats/createdBy/@count),",")}],
                labels: [{string-join(for $item in $createdByStats/createdBy/@name return concat("'",$item,"'"),",")}],
                type: 'pie',
                title: 'Created By Stats'
            }}];
            
            var modifiedByStats = [{{
                values: [{string-join(data($modifiedByStats/modifiedBy/@count),",")}],
                labels: [{string-join(for $item in $modifiedByStats/modifiedBy/@name return concat("'",$item,"'"),",")}],
                type: 'pie',
                title: 'Modified By Stats'
            }}];
            

            var chartLayout = {{
            height: 400,
            width: 600,
            paper_bgcolor: "#EEEEEE"
            }};

            var userStatsLayout = {{
            height: 400,
            width: 800,
            paper_bgcolor: "#EEEEEE"
            }};
            Plotly.newPlot('objects_chart', objectStats, chartLayout);
            Plotly.newPlot('deployment_status_chart', deploymentStats, chartLayout);
            Plotly.newPlot('createdBy_chart', createdByStats, userStatsLayout);
            Plotly.newPlot('modifiedBy_chart', modifiedByStats, userStatsLayout);
        }});
      </script>
    },
    <body>
        {html:pageHeader(map { 
                        'breadCrumbs': <breadcrumbs>
                                    <a href="/iics/database">Databases</a>
                                    <a href="/iics/report?database={$database}">{$database}</a>
                                </breadcrumbs>
                         },())}
        <div id="tabs">
            <ul>
                <li><a href="#summary">Summary</a></li>
                <li><a href="#connectors">Connectors</a></li>
                <li><a href="#connections">Connections</a></li>
                <li><a href="#processObjects">Process Objects</a></li>
                <li><a href="#processes">Processes</a></li>
                <li><a href="#guides">Guides</a></li>
            </ul>
            <div id="summary">
                <h2>Summary</h2>
                <div id="#summary_container" class="summaryContainer">
                    <div id="object_list" class="summaryColumn" style="padding-top: 100px">
                        <table class="simpleTable" id="summary_table" style="margin-right:auto;margin-left:0px">
                        <thead>
                        <tr>
                            <th>Object</th>
                            <th>Count</th>
                        </tr>
                        </thead>
                        <tbody>            
                            {   
                            for $object in $summary/object
                            let $name := $mhtml:IPD_TYPES($object/@type) 
                            let $value := data($object/@count)
                            
                            return
                            <tr>
                                <td>{$name}</td>
                                <td style="text-align: right;">{$value}</td>
                            </tr>
                            }
                            <tr>
                                <td style="font-weight: bold;">All Objects</td>
                                <td style="text-align: right;font-weight: bold;">{count($objects)}</td>
                            </tr>
                        </tbody>
                        </table>
                    </div>
                    <div id="objects_chart" class="summaryColumn">
                    </div>
                    <div id="deployment_status_chart" class="summaryColumn">
                    </div>
                    <div id="createdBy_chart" class="summaryColumn">
                    </div>
                    <div id="modifiedBy_chart" class="summaryColumn">
                    </div>
                </div><!--END div #summary_container -->
                <div class="tableWrapper">
                    <table class="display" id="all_objects" style="margin-right:auto;margin-left:0px">
                    <thead>
                    <tr>
                        <th>Type</th>
                        <th>Name</th>
                        <th>Location</th>
                        <th>Description</th>
                        <th>Tags</th>
                        <th>Publication Status</th>
                        <th>Created By</th>
                        <th>Created Date</th>
                        <th>Modified By</th>
                        <th>Modified Date</th>
                        <th>Published By</th>
                        <th>Published Date</th>
                    </tr>
                    </thead>
                    <tbody>            
                    {   for $file in $db//rep:Item
                        let $design         := $file
                        let $guid           := $file/rep:GUID/text()
                        let $object         := $file/rep:Entry/*
                        let $path           := db:path($file)
                        let $name           := $file/rep:Name/text()
                        let $displayName    := $file/rep:DisplayName/text()
                        let $description    := $object/*:description/text()
                        let $tags           := $design/rep:Tags/text()
                        order by $path 
                        return
                        <tr>
                            <td>{mhtml:objectWithIcon(data($file/rep:MimeType),substring-after(data($file/rep:MimeType),"+"),())}</td>
                            <td title="{$name}"><a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$displayName}</a></td>
                            <td><a href="{$pathPrefix}/{$path}" target="_blank">{$path}</a></td>
                            <td>{$description}</td>
                            <td>
                                {
                                if (empty($tags)) then ()
                                else
                                string-join(tokenize($tags,","),", ")
                                }
                            </td>
                            <td>{$design/rep:PublicationStatus/text()}</td>
                            <td>{$design/rep:CreatedBy/text()}</td>
                            <td>{$design/rep:CreationDate/text()}</td>
                            <td>{$design/rep:ModifiedBy/text()}</td>
                            <td>{$design/rep:ModificationDate/text()}</td>
                            <td>{$design/rep:PublishedBy/text()}</td>
                            <td>{$design/rep:PublicationDate/text()}</td>
                            
                        </tr>
                    }
                    </tbody>
                    </table>
                </div>
            </div> <!--END div #summary -->
            <div id="connectors">
                <h2>Connectors Summary</h2>
                <table class="display" id="connectors_table" style="margin-right:auto;margin-left:0px;width:100%;">
                <thead>
                <tr>
                    <th>Name</th>
                    <th>Location</th>
                    <th>Description</th>
                    <th>Agent Only</th>`
                    <th>Action Count</th>
                    <th>Process Objects Count</th>
                    <th>Tags</th>
                    <th>Publication Status</th>
                    <th>Created By</th>
                    <th>Modified By</th>
                    <th>Published By</th>
                </tr>
                </thead>
                <tbody>
                
                {   for $file in $connectors
                    let $design         := $file
                    let $guid           := $file/rep:GUID/text()
                    let $object         := $file/rep:Entry/*
                    let $path           := db:path($file)
                    let $name           := data($object/@name)
                    let $description    := $object/svc:description/text()
                    let $agentOnly      := data($object/@agentOnly)
                    let $countActions   := count($object/svc:actions/svc:action)
                    let $poCount        := count($object/svc:objects/hen:processObject)
                    let $tags           := $design/rep:Tags/text()
                    
                    return
                    <tr>
                        <td title="{$file/*/*:Name}"><a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$name}</a></td>
                        <td><a href="{$pathPrefix}/{$path}" target="_blank">{$path}</a></td>
                        <td>{$description}</td>
                        <td>{$agentOnly}</td>
                        <td>{$countActions}</td>
                        <td>{$poCount}</td>
                        <td>
                            {
                            if (empty($tags)) then ()
                            else
                            string-join(tokenize($tags,","),", ")
                            }
                        </td>
                        <td>
                            {$design/rep:PublicationStatus/text()}
                        </td>
                        <td>{$design/rep:CreatedBy/text()}</td>
                        <td>{$design/rep:ModifiedBy/text()}</td>
                        <td>{$design/rep:PublishedBy/text()}</td>
                    </tr>
                }
                </tbody>
                </table>
            </div>
            <div id="connections">
                <h2>Connections</h2>
                <table class="display" id="connections_table" style="margin-right:auto; margin-left:0px">
                <thead>
                <tr>
                    <th>Name</th>
                    <th>Location</th>
                    <th>Description</th>
                    <th>Agent</th>
                    <th>Agent Only</th>
                    <th>Connector</th>
                    <th>Tags</th>
                    <th>Publication Status</th>
                    <th>Created By</th>
                    <th>Modified By</th>
                    <th>Published By</th>
                </tr>
                </thead>
                <tbody>
                {   for $file in $connections
                    let $design         := $file
                    let $guid           := $file/rep:GUID/text()
                    let $object         := $file/rep:Entry/*
                    let $path           := db:path($file)
                    let $name           := data($object/@name)
                    let $description    := $object/con:description/text()
                    let $agent          := $object/con:agent/text()
                    let $agentOnly      := data($object/cnt:*/@agentOnly)
                    let $connUuid       := data($object/cnt:*/@uuid)
                    let $connName       := data($object/cnt:*/@name)
                    let $connector      := if (empty($connUuid) or empty($connName)) then () 
                                            else "TODO resolve Connector link"
                    let $connectorName  := data($connector/@name)
                    let $connectorPath  := data($object/cnt:*/@connectorPath)
                    let $connectorUri   := "TODO connector URI"
                    let $tags           := $design/rep:Tags/text()
                    
                    return
                    <tr>
                        <td><a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$name}</a></td>
                        <td><a href="{$pathPrefix}/{$path}" target="_blank">{$path}</a></td>
                        <td>{$description}</td> 
                        <td>{$agent}</td>
                        <td>{$agentOnly}</td>
                        <td>
                            {
                            if (empty($connectorUri)) then "Not Available"
                            else
                            <a href="{$connectorUri}">{$connName}</a>
                            }
                        </td>
                        <td>
                            {
                            if (empty($tags)) then ()
                            else
                            string-join(tokenize($tags,","),", ")
                            }
                        </td>
                        <td>{$design/rep:PublicationStatus/text()}</td>
                        <td>{$design/rep:CreatedBy/text()}</td>
                        <td>{$design/rep:ModifiedBy/text()}</td>
                        <td>{$design/rep:PublishedBy/text()}</td>
                    </tr>
                }
                </tbody>
                </table>
            </div> <!--END div #connections-->
            <div id="processObjects">
                <h2>Process Objects</h2>
                <table class="display" id="po_table" style="margin-right:auto;margin-left:0px;width:100%;">
                <thead>
                <tr>
                    <th>Name</th>
                    <th>Location</th>
                    <th>Description</th>
                    <th>Field Count</th>
                    <th>Tags</th>
                    <th>Created By</th>
                    <th>Modified By</th>
                </tr>
                </thead>
                <tbody>
                {   for $file in $processObjects
                    let $design         := $file
                    let $guid           := $file/rep:GUID/text()
                    let $object         := $file/rep:Entry/*
                    let $path           := db:path($file)
                    let $name           := data($object/@name)
                    let $description    := $object/hen:description/text()
                    let $fieldCount     := count($object/hen:detail/hen:field)
                    let $tags           := $design/rep:Tags/text()
                    
                    return
                    <tr>
                        <td><a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$name}</a></td>
                        <td><a href="{$pathPrefix}/{$path}" target="_blank">{$path}</a></td>
                        <td>{$description}</td>
                        <td>{$fieldCount}</td>
                        <td>
                            {
                            if (empty($tags)) then ()
                            else
                            string-join(tokenize($tags,","),", ")
                            }
                        </td>
                        <td>{$design/rep:CreatedBy/text()}</td>
                        <td>{$design/rep:ModifiedBy/text()}</td>
                    </tr>
                }
                </tbody>
                </table>
            </div> <!--END div #processObjects-->
            <div id="processes">
                <h2>Processes</h2>
                <table class="display" id="process_table" style="margin-right:auto;margin-left:0px;width:100%;">
                <thead>
                <tr>
                    <th>Name</th>
                    <th>Location</th>
                    <th>Description</th>
                    <th>Suspend On Fault</th>
                    <th>Allow Anonymous Access</th>
                    <th>Tracing Level</th>
                    <th>Allowed Roles</th>
                    <th>Agent</th>
                    <th>Tags</th>
                    <th>Input</th>
                    <th>Temp</th>
                    <th>Otput</th>
                    <th>Subprocesses</th>
                    <th>Services</th>
                    <th>Events/Catch</th>
                    <th>Events/Timer</th>
                    <th>Milestones</th>
                    <th>Assignments</th>
                    <th>Excl. Gatewyas</th>
                    <th>Parallel Gatewyas</th>
                    <th>Jump Tos</th>
                    <th>Links</th>
                    <th>Ends</th>
                    <th>Complexity Coef.</th>
                    <th>Publication Status</th>
                    <th>Created By</th>
                    <th>Modified By</th>
                    <th>Published By</th>
                </tr>
                </thead>
                <tbody>
                {   for $file in $processes
                    let $design          := $file
                    let $guid            := $file/rep:GUID/text()
                    let $object          := $file/rep:Entry/*
                    let $path            := db:path($file)
                    let $name            := data($object/@name)
                    let $description     := $object/sfd:description/text()
                    let $suspendOnFault  := data($object/sfd:deployment/@suspendOnFault)
                    let $tracingLevel    := data($object/sfd:deployment/@tracingLevel)
                    let $allowedRoles    := string-join($object/sfd:deployment/sfd:rest/sfd:allowedRoles/sfd:role/text(),",")
                    let $allowAnonymousAccess := exists($object/sfd:deployment/sfd:rest/sfd:allowAnonymousAccess)
                    let $agent           := $object/sfd:deployment/sfd:targetLocation/text()
                    let $tags            := $design/rep:Tags/text()
                    let $inCount         := count($object/sfd:input/sfd:parameter)
                    let $tempCount       := count($object/sfd:tempFields/sfd:field)
                    let $outCount        := count($object/sfd:output/sfd:field)
                    let $countSubflow    := count($object/sfd:flow//sfd:subflow)
                    let $countService    := count($object/sfd:flow//sfd:service)
                    let $countEventCatch := count($object/sfd:flow//sfd:events/sfd:catch)
                    let $countEventTimer := count($object/sfd:flow//sfd:events/sfd:timer)
                    let $countFlow       := count($object/sfd:flow//sfd:flow)
                    let $countMilestone  := count($object/sfd:flow//sfd:milestone)
                    let $countAssignment := count($object/sfd:flow//sfd:assignment)
                    let $countExclGW     := count($object/sfd:flow//sfd:container[@type="exclusive"])
                    let $countParallelGW := count($object/sfd:flow//sfd:container[@type="parallel"])
                    let $countJumpTo     := count($object/sfd:flow//sfd:jumpTo)
                    let $countLink       := count($object/sfd:flow//sfd:link)
                    let $countEnd        := count($object/sfd:flow//sfd:end)
                    let $totalCount  := $countSubflow 
                                        + $countService *100 
                                        + $countEventCatch 
                                        + $countEventTimer 
                                        + $countEnd
                                        + $countLink  
                                        + $countFlow * 100
                                        + $countMilestone 
                                        + $countAssignment 
                                        + $countExclGW * 10
                                        + $countJumpTo * 10
                    let $complexity := format-number(math:log10($totalCount),"0.00")
                    return
                    <tr>
                        <td><a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$name}</a></td>
                        <td><a href="{$pathPrefix}/{$path}" target="_blank">{$path}</a></td>
                        <td>{$description}</td> 
                        <td>{$suspendOnFault}</td>
                        <td>{$allowAnonymousAccess}</td>
                        <td>{$tracingLevel}</td>
                        <td>{if (empty($allowedRoles)) then ()
                            else
                            <div>
                                <ul>
                                    { 
                                    for $role in tokenize($allowedRoles,",")
                                    return   
                                    <li>{$role}</li>
                                    }
                                </ul>
                            </div>
                            }
                        </td>
                        <td>{$agent}</td>
                        <td>
                            {
                            if (empty($tags)) then ()
                            else
                            string-join(tokenize($tags,","),", ")
                            }
                        </td>
                        <td>{$inCount}</td>
                        <td>{$tempCount}</td>
                        <td>{$outCount}</td>
                        <td>{$countSubflow}</td>
                        <td>{$countService}</td>
                        <td>{$countEventCatch}</td>
                        <td>{$countEventTimer}</td>
                        <td>{$countMilestone}</td>
                        <td>{$countAssignment}</td>
                        <td>{$countExclGW}</td>
                        <td>{$countParallelGW}</td>
                        <td>{$countJumpTo}</td>
                        <td>{$countLink}</td>
                        <td>{$countEnd}</td>
                        <td>{$complexity}</td>
                        <td>{$design/rep:PublicationStatus/text()}</td>
                        <td>{$design/rep:CreatedBy/text()}</td>
                        <td>{$design/rep:ModifiedBy/text()}</td>
                        <td>{$design/rep:PublishedBy/text()}</td>
                    </tr>
                }
                </tbody>
                </table>
            </div> <!--END div #processes-->
            <div id="guides">
                <h2>Guides</h2>
                <table class="display" id="guides_table" style="margin-right:auto;margin-left:0px;width:100%;">
                <thead>
                <tr>
                    <th>Name</th>
                    <th>Location</th>
                    <th>Description</th>
                    <th>Allow Restart</th>
                    <th>Disable Screen Rollback</th>
                    <th>Done On End Step</th>
                    <th>Run As</th>
                    <th>Run On</th>
                    <th>Applies To</th>
                    <th>Input</th>
                    <th>Temp</th>
                    <th>Output</th>
                    <th>Screens</th>
                    <th>Ends</th>
                    <th>Services</th>
                    <th>Gateways</th>
                    <th>Jump To</th>
                    <th>Data Decisions</th>
                    <th>Assignments</th>
                    <th>Complexity Coef</th>
                    <th>Tags</th>
                    <th>Publication Status</th>
                    <th>Created By</th>
                    <th>Modified By</th>
                    <th>Published By</th>
                </tr>
                </thead>
                <tbody>
                {   for $file in $guides
                    let $design          := $file
                    let $guid            := $file/rep:GUID/text()
                    let $object          := $file/rep:Entry/*
                    let $path            := db:path($file)
                    let $name            := data($object/@name)
                    let $description     := $object/sfd:description/text()
                    let $allowRestart    := data($object/@allowRestart)
                    let $disableScreenRollback    := data($object/@disableScreenRollback)
                    let $doneOnEndStep   := data($object/@doneOnEndStep)
                    let $runAsUser       := data($object/@runAsUser)
                    let $appliesTo       := $object/sfd:appliesTo/text()
                    let $inCount         := count($object/sfd:input/sfd:parameter)
                    let $tempCount       := count($object/sfd:tempFields/sfd:field)
                    let $outCount        := count($object/sfd:output/sfd:field)
                    let $countScreen     := count($object/sfd:flow//(sfd:startScreen|sfd:screen))
                    let $countEndScreen  := count($object/sfd:flow//sfd:endScreen)
                    let $countService    := count($object/sfd:flow//sfd:service)
                    let $countGateway    := count($object/sfd:flow//sfd:empty)
                    let $countJumpTo     := count($object/sfd:flow//sfd:jumpTo)
                    let $countDataDecision := count($object/sfd:flow//sfd:dataDecision)
                    let $countassignment := count($object/sfd:flow//sfd:assignment)
                    let $runOn           := data($object/sfd:runOn/@target)
                    let $tags            := $design/rep:Tags/text()
                    let $totalCount      := $countScreen * 100 
                                            + $countEndScreen
                                            + $countService * 100
                                            + $countGateway * 10
                                            + $countDataDecision * 10
                                            + $countassignment
                                            + $inCount
                                            + $tempCount 
                                            + $outCount 
                                            
                    let $complexityCoef := format-number(math:log10($totalCount),"0.00")
                    return
                    <tr>
                        <td><a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$name}</a></td>
                        <td><a href="{$pathPrefix}/{$path}" target="_blank">{$path}</a></td>
                        <td>{$description}</td>
                        <td>{$allowRestart}</td>
                        <td>{$disableScreenRollback}</td>
                        <td>{$doneOnEndStep}</td>
                        <td>{$runAsUser}</td>
                        <td>{$runOn}</td>
                        <td>{$appliesTo}</td>
                        <td>{$inCount}</td>
                        <td>{$tempCount}</td>
                        <td>{$outCount}</td>
                        <td>{$countScreen}</td>
                        <td>{$countEndScreen}</td>
                        <td>{$countService}</td>
                        <td>{$countGateway}</td>
                        <td>{$countJumpTo}</td>
                        <td>{$countDataDecision}</td>
                        <td>{$countassignment}</td>
                        <td>{$complexityCoef}</td>
                        <td>
                            {
                            if (empty($tags)) then ()
                            else
                            string-join(tokenize($tags,","),", ")
                            }
                        </td>
                        <td>{$design/rep:PublicationStatus/text()}</td>
                        <td>{$design/rep:CreatedBy/text()}</td>
                        <td>{$design/rep:ModifiedBy/text()}</td>
                        <td>{$design/rep:PublishedBy/text()}</td>
                    </tr>
                }
                </tbody>
                </table>
            </div> <!--END div #guides-->
        </div> <!--END div #tabs-->
    </body>
)};