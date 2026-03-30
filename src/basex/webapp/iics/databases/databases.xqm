module namespace iics = 'iics/database';

import module namespace html   = 'iics/html' at '../modules/html.xqm';
import module namespace mhtml  = 'iics/ipd-metadata-html' at '../modules/ipd-metadata-html.xqm';
import module namespace cdi    = 'iics/cdi-extract' at '../modules/cdi-extract.xqm';

(:ICAI namespaces:)
declare namespace sfd = "http://schemas.active-endpoints.com/appmodules/screenflow/2010/10/avosScreenflow.xsd";
declare namespace svc = "http://schemas.informatica.com/socrates/data-services/2014/05/business-connector-model.xsd";
declare namespace con = "http://schemas.informatica.com/socrates/data-services/2014/04/avosConnections.xsd";
declare namespace cnt = "http://schemas.informatica.com/appmodules/screenflow/2014/04/avosConnectors.xsd";
declare namespace hen = "http://schemas.active-endpoints.com/appmodules/screenflow/2011/06/avosHostEnvironment.xsd";
declare namespace rep = "http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd";

(:basex namespaces:)
declare namespace output  = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace math    = "http://www.w3.org/2005/xpath-functions/math";
declare namespace db      = "http://basex.org/modules/db";
declare namespace rest    = "http://exquery.org/ns/restxq";
declare namespace archive = "http://basex.org/modules/archive";
declare namespace file    = "http://expath.org/ns/file";
declare namespace jobs    = "http://basex.org/modules/jobs";

(:~
 : Shows the database list page with an upload form.
 : @param  $database  optional database name (unused, kept for backwards compat)
 : @param  $message   optional status message: 'created' or 'replaced'
 : @return page
 :)
declare
  %rest:path("/iics/database")
  %output:method("html")
  %output:omit-xml-declaration("yes")
  %rest:query-param("database", "{$database}")
  %rest:query-param("message",  "{$message}")
function iics:start(
   $database as xs:string?,
   $message  as xs:string?
) as element(html) {
    html:wrap(map { 
      'header' : ('Databases'),  
      'css'    : ('https://cdn.datatables.net/v/ju-1.11.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.css'),
      'scripts': ('https://cdn.datatables.net/v/ju-1.11.4/jszip-3.1.3/dt-1.10.15/b-1.3.1/b-colvis-1.3.1/b-html5-1.3.1/b-print-1.3.1/r-2.1.1/se-1.2.2/datatables.min.js',
                  'https://cdn.plot.ly/plotly-latest.min.js')
    },
    <body>
        {html:pageHeader(map {
            'headerActions':
            <div class="indexHeaderAction">
                <button id="btn-upload-package" class="infaButton infaButton-1 ui-header-button"
                        title="Upload IICS Export Package">&#8593;&#160;Upload Package</button>
            </div>
        }, ())}
        {
          if (exists($message) and $message != '') then
            <div class="reportSection" style="background:#dff0d8;border:1px solid #d6e9c6;border-radius:4px;padding:10px 16px;color:#3c763d">
              {if ($message = 'created') then 'Database created successfully.'
               else if ($message = 'replaced') then 'Database replaced successfully.'
               else $message}
            </div>
          else ()
        }
        <div id="upload-dialog" title="Upload IICS Export Package">
            <form id="upload-form" method="POST" action="/iics/database/upload" enctype="multipart/form-data">
                <p>
                    <label for="uploadFile">Package ZIP file:</label><br/>
                    <input type="file" name="file" id="uploadFile" accept=".zip" required="required" style="width:100%;margin-top:4px"/>
                </p>
                <input type="hidden" name="dbname" id="uploadDbName"/>
            </form>
        </div>
        <div class="reportSection">
            <p>Following is a list of available databases. See the service documentation for how to import an IICS Exported Package.
            <a href="https://github.com/jbrazda/iics-reporting-tools#create-exported-objects-database">How to Create DB</a></p>
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
        </div>
    </body>)
    
};

