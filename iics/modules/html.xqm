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
 :   <li><b>breadCrumbs</b>: Navigation Menu Items, it should be another nested map with structure 
    map{
    'label1' : 'url1',
    'label2' : 'url2'
    }</li>
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
    let $breadCrumbs  := $options?breadCrumbs

  
    return 
    <body>
      <header id="pageHeader">
        <div class="indexHeader">
            <div class="indexHeaderLeft">
                <span class="hamburgerMenu"><span class="hamburgerMenuImg hasSVG"><svg version="1.1" viewBox="0 0 16 12"
                            width="16" height="16">
                            <path class="hamburgerBar"
                                d="M15.5 1.1H.5C.2 1.1 0 .9 0 .5 0 .2.2 0 .5 0h15c.3 0 .5.2.5.5 0 .4-.2.6-.5.6zm0 5.4H.5c-.3 0-.5-.2-.5-.6 0-.3.2-.5.5-.5h15c.3 0 .5.2.5.5 0 .4-.2.6-.5.6zm0 5.4H.5c-.3 0-.5-.2-.5-.6 0-.3.2-.5.5-.5h15c.3 0 .5.2.5.5 0 .4-.2.6-.5.6z">
                            </path>
                        </svg></span></span>
                <span class="infaLogo">
                    <img src="/iics/static/icons/infa-logo.svg" class="indexHeaderImage"/>
                </span>
                <span class="breadCrumbs">IICS Reporting Tools { if (empty($breadCrumbs)) then () else for $bc in $breadCrumbs/a return <span class="breadCrumbs">» {$bc}</span>}</span>
            </div>
            <div class="indexHeaderRight">
                <div class="indexHeaderMenus">
                    <div class="indexHelpMenu" data-id="HelpMenu">
                        <a href="https://github.com/jbrazda/iics-reporting-tools/blob/master/README.md" class="breadCrumbs"><button
                            class="infaButton infaButton-toolbar-icon infaButton-dark infaButton-toolbar-icon-anim"
                            title="Help" style="min-width: 16px; min-height: 16px;">
                            <div class="infaButton-interior"><span class="infaButton-icon hasSVG"
                                    style="width: 16px; height: 16px;"><svg version="1.1" width="16" height="16"
                                        viewBox="0.569 0 7.318 13.783">
                                        <path
                                            d="M3.513 11.193a.363.363 0 0 0-.363.362v1.455a.362.362 0 1 0 .724 0v-1.455a.362.362 0 0 0-.361-.362">
                                        </path>
                                        <path
                                            d="M3.513 13.749a.738.738 0 0 1-.738-.738v-1.455a.737.737 0 0 1 1.474 0v1.455a.738.738 0 0 1-.736.738zM4.24.374C2.068.374.969 1.109.969 2.556a.362.362 0 1 0 .725 0c0-.677.289-1.454 2.545-1.454 1.547 0 2.545.856 2.545 2.182 0 1.006-1.43 1.942-1.979 2.22-.067.034-1.656.854-1.656 3.231v.364a.361.361 0 1 0 .724 0v-.364c0-1.91 1.206-2.558 1.254-2.582.099-.048 2.384-1.21 2.384-2.871C7.513 1.571 6.166.374 4.24.374">
                                        </path>
                                        <path
                                            d="M3.513 9.839a.738.738 0 0 1-.738-.736v-.365c0-2.552 1.671-3.472 1.861-3.568.58-.292 1.772-1.137 1.772-1.886 0-1.114-.832-1.807-2.17-1.807-2.17 0-2.17.729-2.17 1.079a.74.74 0 0 1-.738.739.74.74 0 0 1-.737-.739C.593 1.389 1.226 0 4.239 0c2.148 0 3.648 1.35 3.648 3.284 0 1.927-2.567 3.194-2.595 3.208-.028.016-1.043.582-1.043 2.246v.364a.737.737 0 0 1-.736.737z">
                                        </path>
                                    </svg></span></div>
                        </button>
                        </a>
                    </div>
                </div>
            </div>
        </div>
        <div class="clearer"></div>
        {$html}
      </header>
    </body>
  };
  
