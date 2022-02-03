module namespace iics = 'iics/design';

import module namespace html   = 'iics/html' at 'modules/html.xqm';
import module namespace mhtml  = 'iics/ipd-metadata-html' at 'modules/ipd-metadata-html.xqm';
import module namespace imf    = 'iics/imf' at 'modules/ipd-metadata.xqm';
import module namespace functx = 'http://www.functx.com';



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
  %rest:path("/iics/design")
  %output:method("html")
  %output:omit-xml-declaration("yes")
  %rest:query-param("database", "{$database}")
  %rest:query-param("guid",     "{$guid}")
function iics:render(
   $guid as xs:string,
   $database as xs:string
) as element(html) {
    let $error          := ()
    let $db             := db:open($database)
    let $pathPrefix     := concat("/rest/",$database)
    let $design         := imf:getDesignByGuid($db,$guid)
    let $name           := $design/rep:Name/text()
    let $displayName    := $design/rep:DisplayName/text()
    let $designType     := $mhtml:IPD_TYPES($design/rep:MimeType/text())
    
    let $designDependencies := imf:getObjectDependencies($db,$design)
    let $designImpact       := imf:getObjectImpact($db,$design,true())
    return html:wrap(map { 
      'header' : ($database,$displayName),  
      'error'  : $error, 
      'css'    : ('https://cdn.datatables.net/v/ju-1.11.4/jq-2.2.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.css'),
      'scripts': ('https://cdn.datatables.net/v/ju-1.11.4/jq-2.2.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.js', 
                  'https://cdn.plot.ly/plotly-latest.min.js'),
      'inlineScripts' : 
      <script type="text/javascript" charset="utf-8">
        $(document).ready(function() {{
            $("#design-tabs").tabs();
            $("#tabs").tabs();
            $("table.display" ).DataTable({{
                jQueryUI : true,
                scrollX : true,
                scrollY : false,
                colReorder: true,
                responsive: true,
                width: 'fit-content',
                lengthMenu : [[10, 25, 50, 100,  -1], [10, 25, 50, 100, "All"]],
                paging : true,
                dom: 'BlfrtFip',
                buttons: [
                    'colvis',
                    'copy',
                    {{
                        extend: 'excel',
                        filename: '{$displayName}'
                    }},
                    'csvHtml5',
                    'print'
                ]
                }});
          }} );
      </script>
    },
    <body>
        {html:pageHeader(map { 
                            'breadCrumbs': <breadCrumbs> 
                                <a href="/iics/database">Databases</a>
                                <a href="{concat("/iics/report?database=",$database)}">{$database}</a>
                                <a href="{concat("/iics/design?database=",$database,"&amp;guid=",$guid)}">{$displayName}</a>
                                </breadCrumbs>
                            },())}
        {  mhtml:DesigFileMetadata($design[1],$pathPrefix) }
        <div id="tabs">
            <ul>
                <li><a href="#dependencies">Dependencies</a></li>
                <li><a href="#impact">Impact Analysis</a></li>
                <li><a href="#deptree">Dependency Tree</a></li>
            </ul>
            <div id="dependencies" style="margin-right:auto;margin-left:0px">
                <h2>Dependencies</h2>
                {mhtml:ObjectDependencies($designDependencies,$pathPrefix)}
            </div> <!--END div #dependencies -->
            <div id="impact" style="margin-right:auto;margin-left:0px">
                <h2>Impact Analysis</h2>
                <div>
                    <ul class="tree" style="padding-left: 25px;">
                        {mhtml:objectWithIcon(data($design/rep:MimeType),$displayName,())}
                        {mhtml:DependencyTree($designImpact,$pathPrefix)}
                    </ul>
                    {mhtml:ObjectusedBy($designImpact,$pathPrefix)}
                </div>
            </div> <!--END div #impact -->
            <div id="deptree" style="margin-right:auto;margin-left:0px">
                <h2>Dependency Data</h2>
                <div style="padding-left: 15px;">
                    <ul class="tree" style="padding-left: 25px;">
                        {mhtml:objectWithIcon(data($design/rep:MimeType),$displayName,())}
                        {mhtml:DependencyTree($designDependencies,$pathPrefix)}
                    </ul>
                </div>
            </div> <!--END div #deptree -->
        </div> <!--END div #tabs-->
    </body>
    )
};