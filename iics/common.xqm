(:~
 : Common RESTXQ access points.
 :
 : @author Jaroslav Brazda, 2019, MIT License
 :)
module namespace iics = 'iics/common';

import module namespace Request = 'http://exquery.org/ns/request';
import module namespace html = 'iics/html' at 'modules/html.xqm';

(:~
 : Redirects to the start page.
 : @return redirection
 :)
declare
  %rest:path("/iics")
function iics:redirect(
) as element(rest:response) {
  web:redirect("/iics/database")
};

(:~
 : Returns a file.
 : @param  $file  file or unknown path
 : @return rest binary data
 :)
declare
  %rest:path("/iics/static/{$file=.+}")
  %perm:allow("all")
function iics:file(
  $file  as xs:string
) as item()+ {
  let $path := file:base-dir() || 'static/' || $file
  return (
    web:response-header(
      map { 'media-type': web:content-type($path) },
      map { 'Cache-Control': 'max-age=3600,public', 'Content-Length': file:size($path) }
    ),
    file:read-binary($path)
  )
};

(:~
 : Shows a "page not found" error.
 : @param  $path  path to unknown page
 : @return page
 :)
declare
  %rest:path("/iics/{$path}")
  %output:method("html")
function iics:unknown(
  $path  as xs:string
) as element(html) {
  html:wrap(map {},
    <body>
        {html:pageHeader( map {
            'h1': "Page Not Found"},())}
        <div class="reportSection">
          <ul>
            <li>Resource: iics/{ $path }</li>
            <li>Method: { Request:method() }</li>
          </ul>
        </div>
    </body>
  )
};
