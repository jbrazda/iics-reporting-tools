(:~
: This module provides utility functions to generate Design Metadata HTML
: 
: @author jbrazda
: @since Sep 2019
: @version 1.0
:)
module namespace mhtml = 'iics/ipd-metafata-html';

import module namespace imf  = 'iics/imf' at 'ipd-metadata.xqm';
import module namespace util = 'iics/util' at 'util.xqm';


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


declare variable $mhtml:IPD_TYPES := 
    map { 
        "application/xml+processobject": "Process Object",
        "application/xml+connection": "Connection",
        "application/xml+screenflow": "Guide",
        "application/xml+process": "Process",
        "application/xml+businesssconnector": "Service Connector",
        "application/xml+taskflow": "Task Flow"
        };

declare variable $mhtml:IPD_TUPS_TO_CLASS := 
    map { 
        "application/xml+processobject": "processObject",
        "application/xml+connection": "connection",
        "application/xml+screenflow": "guide",
        "application/xml+process": "process",
        "application/xml+businesssconnector": "connector",
        "application/xml+taskflow": "taskflow"
        };


(:~ map reference type to sprite class
:)
declare variable $mhtml:REF_TYPE_CLASS := 
    map {
        "Connection": "connection",
        "Connection:ProcessObject": "connection",
        "Connection:Service": "connection",
        "Connector": "connector",
        "objectlist": "processObject",
        "Process": "process",
        "reference": "processObject",
        "Service": "process",
        "Guide": "guide",
        "Task Flow": "taskflow"
        };

declare variable $mhtml:URL_REST_PREFIX := "/rest";

