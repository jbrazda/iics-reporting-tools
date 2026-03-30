(:~
 : Standalone XQuery job script for CDI asset extraction.
 :
 : Processes an IICS export package ZIP file to index CDI assets into a BaseX database.
 : This is the standalone equivalent of cdi-extract.xqm, written as a main module to
 : work around a BaseX 12 limitation where imported %updating functions called via
 : job:eval do not reliably persist their database writes.
 :
 : Required external bindings (passed via job:eval bindings map):
 :   $db  - target database name (must already exist)
 :   $zip - filesystem path to the package ZIP file (temp file from upload)
 :
 : This file is loaded via file:read-text() and passed as an inline query to job:eval
 : from databases.xqm. After extraction completes, it chains a cache build job.
 :)
declare namespace archive = "http://basex.org/modules/archive";
declare namespace file    = "http://expath.org/ns/file";
declare namespace convert = "http://basex.org/modules/convert";
declare namespace job     = "http://basex.org/modules/job";

declare variable $db  external;
declare variable $zip external;

(:~
 : Extracts JSON and XML entries from a single nested ZIP archive and stores them
 : into the database at paths derived from the ZIP entry path.
 :)
declare %updating function local:index-nested-zip(
  $dbname  as xs:string,
  $zipPath as xs:string,
  $zipBin  as xs:base64Binary
) {
  let $basePath    := replace($zipPath, '\.zip$', '', 'i') || '/'
  let $entries     := archive:entries($zipBin)/string()
  let $textEntries := $entries[
    (ends-with(lower-case(.), '.xml') or ends-with(lower-case(.), '.json'))
    and not(starts-with(., '__MACOSX/'))
  ]
  for $entry in $textEntries
    let $content := archive:extract-text($zipBin, ($entry))
    return
      if (ends-with(lower-case($entry), '.json')) then
        db:put-binary($dbname, convert:string-to-base64($content, 'UTF-8'), $basePath || $entry)
      else
        db:add($dbname, fn:parse-xml($content), $basePath || $entry)
};

(:~
 : Extracts and indexes all CDI content from an IICS export package ZIP file.
 :)
declare %updating function local:extract-from-package(
  $dbname  as xs:string,
  $zipPath as xs:string
) {
  let $zipBin   := file:read-binary($zipPath)
  let $all      := archive:entries($zipBin)/string()
  let $topJson  := $all[ends-with(lower-case(.), '.json')
                        and not(starts-with(., '__MACOSX/'))]
  let $nested   := $all[ends-with(lower-case(.), '.zip')
                        and not(starts-with(., '__MACOSX/'))]
  return (
    (: Index top-level JSON metadata files :)
    for $j in $topJson
      let $content := archive:extract-text($zipBin, ($j))
      return db:put-binary($dbname, convert:string-to-base64($content, 'UTF-8'), $j)
    ,
    (: Extract and index each nested ZIP :)
    for $z in $nested
      let $bin := archive:extract-binary($zipBin, ($z))
      return local:index-nested-zip($dbname, $z, $bin)
    ,
    (: Remove the temp file :)
    file:delete($zipPath)
    ,
    (: Chain a cache build job - runs after this transaction completes.
       file:base-dir() resolves to the modules/ directory (set via job:eval base-uri). :)
    update:output(
      job:eval(
        file:read-text(file:base-dir() || 'cache-build-job.xq'),
        map { 'db': $dbname },
        map { 'base-uri': file:base-dir() }
      )
    )
  )
};

local:extract-from-package($db, $zip)