(:~
 : Redirects to the specified action.
 : @param  $action     action to perform
 : @param  $name       database
 : @param  $resources  resources
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

(:~
 : Handles a ZIP package upload. Creates a new database from the uploaded file, or redirects
 : to a confirmation page if a database with the same name already exists.
 : BaseX RESTXQ delivers multipart file uploads as a map { filename: base64content }.
 : @param  $file    uploaded file map (key = filename, value = base64Binary content)
 : @param  $dbname  target database name (derived from filename by the upload form JS)
 :)
declare
  %rest:POST
  %rest:path("/iics/database/upload")
  %rest:form-param("file",   "{$file}")
  %rest:form-param("dbname", "{$dbname}")
  %updating
function iics:upload(
  $file    as map(*)?,
  $dbname  as xs:string?
) {
  let $filename := if (exists($file)) then map:keys($file)[1] else ''
  let $zip      := if ($filename != '') then xs:base64Binary($file($filename)) else ()
  (: Fall back to deriving name from filename if JS did not populate the hidden field :)
  let $name     := let $n := normalize-space(($dbname, '')[1])
                   return if ($n != '') then $n
                          else replace(replace($filename, '\.zip$', '', 'i'), '[^a-zA-Z0-9_\-]', '_')
  return
  if (empty($zip) or string-length($name) = 0) then
    update:output(iics:upload-error('No file or database name provided. Please select a ZIP file and try again.'))
  else if (db:exists($name)) then
    (: Save to temp and redirect to confirmation page :)
    let $tmpfile := file:temp-dir() || '_iics_upload_' || $name || '.zip'
    return (
      file:write-binary($tmpfile, $zip),
      update:output(web:redirect('/iics/database/upload/confirm', map { 'name': $name, 'tmpfile': $tmpfile }))
    )
  else (
    (: Write ZIP to temp file, create database from XML, then schedule CDI extraction :)
    let $tmpfile := file:temp-dir() || '_iics_upload_' || $name || '.zip'
    return (
      file:write-binary($tmpfile, $zip),
      iics:create-db-from-zip($name, $zip),
      update:output(
        let $_ := jobs:eval(
          "import module namespace cdi = 'iics/cdi-extract' at '../modules/cdi-extract.xqm';" ||
          " cdi:extract-from-package($db, $zip)",
          map { 'db': $name, 'zip': $tmpfile },
          map { 'base-uri': file:base-dir() }
        )
        return web:redirect('/iics/report', map { 'database': $name })
      )
    )
  )
};

(:~
 : Displays a confirmation page when the target database already exists.
 : @param  $name     database name
 : @param  $tmpfile  path to the temporarily stored ZIP file
 : @return confirmation page
 :)
declare
  %rest:GET
  %rest:path("/iics/database/upload/confirm")
  %rest:query-param("name",    "{$name}")
  %rest:query-param("tmpfile", "{$tmpfile}")
  %output:method("html")
function iics:upload-confirm(
  $name    as xs:string?,
  $tmpfile as xs:string?
) as element(html) {
  if (empty($name) or string-length(normalize-space($name)) = 0
      or empty($tmpfile) or not(file:exists($tmpfile))) then
    iics:upload-error('Upload session has expired or the temporary file is missing. Please re-upload the package.')
  else
    html:wrap(map { 'header': ('Databases', 'Confirm Replace') },
      <body>
        {html:pageHeader(map {}, ())}
        <div id="confirm-dialog" title="Replace Existing Database?">
          <p>A database named <strong>{$name}</strong> already exists.</p>
          <p>Do you want to replace it with the newly uploaded package? This action cannot be undone.</p>
          <form id="confirm-form" method="POST" action="/iics/database/upload/confirm">
            <input type="hidden" name="dbname"  value="{$name}"/>
            <input type="hidden" name="tmpfile" value="{$tmpfile}"/>
          </form>
        </div>
      </body>)
};

(:~
 : Performs the confirmed overwrite: drops the existing database, creates a new one from the
 : stored temporary ZIP file, then cleans up the temp file.
 : @param  $dbname   database name to replace
 : @param  $tmpfile  path to the temporarily stored ZIP file
 :)
declare
  %rest:POST
  %rest:path("/iics/database/upload/confirm")
  %rest:form-param("dbname",  "{$dbname}")
  %rest:form-param("tmpfile", "{$tmpfile}")
  %updating
function iics:upload-overwrite(
  $dbname  as xs:string?,
  $tmpfile as xs:string?
) {
  let $name := normalize-space(($dbname, '')[1])
  return
  if (string-length($name) = 0 or empty($tmpfile) or not(file:exists($tmpfile))) then
    update:output(iics:upload-error('Upload session has expired or the temporary file is missing. Please re-upload the package.'))
  else
    let $zip := file:read-binary($tmpfile)
    return (
      db:drop($name),
      iics:create-db-from-zip($name, $zip),
      update:output(
        let $_ := jobs:eval(
          "import module namespace cdi = 'iics/cdi-extract' at '../modules/cdi-extract.xqm';" ||
          " cdi:extract-from-package($db, $zip)",
          map { 'db': $name, 'zip': $tmpfile },
          map { 'base-uri': file:base-dir() }
        )
        return web:redirect('/iics/report', map { 'database': $name })
      )
    )
};

(:~
 : Creates a BaseX database from the XML entries of a ZIP archive.
 :
 : Only XML documents are loaded in this transaction. Top-level JSON and nested ZIP
 : content are processed separately by cdi:extract-from-package() running as a
 : background job after this transaction completes (db:create and db:store cannot
 : coexist in the same updating transaction - db:store requires the DB to already exist).
 :
 : @param  $dbname  target database name
 : @param  $zip     top-level ZIP archive as base64Binary
 :)
declare %private %updating function iics:create-db-from-zip(
  $dbname as xs:string,
  $zip    as xs:base64Binary
) {
  let $allEntries := archive:entries($zip)/string()
  let $xmlEntries := $allEntries[ends-with(lower-case(.), '.xml')
                                  and not(starts-with(., '__MACOSX/'))]
  let $xmlDocs    := archive:extract-text($zip, $xmlEntries)
  return db:create($dbname, $xmlDocs, $xmlEntries)
};

(:~
 : Returns an error page for upload failures.
 : @param  $message  human-readable error description
 : @return error page
 :)
declare %private function iics:upload-error(
  $message as xs:string
) as element(html) {
  html:wrap(map { 'header': ('Databases', 'Upload Error') },
    <body>
      {html:pageHeader(map {}, ())}
      <div class="reportSection" style="background:#f2dede;border:1px solid #ebccd1;border-radius:4px;padding:10px 16px;color:#a94442">
        <strong>Upload failed:</strong>&#160;{$message}
      </div>
      <div class="reportSection">
        <a href="/iics/database">&#8592; Back to Databases</a>
      </div>
    </body>)
};