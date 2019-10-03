(:~
 : Provides HTML components.
 :
 : @author Jaroslav Brazda 2019, MIT License
 :)
module namespace html = 'iics/html';

import module namespace util = 'iics/util' at 'util.xqm';

(: Number formats. :)
declare variable $html:NUMBER := ('decimal', 'number', 'bytes');


(:~
 : Renders page with a specific Headers, Includes, Stylesheets, etc.
 : The following options can be specified:
 : <ul>
 :   <li><b>header</b>: page headers</li>
 :   <li><b>error</b>: error string</li>
 :   <li><b>css</b>: CSS files</li>
 :   <li><b>scripts</b>: JavaScript files</li>
 :   <li><b>inlineScripts</b>: Inline Page Scripts </li>
 : </ul>
 : @param  $options  options
 : @param  $body     any html elements
 : @return page
 :)
declare 
  function html:wrap(
  $options  as map(*),
  $innerhtml     as element(*)*
) as element(html) {
    let $header := head($options?header) ! util:capitalize(.)
    return 
    <html>
        <head>
        <meta charset="utf-8"/>
        <title>IICS{ ($header, tail($options?header)) ! (' » ' || .) }</title>
        <meta name="description" content="IICS Reporting Tool"/>
        <meta name="author" content="Jaroslav Brazda 2019, MIT License"/>
        <link rel="stylesheet" type="text/css" href="static/style.css"/>
        { $options?css ! <link rel="stylesheet" type="text/css" href="{ . }"/> }
        <script type="text/javascript" src="static/js.js"/>
        { $options?scripts ! <script type="text/javascript" src="{ . }"/> }
        { $options?inlineScripts ! . }
        </head>
        <body>{$innerhtml}</body>
    </html>
};

(:~ Writes Common Page header section 
 :  <ul>
 :   <li><b>h1</b>: Page Main Title</li>
 :   <li><b>h2</b>: Page Sub Title</li>
 :   <li><b>html</b>: Custom html section within the Header div container</li>
 : </ul>
 : @param  $options  options
 : @param  $html     any html content
 : @return html section
 :)
declare 
  function html:pageHeader(
    $options as map(*),
    $html as node()*
  ) as node()* {
    <div class="reportsection">
      <img src="https://www.informatica.com/content/dam/informatica-com/global/informatica-logo.png" style="float:right" />
      {$options?h1 ! <h1>{.}</h1>}
      {$options?h2 ! <h2>{.}</h2>}
      {$html}
    </div>
  };
  




