(:~
 : CDI asset extraction module.
 :
 : Processes an uploaded IICS export package (ZIP file on the filesystem) to index
 : CDI (Cloud Data Integration) assets into an existing BaseX database.
 :
 : CDI assets are stored as nested ZIP archives within the top-level package ZIP.
 : Known nested ZIP types and the JSON files they contain:
 :
 :   .DTEMPLATE.zip  -> mappingTemplate.json  (CDI Mapping Template)
 :   .MTT.zip        -> mtTask.json            (CDI Mapping Task)
 :   .Connection.zip -> connection.json        (CDI Connection)
 :   .MAPPLET.zip    -> mappingTemplate.json   (CDI Mapplet)
 :
 : The top-level ZIP also contains useful JSON metadata:
 :
 :   exportMetadata.v2.json  - maps objectGuid (federatedId) to name and type
 :   *.Folder.json           - folder structure metadata
 :
 : JSON files are stored as binary resources (via db:store) so that json:parse()
 : can reliably retrieve and parse them later.
 :
 : This module is designed to be invoked as a BaseX background job via jobs:eval()
 : AFTER the database has been created by iics:create-db-from-zip(). The db:create
 : and db:store operations cannot share the same updating transaction.
 :
 : @author Jaroslav Brazda, 2024, MIT License
 :)
module namespace cdi = 'iics/cdi-extract';

declare namespace db      = "http://basex.org/modules/db";
declare namespace archive = "http://basex.org/modules/archive";
declare namespace file    = "http://expath.org/ns/file";
declare namespace convert = "http://basex.org/modules/convert";

(:~
 : Extracts JSON and XML entries from a single nested ZIP archive and indexes them
 : into the database at paths derived from the ZIP entry path.
 :
 : Binary files (e.g. .bin) and non-text files are skipped. JSON is stored as binary
 : (via db:store) to preserve the raw text for json:parse(). XML is stored as a
 : parsed document node (via db:add).
 :
 : Example: nested ZIP at "Explore/DI/m_Foo.DTEMPLATE.zip" produces:
 :          "Explore/DI/m_Foo.DTEMPLATE/mappingTemplate.json"
 :          "Explore/DI/m_Foo.DTEMPLATE/fileRecord.json"
 :
 : @param  $dbname   target database name (must already exist)
 : @param  $zipPath  path of the nested ZIP entry within the package (for deriving base path)
 : @param  $zip      ZIP archive content as base64Binary
 :)
declare %updating function cdi:index-nested-zip(
  $dbname  as xs:string,
  $zipPath as xs:string,
  $zip     as xs:base64Binary
) {
  let $basePath    := replace($zipPath, '\.zip$', '', 'i') || '/'
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
 : Extracts and indexes all CDI content from an IICS export package ZIP file.
 :
 : Processes:
 :  - Top-level JSON files (exportMetadata.v2.json, *.Folder.json) stored as binary
 :  - Nested ZIP files (.DTEMPLATE.zip, .MTT.zip, .Connection.zip, etc.) expanded
 :    via cdi:index-nested-zip()
 :
 : Deletes the temp ZIP file when done.
 :
 : This function runs as a BaseX background job after the database has been created
 : by iics:create-db-from-zip() in a prior transaction.
 :
 : @param  $dbname   target database name (must already exist)
 : @param  $zipPath  filesystem path to the package ZIP file (temp file from upload)
 :)
declare %updating function cdi:extract-from-package(
  $dbname  as xs:string,
  $zipPath as xs:string
) {
  let $zip      := file:read-binary($zipPath)
  let $all      := archive:entries($zip)/string()
  let $topJson  := $all[ends-with(lower-case(.), '.json')
                        and not(starts-with(., '__MACOSX/'))]
  let $nested   := $all[ends-with(lower-case(.), '.zip')
                        and not(starts-with(., '__MACOSX/'))]
  return (
    (: Index top-level JSON metadata files :)
    for $j in $topJson
      let $content := archive:extract-text($zip, ($j))
      return db:store($dbname, $j, convert:string-to-base64($content, 'UTF-8'))
    ,
    (: Extract and index each nested ZIP :)
    for $z in $nested
      let $bin := archive:extract-binary($zip, ($z))
      return cdi:index-nested-zip($dbname, $z, $bin)
    ,
    (: Remove the temp file :)
    file:delete($zipPath)
  )
};