(:~
 : Renders Dependency tree as Dependecy/Impact report structure
 : such as
 : <dependencies object="Setup_Logging_DB" guid="akOVKXc0aE7lAct0X7uEMo">
 :  <dependency objectName="Setup Logging DB" referenceFrom="Setup_Logging_DB" referenceTo="SP-Setup-Logging-DB" fromGuid="akOVKXc0aE7lAct0X7uEMo" toGuid="jSu7p8fQuE8dQDuX3vRk6v" referenceType="Process" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/Logging/Setup/SP-Setup-Logging-DB.PROCESS.xml">
 :    <dependency objectName="DataAccessService" referenceFrom="SP-Setup-Logging-DB" referenceTo="DataAccessService:tMultiResponse" fromGuid="jSu7p8fQuE8dQDuX3vRk6v" toGuid="jhXRGp8HGy8fOjJy57yhy1" referenceType="Connection:ProcessObject" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_CONNECTION.xml"/>
 :    <dependency objectName="DataAccessService" referenceFrom="SP-Setup-Logging-DB" referenceTo="DataAccessService:tMultiDataAccessRequest" fromGuid="jSu7p8fQuE8dQDuX3vRk6v" toGuid="jhXRGp8HGy8fOjJy57yhy1" referenceType="Connection:ProcessObject" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_CONNECTION.xml"/>
 :    <dependency objectName="SP-Setup-Logging-DB" referenceFrom="SP-Setup-Logging-DB" referenceTo="DataAccessService" fromGuid="jSu7p8fQuE8dQDuX3vRk6v" toGuid="jhXRGp8HGy8fOjJy57yhy1" referenceType="Connection" connectorType="businessConnector" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_CONNECTION.xml">
 :      <dependency objectName="DataAccessService" referenceFrom="DataAccessService" referenceTo="DataAccessService" fromGuid="jhXRGp8HGy8fOjJy57yhy1" toGuid="cZ66760oF8pjwt5OEx7AY1" referenceType="Connector" connectorType="businessConnector" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_SERVICE_CONNECTOR.xml" uuid="93d7509e-96fb-4872-b8c1-41f382c1811f"/>
 :    </dependency>
 :    <dependency objectName="execMultiSQL" referenceFrom="jSu7p8fQuE8dQDuX3vRk6v" referenceTo="execMultiSQL" fromGuid="SP-Setup-Logging-DB" toGuid="" referenceType="Service" docUri="">
 :      <info>This Service reference is either System Service or Connection Service</info>
 :    </dependency>
 :  </dependency>
 : </dependencies>
 : @param $guid as xs:string? IICS internal GUID for the object
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @return empty set if file is not found in the repository or a document Instance of design with metadata
:)
declare function mhtml:DependencyTree (
    $node as node()*,
    $pathPrefix as xs:string?
) as item()* {  
    let $children := for $child in $node/*
            return
            mhtml:DepenencyTreeNodeLabel($child,$pathPrefix)
    let $html := if (empty($children)) then () else 
        <ul>
            { $children }
        </ul>
    return
    $html
};



(:~
 : Renders Dependency tree as Dependecy/Impact report structure
 : 
 : @param $node as xs:string? IICS internal GUID for the object
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
 :)
declare function mhtml:DepenencyTreeNodeLabel (
    $node as node()*,
    $pathPrefix as xs:string?
) as item()*{
    typeswitch ($node)
    case element(dependency) return mhtml:DepenencyLabel($node,$pathPrefix)
    case element(usedBy) return mhtml:usedByLabel($node,$pathPrefix)
    default return ()
};


(:~
 : Renders Dependency tree as Dependecy/Impact report structure
 : Dependency Example
 :  <dependency 
 :     objectName="DataAccessService" 
 :     referenceFrom="DataAccessService" 
 :     referenceTo="DataAccessService" 
 :     fromGuid="jhXRGp8HGy8fOjJy57yhy1" 
 :     toGuid="cZ66760oF8pjwt5OEx7AY1" 
 :     referenceType="Connector" 
 :     connectorType="businessConnector" 
 :     docUri="Explore/DAS/DataAccessService.AI_SERVICE_CONNECTOR.xml" uuid="93d7509e-96fb-4872-b8c1-41f382c1811f"/>
 : @param $node as xs:string? IICS internal GUID for the object
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
 :)
declare function mhtml:DepenencyLabel (
    $node as node()*,
    $pathPrefix as xs:string?
) as item()*{
    let $name := data($node/@objectName)
    let $referenceTo   := data($node/@referenceTo)
    let $referenceType := data($node/@referenceType)
    let $label := switch ($referenceType)
                 case "Connector" return data($node/@connectorType)
                 default return $referenceType
    let $class := $mhtml:REF_TYPE_CLASS($referenceType)
    let $url  := data($node/@docUri)
    let $html := <li>
                    {
                        if (empty($url) or string($url) = '') then <span class="icon {$class}">{$referenceTo} [{$label}]</span>
                        else
                        <a class="icon {$class}" href="{$pathPrefix}/{$url}">{$referenceTo} [{$label}]</a> 
                    }
                    {mhtml:DependencyTree($node,$pathPrefix)}
                </li>
    return
    $html
};



(:~
 : Renders Impact used by label from usedBy Element with a reference to an object
 :
 : <code>&lt;usedBy displayName="Logging Framework Configuration" 
 :   name="Logging_Framework_Configuration" 
 :   guid="121jjjlqAKNhxs9emgKOWk" 
 :   dependsOn="Setup_Logging_DB" 
 :   dependsOndisplayName="Setup Logging DB" 
 :   dependsOnGuid="akOVKXc0aE7lAct0X7uEMo" 
 :   referenceType="subflow" 
 :   designType="application/xml+connection"
 :   docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/Logging/Logging Framework Configuration.GUIDE.xml"/&gt;
 :   </code>
 :   
 : @param $node as xs:string? IICS internal GUID for the object
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
 :)
declare function mhtml:usedByLabel (
    $node as node()*,
    $pathPrefix as xs:string?
) as item()*{
    let $name := data($node/@name)
    let $referenceType := data($node/@referenceType)
    let $class := $mhtml:IPD_TUPS_TO_CLASS(data($node/@designType))
    let $dependsOn := data($node/@dependsOn)
    let $url :=  data($node/@docUri)
    let $html := <li> 
                    {
                        if (empty($url) or string($url) = '') then <span class="icon {$class}">{$name} [ {$referenceType}:{$dependsOn})</span>
                        else
                        <a class="icon {$class}" href="{$pathPrefix}/{$url}">{$name} [{$referenceType}:{$dependsOn}]</a>
                    }
                    {mhtml:DependencyTree($node,$pathPrefix)}
                </li>
    return
    $html
};

(:~ Function Generates Div Label With correcponding Design Object icon based on the design MimeType Field Value
 :
 : @param $objectType as xs:string? Vaulue of Design rep:Item/rep:MimeType
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @param $options as map(*) Map object with rendering Options (reserved for future use, currently ignored)
 : @returns html nodes
:)
declare function mhtml:objectWithIcon(
    $objectType as xs:string?,
    $objectName as xs:string?,
    $options as map(*)?
) as item()*{
  let $imageUrl :=   
        switch ($objectType) 
        case "application/xml+processobject" return "/iics/static/icons/processobject-x22.png"
        case "application/xml+connection" return "/iics/static/icons/connections.svg"
        case "application/xml+screenflow" return "/iics/static/icons/guide.svg"
        case "application/xml+process" return "/iics/static/icons/process.svg"
        case "application/xml+businesssconnector" return "/iics/static/icons/service_connector.svg"
        case "application/xml+taskflow" return "/iics/static/icons/taskflow.svg"
    default return () 
  return
  <div title="{$objectName}" class="noWrapLabel">
    <img class="shellLibNameImage" src="{$imageUrl}"/>
    <span class="shellLibNameMargin">{$objectName}</span>
  </div>
};

(:~ Function Generates Table with Design Object Attributes (all immediate Children  of rep:Item element except the rep:Item/rep:Entry)
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:RepositoryMetadata (
  $designDoc as node(),
  $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <h2>Repository Meta Data</h2>
        <table class="simpleTable">
            <tbody>
            {for $element in $designDoc/rep:*
            where local-name($element) != "Entry" 
            order by local-name($element) 
            return
            <tr>
                <td>{local-name($element)}</td>
                <td>{$element/text()}</td>
            </tr>
            }
            </tbody>
        </table>
    </div> 
};

(:~ Function Generates Table with Design Object Common Attributes and Sub Section With Desig Type Specific Details
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:DesigFileMetadata(
    $designDoc as node(),
    $pathPrefix as xs:string?
) as item()* {
    let $design := $designDoc/rep:Entry/*
    let $uri    := db:path($designDoc)
    let $name   := $designDoc/rep:Name/text()
    let $guid   := $designDoc/rep:GUID/text()
    let $displayName := $designDoc/rep:DisplayName/text()
    let $designType  := $designDoc/rep:MimeType/text()
    let $designTypeLabel  := $mhtml:IPD_TYPES($designType)
    
    return
    <div id="design-tabs">
        <ul>
           <li><a href="#design-tabs-1">Design Details</a></li>
           <li><a href="#design-tabs-2">Repository Meta Data</a></li>
        </ul>
        <div id="design-tabs-1">
            <div class="reportsection">
                <h2>{$displayName} [{$name}]</h2>
                <table class="simpleTable">
                    <tbody>
                     <tr>
                        <td>Design File</td>
                        <td><a href="{$pathPrefix}/{$uri}">{$uri}</a></td>
                     </tr>
                     <tr>
                        <td>Type</td>
                        <td>{$designTypeLabel}</td>
                     </tr>
                     <tr>
                        <td>GUID</td>
                        <td>{$guid}</td>
                     </tr>
                     <tr>
                        <td>Description</td>
                        <td>{data($design/*:description/text())}</td>
                     </tr>
                     <tr>
                        <td>Notes</td>
                        <td>{data($design/*:notes/text())}</td>
                     </tr>
                     <tr>
                        <td>Repository Tags</td>
                        <td>{data($designDoc/rep:Tags/text())}</td>
                     </tr>
                     <tr>
                        <td>Tags</td>
                        <td>{data($design/*:tags/text())}</td>
                     </tr>
                     <tr>
                        <td>Generator</td>
                        <td>{data($design/*:generator/text())}</td>
                     </tr>
                    </tbody>
                </table>
            </div>
            {mhtml:ObjectInfo($design,$pathPrefix)}
        </div><!-- END Design TAB 1-->
        <div id="design-tabs-2">
            {mhtml:RepositoryMetadata($designDoc,$pathPrefix)}
        </div><!-- END Design TAB 2 -->
    </div>
};


(:~ Dispatch Function to generate Design Specific Information Sections of the Report
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:ObjectInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item()* {
    typeswitch ($node)
        case element(sfd:avosScreenflow) return mhtml:GuideInfo($node,$pathPrefix)
        case element(sfd:process) return mhtml:ProcessInfo($node,$pathPrefix)
        case element(svc:businessConnector) return mhtml:ConnectorInfo($node,$pathPrefix)
        case element(hen:processObject) return mhtml:ProcessObjectInfo($node,$pathPrefix)
        case element(con:connection) return mhtml:ConnectionInfo($node,$pathPrefix)
        case element(sfd:taskflow) return (mhtml:ProcessInfo($node,$pathPrefix),mhtml:TaskFlowInfo($node,$pathPrefix))
        default return ()
    
};

(:~ Function to generate Guide Information Sections of the Report
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:GuideInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <h2>Guide Properties</h2>
        <table class="simpleTable">
            <tbody>
             <tr>
                <td>Allow restart</td>
                <td>{data($node/@allowRestart)}</td>
             </tr>
             <tr>
                <td>Done On End Step</td>
                <td>{data($node/@doneOnEndStep)}</td>
             </tr>
             <tr>
                <td>Run as User</td>
                <td>{data($node/@runAsUser)}</td>
             </tr>
             <tr>
                <td>Applies To</td>
                <td>{$node/sfd:appliesTo/text()}</td>
             </tr>
            </tbody>
        </table>
        {mhtml:FieldsInfo($node,$pathPrefix)}
    </div>
};

(:~ Function to generate Input,Temp,Output Fields Information Information for Guides, Processes and Task Flows
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:FieldsInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item()* {
    <div>
        <h3>Input Fields</h3>
        <div class="tableWrapper">
        <table class="display" id="property_list" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Type</th>
                 <th>Required</th>
                 <th>Description</th>
                 <th>Reference To</th>
               </tr>
            </thead>
            <tbody>
             {for $item in $node/sfd:input/sfd:parameter
                 return
                 <tr>
                    <td>{data($item/@name)}</td>
                    <td>{data($item/@type)}</td>
                    <td>{$item/sfd:options/sfd:option[@name="required"]/text()}</td>
                    <td>{data($item/@description)}</td>
                    <td>{$item/sfd:options/sfd:option[@name="referenceTo"]/text()}</td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
        <div class="tableWrapper">
        <h3>Output Fields</h3>
        <table class="display" id="property_list" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Type</th>
                 <th>Required</th>
                 <th>Description</th>
                 <th>Reference To</th>
               </tr>
            </thead>
            <tbody>
             {for $item in $node/sfd:output/sfd:field
                 return
                 <tr>
                    <td>{data($item/@name)}</td>
                    <td>{data($item/@type)}</td>
                    <td>{$item/sfd:options/sfd:option[@name="required"]/text()}</td>
                    <td>{data($item/@description)}</td>
                    <td>{$item/sfd:options/sfd:option[@name="referenceTo"]/text()}</td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
        <div class="tableWrapper">
        <h3>Temp Fields</h3>
        <table class="display" id="property_list" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Type</th>
                 <th>Required</th>
                 <th>Description</th>
                 <th>Reference To</th>
               </tr>
            </thead>
            <tbody>
             {for $item in $node/sfd:tempFields/sfd:field
                 return
                 <tr>
                    <td>{data($item/@name)}</td>
                    <td>{data($item/@type)}</td>
                    <td>{$item/sfd:options/sfd:option[@name="required"]/text()}</td>
                    <td>{data($item/@description)}</td>
                    <td>{$item/sfd:options/sfd:option[@name="referenceTo"]/text()}</td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
    </div>
};

(:~ Function to generate Process Design Information
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:ProcessInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <div class="tableWrapper">
        <h2>Process Properties</h2>
        <table class="simpleTable">
            <tbody>
             <tr>
                <td>Suspend on Fault</td>
                <td>{data($node/sfd:deployment/@suspendOnFault)}</td>
             </tr>
             <tr>
                <td>Tracing Level</td>
                <td>{data($node/sfd:deployment/@tracingLevel)}</td>
             </tr>
             <tr>
                <td>Allow Anonymous Access</td>
                <td>{$node/sfd:deployment/sfd:rest/sfd:allowAnonymousAccess/text()}</td>
             </tr>
             <tr>
                <td>Target Location</td>
                <td>{
                    let $targetLocation := $node/sfd:deployment/sfd:targetLocation/text()
                    return 
                    if (empty($targetLocation)) then "Cloud"
                    else $targetLocation
                    }
                </td>
             </tr>
            </tbody>
        </table>
        {mhtml:FieldsInfo($node,$pathPrefix)}
        </div>
    </div>
};


(:~ Function to generate Connection Information 
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:ConnectorInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <div class="tableWrapper">
        <h2>Connector Properties</h2>
        <table class="display" id="property_list" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Type</th>
                 <th>Required</th>
                 <th>Masked</th>
                 <th>Description</th>
                 <th>Test With</th>
               </tr>
            </thead>
            <tbody>
             {for $attribute in $node/cnt:connectionAttributes/cnt:connectionAttribute
                 return
                 <tr>
                    <td>{data($attribute/@name)}</td>
                    <td>{data($attribute/@type)}</td>
                    <td>{data($attribute/@required)}</td>
                    <td>{data($attribute/@masked)}</td>
                    <td>{data($attribute/@description)}</td>
                    <td>{data($attribute/@testWith)}</td>

                 </tr>
             }
            </tbody>
        </table>
        </div>
        <div class="tableWrapper">
        <h3>Actions</h3>
        <table class="display" id="action_list" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Action</th>
                 <th>Label</th>
                 <th>Description</th>
                 <th>Category</th>
                 <th>Fail On Error</th>
                 <th>Preemptive Auth</th>
                 <th>Is Abstract</th>
                 <th>Inherits</th>
                 <th>Binding Verb</th>
               </tr>
            </thead>
            <tbody>
             {for $action in $node/svc:actions/svc:action
                 order by $action/@category,$action/@name
                 return
                 <tr>
                    <td>{data($action/@name)}</td>
                    <td>{data($action/@label)}</td>
                    <td>{$action/*:description/text()}</td>
                    <td>{data($action/@category)}</td>
                    <td>{data($action/@failOnError)}</td>
                    <td>{data($action/@preemptiveAuth)}</td>
                    <td>{data($action/@isAbstract)}</td>
                    <td>{data($action/@inherits)}</td>
                    <td>{data($action//*:restSimpleBinding/@verb)}</td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
        <div class="tableWrapper">
        <h3>Process Objects</h3>
        <table class="display" id="po_list" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Description</th>
                 <th>Field Count</th>
                 <th>Fields</th>
               </tr>
            </thead>
            <tbody>
             {for $po in $node/svc:objects/hen:processObject
                 order by $po/@name
                 return
                 <tr>
                    <td>{data($po/@name)}</td>
                    <td>{data($po/hen:description/text())}</td>
                    <td>{count($po/hen:detail/hen:field)}</td>
                    <td>
                        <ul>{for $field in $po/hen:detail/hen:field
                            return
                            <li>{string-join((data($field/@name),data($field/@type),data($field/*:options/*:option[@name="referenceTo"]/text()))," - ")}</li>
                            }
                        </ul>
                    </td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
        
    </div>
};

(:~ Function to generate Process Object Design Information
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:ProcessObjectInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <div class="tableWrapper">
        <h3>Fields</h3>
        <table class="display" id="fieldList" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Label</th>
                 <th>Type</th>
                 <th>Reference To</th>
               </tr>
            </thead>
            <tbody>
             {for $field in $node/hen:detail/hen:field
                 order by $field/@name
                 return
                 <tr>
                    <td>{data($field/@name)}</td>
                    <td>{data($field/@label)}</td>
                    <td>{data($field/@type)}</td>
                    <td>{$field/hen:options/hen:option[@name="referenceTo"]/text()}</td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
    </div>
};

(:~ Function to generate Connection Design Information
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:ConnectionInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <div class="tableWrapper">
        <h3>Attributes</h3>
        <table class="simpletable" id="property_list" style="margin-right:auto;margin-left:0px">
            <thead>
               <tr>
                 <th>Name</th>
                 <th>Value</th>
                 <th>Encrypted</th>
               </tr>
            </thead>
            <tbody>
             {for $attribute in $node/con:attributes/con:attribute
                 return
                 <tr>
                    <td>{data($attribute/@name)}</td>
                    <td>{data($attribute/@value)}</td>
                    <td>{data($attribute/@encrypted)}</td>
                 </tr>
             }
             {for $attribute in $node/con:authentication/con:attributes/con:attribute
                 return
                 <tr>
                    <td>authentication:{data($node/con:authentication/@type)}:{data($attribute/@name)}</td>
                    <td>{data($attribute/@value)}</td>
                    <td>{data($attribute/@encrypted)}</td>
                 </tr>
             }
            </tbody>
        </table>
        </div>
    </div>
};

(:~ Function to generate Task Flow Design Information
 :
 : @param $designDoc as node() Design Document
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:TaskFlowInfo (
    $node as node(),
    $pathPrefix as xs:string?
) as item() {
    <div class="reportsection">
        <h2>Tasks</h2>
        { 
        for $service in $node//sfd:service  
        return
        <div>
            <h3>{$service/sfd:title/text()}</h3>
            <p>Task Service: {$service/sfd:serviceName/text()}</p>
            <h3>Inputs</h3>
            <table class="simpletable" id="property_list" style="margin-right:auto;margin-left:0px;">
                <thead>
                    <tr>
                        {
                        for $attr in $service/sfd:serviceInput/sfd:parameter[1]/@*  
                        return
                        <th>{util:capitalize(local-name($attr))}</th>
                        }
                        <th>Value</th>
                    </tr>
                </thead>
                <tbody> 
                    {for $parameter in $service/sfd:serviceInput/sfd:parameter 
                    return
                    <tr>
                        {
                        for $attr in $parameter/@*
                        return
                        <td>{data($attr)}</td>
                        }
                        <td>{$parameter/text()}</td>
                    </tr>
                    }
                </tbody>
            </table>
            <h3>Outputs</h3>
            <table class="simpletable" id="property_list" style="margin-right:auto;margin-left:0px;">
                <thead>
                    <tr>
                        {
                        for $attr in $service/sfd:serviceOutput/sfd:operation[1]/@* 
                        return
                        <th>{util:capitalize(local-name($attr))}</th>
                        }
                        <th>Value</th>
                    </tr>
                </thead>
                <tbody> 
                    {
                    for $parameter in $service/sfd:serviceOutput/sfd:operation 
                    return
                    <tr>
                        {
                        for $attr in $parameter/@*
                        return
                        <td>{data($attr)}</td>
                        }
                        <td>{$parameter/text()}</td>
                    </tr>
                    }
                </tbody>
            </table>
        </div>
        }
    </div>
};





(: Function will render dependencies as a table with distinct object dependencies
 : Example Dependency tree Source
 : <dependencies object="Setup_Logging_DB" guid="akOVKXc0aE7lAct0X7uEMo">
 :   <dependency objectName="Setup Logging DB" referenceFrom="Setup_Logging_DB" referenceTo="SP-Setup-Logging-DB" fromGuid="akOVKXc0aE7lAct0X7uEMo" toGuid="jSu7p8fQuE8dQDuX3vRk6v" referenceType="Process" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/Logging/Setup/SP-Setup-Logging-DB.PROCESS.xml">
 :     <dependency objectName="DataAccessService" referenceFrom="SP-Setup-Logging-DB" referenceTo="DataAccessService:tMultiResponse" fromGuid="jSu7p8fQuE8dQDuX3vRk6v" toGuid="jhXRGp8HGy8fOjJy57yhy1" referenceType="Connection:ProcessObject" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_CONNECTION.xml"/>
 :     <dependency objectName="DataAccessService" referenceFrom="SP-Setup-Logging-DB" referenceTo="DataAccessService:tMultiDataAccessRequest" fromGuid="jSu7p8fQuE8dQDuX3vRk6v" toGuid="jhXRGp8HGy8fOjJy57yhy1" referenceType="Connection:ProcessObject" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_CONNECTION.xml"/>
 :     <dependency objectName="SP-Setup-Logging-DB" referenceFrom="SP-Setup-Logging-DB" referenceTo="DataAccessService" fromGuid="jSu7p8fQuE8dQDuX3vRk6v" toGuid="jhXRGp8HGy8fOjJy57yhy1" referenceType="Connection" connectorType="businessConnector" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_CONNECTION.xml">
 :       <dependency objectName="DataAccessService" referenceFrom="DataAccessService" referenceTo="DataAccessService" fromGuid="jhXRGp8HGy8fOjJy57yhy1" toGuid="cZ66760oF8pjwt5OEx7AY1" referenceType="Connector" connectorType="businessConnector" docUri="IICS-SRC-ICLAB-08-05-2019.zip/Explore/DAS/DataAccessService.AI_SERVICE_CONNECTOR.xml" uuid="93d7509e-96fb-4872-b8c1-41f382c1811f"/>
 :     </dependency>
 :     <dependency objectName="execMultiSQL" referenceFrom="jSu7p8fQuE8dQDuX3vRk6v" referenceTo="execMultiSQL" fromGuid="SP-Setup-Logging-DB" toGuid="" referenceType="Service" docUri="">
 :       <info>This Service reference is either System Service or Connection Service</info>
 :     </dependency>
 :   </dependency>
 : </dependencies>
 : @param $designDependencies as node()* Design Dependecies Structure
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
:)
declare function mhtml:ObjectDependencies (
    $designDependencies as node()*,
    $pathPrefix as xs:string?
) as node()*{
    let $distinctDeps := distinct-values( for $item in $designDependencies//dependency return 
                                            concat(data($item/@referenceTo),"::",data($item/@toGuid)))
    let $database := tokenize($pathPrefix,"/")[last()]
    return
    <div class="reportsection">
        This table contains complete list of distinct dependencies of the design object
        { 
        let $maxDepth :=  max(for $node in $designDependencies//dependency
                        return count($node/ancestor::dependency))
        return 
            if (empty($maxDepth )) then ()
            else <div class=".ui-corner-all">Maximum Dependency Depth: {$maxDepth}</div>
        }
        <div class="tableWrapper">
        <table class="display" id="dependency_table" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
                <tr>
                    <th>Object</th>
                    <th>Reference To</th>
                    <th>Type</th>
                    <th>Location</th>
                    <th>Warnings</th>
                </tr>
            </thead>
            <tbody>
            {   
                for $distninctDep in $distinctDeps
                    let $referenceTo := substring-before($distninctDep,"::")
                    let $guid := substring-after($distninctDep,"::")
                    let $deps := $designDependencies//dependency[@referenceTo = $referenceTo and @toGuid=$guid ]
                    let $dep := $deps[1]
                    let $objectName := data($dep/@objectName)
                    let $fromGuid := data($dep/@fromGuid)
                    let $toGuid := data($dep/@toGuid)
                    let $docUri := data($dep/@docUri)
                    let $referenceType := data($dep/@referenceType)
                    let $warnings := for $warning in $dep/warning/text() 
                                return <div><span>
                                    <span class="ui-icon ui-icon-info" style="float: left; margin-right: .3em;"></span>
                                    <span class="ui-state-highlight">{$warning}</span>
                                    </span></div>

                    order by $referenceTo
                return
                <tr>
                    <td>{
                        if (empty($toGuid) or $toGuid='') then $objectName
                        else <a href="design?database={$database}&amp;guid={$guid}" target="_blank">{$objectName}</a>
                        }</td>
                    <td>{$referenceTo}</td>
                    <td>{$referenceType}</td>
                    <td>
                        {
                        if (empty($docUri)) then ()
                        else 
                            <a href="{$pathPrefix}/{$docUri}" target="_blank">{$docUri}</a>
                        }
                    </td>
                    <td>{$warnings}</td>
                </tr>
            }
            </tbody>
        </table>
        </div>
    </div>
};

(:~ Function produces Used By Impact Summary Table
 : <usedBy displayName="UncaughtFaultAlertHandler-NA" 
 :     name="UncaughtFaultAlertHandler-NA" 
 :     guid="9UWeUqnSHkalqQVZI82Ekf" 
 :     dependsOn="github-gist-alert-configuration:getGistFile" 
 :     dependsOndisplayName="github-gist-alert-configuration" 
 :     dependsOnGuid="2AJJfAJqQLkaZMytvRBVWR" 
 :     referenceType="service" 
 :     docUri="Explore/Alerting/Processes/UncaughtFaultAlertHandler-NA.PROCESS.xml">
 :     <usedBy displayName="Alert Configuration Manager" 
 :         name="Alert_Configuration_Manager" 
 :         guid="8zodeZJhfnBdPPMtFf1DQE" 
 :         dependsOn="UncaughtFaultAlertHandler-NA" 
 :         dependsOndisplayName="UncaughtFaultAlertHandler-NA" 
 :         dependsOnGuid="9UWeUqnSHkalqQVZI82Ekf" 
 :         referenceType="service" 
 :         docUri="Explore/Alerting/Guides/Alert Configuration Manager.GUIDE.xml"/>
 : </usedBy>
 :
 : @param $impactData as node()* Design Impact (Used By) tree
 : @param $pathPrefix as xs:string? Parameter is used to generate links to referenced documents over basex REST API example /rest/DB_NAME
 : @returns html nodes
 :
:)
declare function mhtml:ObjectusedBy (
    $impactData as node()*,
    $pathPrefix as xs:string?
) as node()*{
    let $distinctImpacts := distinct-values( for $item in $impactData//usedBy return 
                                            concat(data($item/@name),"::",data($item/@guid)))
    let $database := tokenize($pathPrefix,"/")[last()]
    return
    <div>
        { 
        let $maxDepth :=  max(for $node in $impactData//usedBy
                        return count($node/ancestor::usedBy))
        return 
            if (empty($maxDepth )) then ()
            else <div class=".ui-corner-all">Maximum Impact Parent Levels: {$maxDepth}</div>
        }
        <div class="tableWrapper">
        Following table displays objects that use current design, these object might be impacted by the changes of current design.
        <table class="display" id="impact_table" style="margin-right:auto;margin-left:0px;width:100%">
            <thead>
              <tr>
                  <th>Used By</th>
                  <th>Reference Type</th>
                  <th>Depends On</th>
                  <th>Used By Design Location</th>
              </tr>
            </thead>
            <tbody>            
            {   
                for $impact in $distinctImpacts
                    let $name := substring-before($impact,"::")
                    let $guid := substring-after($impact,"::")
                    let $impacts       := $impactData//usedBy[@name=$name and @guid=$guid]
                    let $design        := $impacts[1] 
                    let $dependsOn     := data($design/@dependsOn)
                    let $dependsOnGuid := data($design/@dependsOnGuid)
                    let $dependsOndisplayName := data($design/@dependsOndisplayName)
                    let $location      := data($design/@docUri)
                    let $referenceType := data($design/@referenceType)
                    let $designUri     := concat($pathPrefix,'/',$location)
                    order by $impact 
                return
                <tr>
                    <td>
                        {
                        if (empty(data($design/@guid))) then ($name)
                        else <a href="design?database={$database}&amp;guid={$guid}" target="_new">{$name}</a>
                        }
                    </td>
                    <td>{$referenceType}</td>
                    <td>{$dependsOndisplayName}</td>
                    <td>
                        {
                        if (empty($location)) then ($name)
                        else 
                            <a href="{$designUri}" target="_new">{$location}</a>
                        }
                    </td>
                </tr>
            }
            </tbody>
        </table>
        </div>   
    </div>
};