(:~
 : CDI asset extraction module.
 :
 : Processes nested ZIP files found inside an IICS export package. CDI (Cloud Data
 : Integration) assets — Mappings, Mapping Tasks, Taskflows — are exported as nested ZIP
 : archives containing JSON (and occasionally XML) metadata files.
 :
 : After the top-level package ZIP is loaded into a BaseX database, call
 : cdi:process-nested-zips() to extract all nested ZIPs and index their contents at
 : paths such as:
 :
 :   Explore/CDI/MP_SomeMapping/mapping.json
 :   Explore/CDI/MT_SomeTask/mappingtask.json
 :   Explore/CDI/TF_SomeFlow/taskflow.json
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace cdi = 'iics/cdi-extract';

declare namespace db      = "http://basex.org/modules/db";
declare namespace archive = "http://basex.org/modules/archive";
declare namespace file    = "http://expath.org/ns/file";
declare namespace convert = "http://basex.org/modules/convert";

(:~
 : Extracts text (JSON/XML) entries from a single nested ZIP archive and indexes them into
 : the database at paths derived from the ZIP path.
 :
 : Example: a nested ZIP stored at "Explore/CDI/MP_SomeMapping.zip" produces documents at
 :          "Explore/CDI/MP_SomeMapping/{entry-name}"
 :
 : @param  $dbname   target database name
 : @param  $zipPath  path of the nested ZIP within the database (used to derive base path)
 : @param  $zip      ZIP archive content as base64Binary
 :)
declare %updating function cdi:index-nested-zip(
  $dbname  as xs:string,
  $zipPath as xs:string,
  $zip     as xs:base64Binary
) {
  let $basePath    := replace($zipPath, '(?i)\.zip$', '') || '/'
  let $entries     := archive:entries($zip)/string()
  let $textEntries := $entries[
    (ends-with(lower-case(.), '.xml') or ends-with(lower-case(.), '.json'))
    and not(starts-with(., '__MACOSX/'))
  ]
  for $entry in $textEntries
    let $content := archive:extract-text($zip, ($entry))
    return
      if (ends-with(lower-case($entry), '.json')) then
        (: JSON stored as binary so json:parse() can read it back cleanly :)
        db:store($dbname, $basePath || $entry, convert:string-to-base64($content, 'UTF-8'))
      else
        (: XML stored as a parsed document node :)
        db:add($dbname, fn:parse-xml($content), $basePath || $entry)
};

(:~
 : Scans a database for binary ZIP documents previously stored by the upload process,
 : calls cdi:index-nested-zip for each one, then removes the raw binary.
 :
 : This function is designed to be invoked as a BaseX background job via jobs:eval().
 :
 : @param  $dbname  target database name
 :)
declare %updating function cdi:process-nested-zips($dbname as xs:string) {
  for $path in db:list-details($dbname)[@raw = 'true']
                [ends-with(lower-case(text()), '.zip')]/text()
    let $bin := db:retrieve($dbname, $path)
    return (
      cdi:index-nested-zip($dbname, $path, $bin),
      db:delete($dbname, $path)
    )
};
