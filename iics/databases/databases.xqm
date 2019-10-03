module namespace iics = 'iics/database';

import module namespace html   = 'iics/html' at '../modules/html.xqm';
import module namespace mhtml  = 'iics/ipd-metafata-html' at '../modules/ipd-metadata-html.xqm';

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
  %rest:path("/iics/database")
  %output:method("html")
  %output:omit-xml-declaration("yes")
  %rest:query-param("database",    "{$database}")
function iics:start(
   $database as xs:string?
) as element(html) {
    let $error := ()
    return
    html:wrap(map { 
      'header' : ('Databases'),  
      'error'  : $error, 
      'css'    : ('https://cdn.datatables.net/v/ju-1.11.4/jq-2.2.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.css'),
      'scripts': ('https://cdn.datatables.net/v/ju-1.11.4/jq-2.2.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.js', 
                  'https://cdn.plot.ly/plotly-latest.min.js'),
      'inlineScripts' : 
      <script type="text/javascript" charset="utf-8">
        $(document).ready(function() {{
            
            $("#databases_table").DataTable({{
                jQueryUI : true,
                scrollX : true,
                scrollY : false,
                colReorder: true,
                responsive: true,
                lengthMenu : [[10, 25, 50, 100,  -1], [10, 25, 50, 100, "All"]],
                paging : true,
                dom: 'BlfrtFip',
                columnDefs: [
                    {{
                        'targets': [ 1,2,3 ],
                        'className': 'dt-body-right dt-body-nowrap'
                    }}],
                buttons: [
                    'colvis',
                    'copy',
                    {{
                        extend: 'excel',
                        filename: 'tabkle_data',
                    }},
                    'csvHtml5',
                    'print'
                ]
                }});
            
            $("div.tableWrapper").addClass("tableWrapperFitContents");
            
          }} );
      </script>
    },
    <body>
        {html:pageHeader(map {
            'h1': 'Databases'
            },
            ())}
        <div id="db_table" class="tableWrapper">
            <table class="display" id="databases_table" style="margin-right:auto;margin-left:0px">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Resources</th>
                        <th>Size</th>
                        <th>Modified Date</th>
                        <th>Path</th>
                    </tr>
                </thead>
                <tbody>       
                    {
                    for $db in db:list-details()
                        let $containsIPDData := exists(db:open($db/text())//rep:Item)
                        let $size := data($db/@size)
                        where $containsIPDData
                    return
                    <tr>
                        <td><a href="report?database={$db}" title="Open DB Report">{$db/text()}</a></td>
                        <td>{data($db/@resources)}</td>
                        <td>{prof:human(if(exists($size)) then xs:integer($size) else 0)}</td>
                        <td>{format-dateTime(xs:dateTime($db/@modified-date),"[Y0001]-[M01]-[D01] [H01]:[m01]:[s01] [ZN,*-3]")}</td>
                        <td>{data($db/@path)}</td>
                    </tr>
                    }
                </tbody>
            </table>
        </div>
    </body>)
    
};

(:~
 : Redirects to the specified action.
 : @param  $action     action to perform
 : @param  $name       database
 : @param  $resources  resources
 : @param  $backups    backups
 : @return redirection
 :)
declare
  %rest:POST
  %rest:path("/iics/database")
  %rest:form-param("action",   "{$action}")
  %rest:form-param("name",     "{$name}")
  %rest:form-param("resource", "{$resources}")
function iics:database-redirect(
  $action     as xs:string,
  $name       as xs:string,
  $resources  as xs:string*
) as element(rest:response) {
  web:redirect($action, map { 'name': $name, 'resource': $resources  })
};