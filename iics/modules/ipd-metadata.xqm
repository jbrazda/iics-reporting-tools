(:~
: This module provides utility functions to read and analyze IPD object designs and metadata
: 
: @author jbrazda
: @since Sep 2019
: @version 1.0
:)

module namespace imf = 'iics/imf';


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


(:~
 : Function returns IICS design by GUID
 : 
 : @param $guid as xs:string? IICS internal GUID for the object
 : @return empty set if file is not found in the repository or a document Instance of design with metadata
 :)
declare function imf:getDesignByGuid (
   $database as document-node()*,  
   $guid as xs:string? 
) as node()* {
   $database//rep:Item[rep:GUID = $guid]
};

(:~
 : Function returns file repository document resolved by the IPD object name and optional Type;
 : Object name is not gauaranteed to be unique for different types so It is recommended to use a type to avoid ambiguous results
 :
 : @param $database as node() PID Document Collection repository with file descriptors
 : @param $objectType as xs:string? optional object Type can be one of the following (processobject, connection, screenflow, process, businesssconnector)
 : @param $objectName as xs:string  Design Object Name (rep:Name)
 : @return empty set if file is not found in ther repo or Catalog Instance of the repository file with metadata
 :)
declare function imf:getDesignByObjectName (
    $database as document-node()*,
    $objectType as xs:string?, 
    $objectName as xs:string? 
) as node()* {
    if (string($objectType) = "") then
        $database//rep:Item[rep:Name/text() = $objectName ]
    else 
        $database//rep:Item[rep:MimeType/text() = concat("application/xml+",$objectType) and rep:Name/text() = $objectName ]
};


(:~
 : Function resolves repository Document  entry for Connector by UUID and Name
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $uuid as xs:string Connector UUID
 : @param $name as xs:string? Optional Connector Name
 : @return empty set if file is not found in ther repo or Calatog Instance of the repo file
 :)
declare function imf:getConnectorByUid (
   $database as document-node()*, 
   $uuid as xs:string, 
   $name as xs:string?
) as node()? {
    if (empty($name)) 
    then
        $database//rep:Item[rep:Entry/*/@uuid = $uuid ]
    else
        $database//rep:Item[rep:Name/text() = $name and rep:Entry/*/@uuid = $uuid ]
};


(:~
 : Function Calculates IPD Design Object Dependdencies
 : TODO: Implement Support for TaskFlow Dependencies
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $document as node()? IPD Design Document Instance to analyze for Dependencies
 : @return empty set if file is not found in ther repo or Calatog Instance of the repo file
 :)
declare function imf:getObjectDependencies (
   $database as document-node()*, 
   $document as node()?
) as item()* {
    let $design := $document/rep:Entry/*
    let $guid   := $document/rep:GUID/text()
    let $name   := $document/rep:Name/text()
    
    return
    <dependencies object="{$name}" guid="{$guid}">
        {
        typeswitch ($design)
          case element(svc:businessConnector) return ()
          case element(con:connection) return imf:getConnectionDependencies($database,$document,$name)
          case element(hen:processObject) return imf:getPODependencies($database,$document)
          default return imf:getDesignDependencies($database,$document,())
        }
     </dependencies>
};

(:~
 : Function Calculates IPD Process Object Dependencies
 : This function is recursive
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $document as node()? IPD Design Document Instance to analyze for Dependencies
 : @return empty set if file is not found in ther repo or Calatog Instance of the repo file
 :)
declare function imf:getPODependencies (
   $database as document-node()*, 
   $design as node()?
) as item()* {
    let $guid := $design/rep:GUID/text()
    let $name := $design/rep:Name/text()
    
    let $referenceFrom := '$po:' || $name
    return for $reference in $design//hen:detail/hen:field[@type="reference" or @type="objectlist"]
            let $referenceTo    := $reference/hen:options/hen:option[@name="referenceTo"]/text()
            let $objectName     := substring-after($referenceTo, ":")
            let $connectionName := substring-before($referenceTo, ":")
            let $dependOnGuid   := $reference/hen:options/hen:option[@name = 'guid']/text()
            let $referenceType  := if ($connectionName = '$po') then 'Process Object' else 'Connection PO'
            let $design         := imf:getDesignByGuid($database,$dependOnGuid) 
            let $children       := imf:getPODependencies($database,$design)
            let $documentUri    := if (empty($design)) then () else db:path($design)
         return
         <dependency 
            objectName="{$objectName}" 
            fromGuid="{$guid}"
            toGuid="{$dependOnGuid}"
            referenceFrom="{$referenceFrom}"
            referenceTo="{$referenceTo}" 
            referenceType="{$reference/@type}" 
            type="{$referenceType}"
            docUri="{$documentUri}">
            {
             if (empty($design) and $referenceTo != '$po:$any') then 
               <warning type="Missing Dependency">Missing Referenced Object From:{$referenceFrom} To:{$referenceTo} guid:{$dependOnGuid}</warning>
               
             else $children 
            }
         </dependency>
};


(:~
 : Function Provides dependency tree for Designs in the Guides and Processes
 : This is a recursive function that must prvent infite loop when cyclical dependensies occur, it uses $parentFlows
 : as a stack of parent references which is is used to break out of cyclic dependencies
 :
 : @param $database as node() PID Document Collection repository with file descriptors
 : @param $subflowPath as xs:string  Subflow name (guide or process)
 : @param $parentFlows as xs:string  Parent flows stack mainteind during recursion 
 : @return SubFlow Dependencies
 :)
declare function imf:getDesignDependencies (
   $database as document-node()*, 
   $designFile as node()?, 
   $parentFlows as xs:string*
) as node()* {
    let $design := $designFile/rep:Entry/*
    let $guid := $designFile/rep:GUID/text()
    let $name := $designFile/rep:Name/text()

    let $objectDependencies := for $field in $design//(*:field|*:parameter)[@type="reference" or @type="objectList"]
                let $referenceTo     := $field/*:options/*:option[@name="referenceTo"]/text()
                let $objectContainer := substring-before($referenceTo, ":")
                let $objectName      := substring-after($referenceTo, ":")
                let $objectDesign    := imf:getDesignByObjectName($database,(),$objectName)
                return
                 switch  ( true() ) 
                   case (count($objectDesign) = 0 and $objectContainer = '$po') 
                     return 
                        <warning type="Missing Object Reference">Could not find object reference to {$referenceTo}</warning> 
                   case (count($objectDesign) = 1) 
                     return 
                        imf:getPODependencies($database,$objectDesign)
                   case (count($objectDesign) > 1) 
                     return 
                        <warning type="Ambiguous Object Reference">Found more than 1 object with name {$referenceTo} 
                           {string-join(for $item in $objectDesign return $item/rep:Name/text() || '[' || $item/rep:GUID/text() || ']' )}
                        </warning> 
                  default 
                     return
                        let $connectionObject := imf:getDesignByObjectName($database,'connection',$objectContainer)
                        let $connGuid         := $connectionObject/rep:GUID/text() 
                        let $documentUri      := if (empty($connectionObject)) then () else db:path($connectionObject)
                        return
                        <dependency objectName="{$objectContainer}" 
                           referenceFrom="{$name}" 
                           referenceTo="{$referenceTo}" 
                           fromGuid="{$guid}" toGuid="{$connGuid}" 
                           referenceType="Connection:ProcessObject"
                           docUri="{$documentUri}"/>
                  
   (: build distinct set of connections used by the process:)
   let $connections := 
      for $field in $design//(*:field|*:parameter)[@type="reference" or @type="objectList"]
         let $referenceTo     := $field/*:options/*:option[@name="referenceTo"]/text()
         let $conName := substring-before($referenceTo,":")
      where $conName != "$po"
      return $conName
   (:getting create step connection dependencies:)
   let $createStepConnections :=  
      for $object in $design//*:create/*:entityName/text()
        let $conName := substring-before($object,":")
      return $conName
 
   let $connectionDependencies :=  
      for $connectionName in distinct-values(($connections,$createStepConnections)) 
      return
      imf:getConnectionDependencies($database,$designFile,$connectionName)
      
   return
   (   
      $objectDependencies
      ,imf:getSubflowDependencies($database,$designFile,$parentFlows)
      ,imf:getServiceDependencies($database,$designFile,$parentFlows)
      ,$connectionDependencies
   )
};




(:~
 : Function Provides dependencies on Connections, reference to a connector used by the connection
 
 Connector Type examples
   
    <javaConnector xmlns="http://schemas.informatica.com/appmodules/screenflow/2014/04/avosConnectors.xsd"
           agentOnly="true"
           plugin="Camel"
           supportsConnectionTest="true"
           supportsDataPreview="false"
           supportsOData="false"
           type="File"
           uuid="ac000300-d9fe-11e4-8830-0800200c9a66">
   
   <businessConnector xmlns="http://schemas.informatica.com/appmodules/screenflow/2014/04/avosConnectors.xsd"
           agentOnly="false"
           connectorPath="project:/rt.connector/ICS_API/ICS_API_svcDef.xml"
           name="ICS_API"
           supportsConnectionTest="false"
           uuid="5948d459-e805-42c1-b510-47e0685c1be2">
       <description>Native connector for Informatica Cloud API.</description>
    </businessConnector>
    
    <soaConnector xmlns="http://schemas.informatica.com/appmodules/screenflow/2014/04/avosConnectors.xsd"
          connectorPath="project:/com.activevos.cumulus.cloud.extend.playbook.configuration/config/sfConnector.xml"
          name="Salesforce"
          supportsConnectionTest="true"
          supportsOData="true"
          uuid="05fc48f1-e6e1-441b-b700-bac396ca2ed1">
       <description>Salesforce.com SOA based data connector.</description>
    </soaConnector>                     
 :
 : @param $database as node() PID Document Collection repository with file descriptors
 : @param $connectionName as xs:string  Connection Name
 : @return Connectiomn Dependencies
 :)
declare function imf:getConnectionDependencies (
   $database as document-node()*, 
   $fromDesignFile as node(), 
   $connectionName as xs:string
) as node()* {
    let $fromDesignFile := $fromDesignFile
    let $referenceFrom  := $fromDesignFile/rep:Name/text()
    let $fromGuid       := $fromDesignFile/rep:GUID/text()
    let $displayName    := $fromDesignFile/rep:DisplayName/text()
    let $referedCon     := imf:getDesignByObjectName($database,"connection",$connectionName)
    let $warnings       := switch (count($referedCon ))
               case 0 
                  return 
                     <warning type="Missing Connection Reference">Counld not find a Connection Definition '{$connectionName}'</warning>
               case 1 
                  return ()
               default 
                  return 
                     <warning type="Ambiguous Reference">Found more than one Connection with Name '{$connectionName}'
                        {string-join(for $item in $referedCon return $item/rep:Name/text() || '[' || $item/rep:GUID/text() || ']' )}
                     </warning>
                     
    let $connectionName := if (empty($referedCon)) then $connectionName else $referedCon[1]/rep:Name/text()
    let $connectionGuid := $referedCon[1]/rep:GUID/text()
    let $design         := $referedCon[1]/rep:Entry/* 
    let $connectorDescriptor := $design/(*:soaConnector|*:businessConnector|*:javaConnector)
    
    let $connectorType  := string-join((local-name($connectorDescriptor),data($connectorDescriptor/@plugin),data($connectorDescriptor/@type)),":")
    let $connectorId    := data($connectorDescriptor/@uuid)
    let $connectorName  := data($connectorDescriptor/@name)
    let $connector      := if (empty($connectorId)) then () 
                           else imf:getConnectorByUid($database,$connectorId,$connectorName)
    let $connectorGuid  := $connector[1]/rep:GUID/text()
    let $connectorDisplayName := $connector[1]/rep:DisplayName/text()
    let $referenceTo    := switch (local-name($connectorDescriptor))
                            case "javaConnector" return local-name($connectorDescriptor)
                            default return $connector[1]/rep:Name/text()
    let $connectorUri  := if (empty($connector)) then ()
                           else db:path($connector)
    let $connectionUri  := if (empty($referedCon)) then () else db:path($referedCon) 
    return
    <dependency objectName="{$displayName}" 
                referenceFrom="{$referenceFrom}" referenceTo="{$connectionName}"  
                fromGuid="{$fromGuid}" toGuid="{$connectionGuid}" 
                referenceType="Connection" connectorType="{$connectorType}"
                docUri="{$connectionUri}">

       {
       if (empty($connectorId )) then <warning type="Unresolved Connector reference">Unable to Resove Connection Connector Reference or Type</warning>
       else
       <dependency objectName="{$connectorDisplayName}" 
                referenceFrom="{$connectionName}" 
                referenceTo="{$referenceTo}" 
                fromGuid="{$connectionGuid}" toGuid="{$connectorGuid}" 
                referenceType="Connector" connectorType="{$connectorType}"
                docUri="{$connectorUri}">
         {$connector/@*, $connectorDescriptor/@uuid}
       </dependency>
       }
       {$warnings}
    </dependency>
};





(:~
 : Function Provides dependency tree for Subflows in the Guides and Processes
 
 : Looking for 
   <code>
    <subflow id="jthesmqr">
        <title>iPaaS Job View</title>
        <subflowGUID>anJKIeJPfDJk8kvVHqi4Wo</subflowGUID>
        <subflowPath>iPaaS_Job_View_DB</subflowPath>
        <runAsUser>$current</runAsUser>
        <serviceInput>
           <parameter id="jv2tbwa0" name="in_job_id" source="field" updatable="true">temp.tmp_ic_job_log</parameter>
        </serviceInput>
        <actions>
           <action alt="" id="jthesmqr_jthesmqs" targetScreen="jthesmqs">
              <text>Continue</text>
           </action>
        </actions>
     </subflow>
   </code>
   or
   <code>
   <callProcess id="jvffo6cp">
      <title>SP-Setup-Logging-DB</title>
      <subflowGUID>jSu7p8fQuE8dQDuX3vRk6v</subflowGUID>
      <subflowPath>SP-Setup-Logging-DB</subflowPath>
      <runAsUser>$current</runAsUser>
      <serviceInput>
         <parameter id="jvfi37vj" name="in_task" source="field" updatable="true">temp.tmp_task</parameter>
         <parameter id="jvfi37vk" name="in_dbType" source="field" updatable="true">temp.tmp_dbType</parameter>
         <parameter id="jvfi37vl"
                    name="in_dataSource"
                    source="field"
                    updatable="true">temp.tmp_dataSource</parameter>
      </serviceInput>
      <subflowOutput>
         <field name="out_multiDataAccessResponse" type="reference">
            <options>
               <option name="referenceTo">DataAccessService:tMultiResponse</option>
               <option name="required">false</option>
               <option name="isCopy">true</option>
               <option name="guid">jhXRGp8HGy8fOjJy57yhy1</option>
            </options>
         </field>
      </subflowOutput>
      <actions>
         <action alt="null" id="jvffo6cp_jvffo6d4" targetScreen="jvffo6d4">
            <text>Continue</text>
         </action>
      </actions>
   </callProcess>
   </code>
 : This is a recursive function that must prvent infinite loop when cyclycal dependensies occur it uses $parentFlows
 : as a stack of parent references which is is used to break out of cyclic dependencies
 : @param $database as node() PID Document Collection repository with file descriptors
 : @param $subflowPath as xs:string  Subflow name (guide or process)
 : @param $parentFlows as xs:string  Parent flows stack mainteind during recursion 
 : @return SubFlow Dependencies
 :)
declare function imf:getSubflowDependencies (
   $database as document-node()*, 
   $parentDesign as node()?, 
   $parentFlows as xs:string*
) as node()* {
    let $fromGuid := $parentDesign/rep:GUID/text()
    let $referenceFrom := $parentDesign/rep:Name/text()
    let $fromDisplayName := $parentDesign/rep:DisplayName/text()
    
    (: get distinct set of subflows referenced by the design:)
    let $distinctSubflows := distinct-values($parentDesign//(*:subflow|*:callProcess)/*:subflowGUID/text())
    (:we need to exclude parent flows from recursion to prevent infinite loop for cyclic dependencies :)
    let $parentStack := distinct-values(($parentFlows, $fromGuid))
    let $distinctSubflowsMinusParent := distinct-values($distinctSubflows[not(.=$parentStack)])
    return 
      for $subflowId in $distinctSubflowsMinusParent
            let $refFlow       := imf:getDesignByGuid($database,$subflowId)
            let $reference     := $parentDesign//(*:subflow|*:callProcess)[*:subflowGUID/text() = $subflowId and position() = 1] 
            let $design        := $refFlow[1]/rep:Entry/* 
            let $toGuid        := if (empty($refFlow)) then $subflowId else $refFlow[1]/rep:GUID/text()
            let $referenceTo   := if (empty($refFlow)) then $reference/*:subflowPath/text() else $refFlow[1]/rep:Name/text()
            let $referenceType := switch (local-name($design))
                    case "avosScreenflow" return "Guide"
                    case "process" return "Process"
                    default return local-name($reference)
            let $docUri := if (empty($refFlow)) then "." else db:path($refFlow)
            return
              <dependency objectName="{$fromDisplayName}" 
                  referenceFrom="{$referenceFrom}" referenceTo="{$referenceTo}"
                  fromGuid="{$fromGuid}" toGuid="{$toGuid}" 
                  referenceType="{$referenceType}" 
                  docUri="{$docUri}">
                 {
                  imf:getDesignDependencies($database,$refFlow,$parentStack)
                 }
                 {
                  switch (count($refFlow))
                     case 0 
                        return 
                        <warning type="Missing Referenced Design">Counld not find a {$referenceType} reference '{$referenceTo}' guid:{$subflowId} </warning>
                     case 1 
                        return ()
                     default 
                        return 
                        <warning type="Ambiguous Reference">Found more than one SubFlow with ID '{$toGuid}'
                           {string-join(for $item in $refFlow return $item/rep:Name/text() || '[' || $item/rep:GUID/text() || ']' )}
                        </warning>
                 }
              </dependency>         
             
};




(:~
 : Function Provides dependencies on Services 
 :
 : @param $database as document-node()* Document Collection repository with file descriptors
 : @param $$parentDesign as node()? Parent design document
 : @return Service Dependencies
 :)
declare function imf:getServiceDependencies (
   $database as document-node()*, 
   $parentDesign as node()?, 
   $parentFlows as xs:string*
) as node()* {
     let $fromName           := $parentDesign/rep:GUID/text()
     let $fromGuid           := $parentDesign/rep:Name/text()
     let $fromDisplayName    := $parentDesign/rep:DisplayName/text()
     let $parentStack        := ($parentFlows,$fromGuid)
     let $design             := $parentDesign/rep:Entry/* 
     let $distinctServices   := distinct-values($design//sfd:service/sfd:serviceName/text())
     let $distinctSubflows   := distinct-values($design//sfd:service/sfd:serviceGUID/text())
     let $distinctSubflowsMinusParent := distinct-values($distinctSubflows[not(.=$parentStack)])
     let $dependencies       := for $service in $distinctServices
           let $serviceName  := if (contains($service, ":"))
                            then substring-before($service, ":")
                            else $service
           let $referenceType := if (contains($service, ":")) then "Connection:Service" else "Service"
           let $serviceGUID   := $design//sfd:service[sfd:serviceName = $service]/sfd:serviceGUID/text()
           let $serviceDesign := if (empty($serviceGUID[1]) or string($serviceGUID[1])='') 
                                 then imf:getDesignByObjectName($database,"process",$serviceName) else imf:getDesignByGuid($database,$serviceGUID[1])
           let $docUri        := if (empty($serviceDesign )) then () else db:path($serviceDesign)
         return
         <dependency objectName="{$serviceName}" 
            referenceFrom="{$fromName}" referenceTo="{$service}" 
            fromGuid="{$fromGuid}" toGuid="{$serviceGUID}"
            referenceType="{$referenceType}" 
            docUri="{$docUri}">
            {if (empty($serviceDesign)) then <warning type="Missing Design Reference">Could not find referenced {$referenceType} to {$serviceName} guid:{$serviceGUID[1]}</warning>  else  imf:getDesignDependencies($database,$serviceDesign,$distinctSubflowsMinusParent) }
        </dependency>
    return 
    $dependencies
};



(:~
 : Function generates Impact of a design used as as Service or Sub-proces or Embedded Guide 
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $fdesignDoc as node()?  Design Object to check impact for
 : @param $traverseImpactTree as xs:boolean When  set to true() then the function will travverse the dependencies 
 :        all the way to top level process/ guide, otherwise it will only scan direct first level dependencies
 : @return Service use in the workspace
 :)
declare function imf:getSubflowImpact (
   $database as document-node()*, 
   $designDoc as node()?,
   $traverseImpactTree as xs:boolean
) as node()* {
    let $name   := $designDoc/rep:Name/text()
    let $guid   := $designDoc/rep:GUID/text()
    let $displayName := $designDoc/rep:DisplayName/text()

    let $impactedFlows:= for $service in $database//rep:Entry[(*:avosScreenflow|*:process|*:taskflow)]//(sfd:service[sfd:serviceName/text()=$name or sfd:serviceGUID/text()=$guid ] |
                                                     sfd:subflow[sfd:subflowPath/text()=$name or sfd:subflowGUID/text()=$guid ] |
                                                     sfd:callProcess[sfd:subflowPath/text()=$name or sfd:subflowGUID/text()=$guid ])
       let $documentUri := db:path($service)
       let $item        := root($service)/*/rep:Item
       let $itemName    := $item/rep:Name/text()
       let $itemGuid    := $item/rep:GUID/text()
       let $designType  := $item/rep:MimeType/text()
       let $itemDisplayName := $item/rep:DisplayName/text()
       let $dependsOn   := typeswitch ($service) 
                             case element(sfd:subflow) return $service/sfd:subflowPath/text()
                             case element(sfd:callProcess) return $service/sfd:subflowPath/text()
                             default return $service/sfd:serviceName/text()
       let $referenceType := local-name($service)
       where $itemGuid != $guid (:prevent cyclic dependecy recursion:)
       return
       <usedBy displayName="{$itemDisplayName}" name="{$itemName}" guid="{$itemGuid}"
               dependsOn="{$dependsOn}" dependsOndisplayName="{$displayName}" dependsOnGuid="{$guid}" 
               referenceType="{$referenceType}" designType="{$designType}"
               docUri="{$documentUri}">
           {
            if ($traverseImpactTree ) then 
               imf:getSubflowImpact($database,imf:getDesignByGuid($database,$itemGuid), $traverseImpactTree )
            else ()
           }
       </usedBy>
  return
  $impactedFlows
};



(:~
 : Function generates Impact for Process Object Definition, finds all objects refering to this process object
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $fdesignDoc as node()?  Design Object to check impact for
 : @param $traverseImpactTree as xs:boolean When  set to true() then the function will travverse the dependencies 
 :        all the way to top level process/ guide, otherwise it will only scan direct first level dependencies
 : @return Process Object Use in the workspace
 :)
declare function imf:getPOImpact (
   $database as document-node()*, 
   $designDoc as node()?, 
   $traverseImpactTree as xs:boolean
) as node()* {
    let $name   := $designDoc/rep:Name/text()
    let $guid   := $designDoc/rep:GUID/text()
    let $displayName := $designDoc/rep:DisplayName/text() 
    let $fullName := "$po:" || $name
    let $impactedObjects := for $flow in $database//rep:Item/rep:Entry[(*:avosScreenflow|*:process|*:processObject|*:taskflow)]
         let $documentUri := db:path($flow)
         let $flowDesign  := root($flow)/*/rep:Item
         let $itemName    := $flowDesign/rep:Name/text()
         let $itemGuid    := $flowDesign/rep:GUID/text()
         let $designType  := $flowDesign/rep:MimeType/text()
         let $itemDisplayName := $flowDesign/rep:DisplayName/text()
         let $useCount := count($flowDesign//(*:field|*:parameter)[(@type="reference" or @type="objectlist") and ./*:options/*:option[@name="referenceTo"]/text() = $fullName])
         where $useCount > 0 and $itemGuid != $guid
         return
             <usedBy 
               displayName="{$itemDisplayName}" name="{$itemName}" guid="{$itemGuid}"
               dependsOn="{$name}" dependsOndisplayName="{$displayName}" dependsOnGuid="{$guid}" 
               useCount="{$useCount}" referenceType="Process Object" designType="{$designType}"
               docUri="{$documentUri}">
               {
                  if ($traverseImpactTree ) then 
                     (
                        imf:getSubflowImpact($database,$flowDesign , $traverseImpactTree ),
                        imf:getPOImpact($database,$flowDesign, $traverseImpactTree)
                     )
                  else ()
                  
               }
            </usedBy>
    return $impactedObjects
};



(:~
 : Function generates Impact for Connection, finds all objects refering to services and process objects provided by the connection/connector
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $fdesignDoc as node()?  Design Object to check impact for
 : @param $traverseImpactTree as xs:boolean When  set to true() then the function will travverse the dependencies 
 :        all the way to top level process/ guide, otherwise it will only scan direct first level dependencies    
 : @return Connection UsedBy in the workspace
 :)
declare function imf:getConnectionImpact (
   $database as document-node()*, 
   $designDoc as node()?, 
   $traverseImpactTree as xs:boolean
) as node()*  {
   let $name   := $designDoc/rep:Name/text()
   let $guid   := $designDoc/rep:GUID/text()
   let $displayName := $designDoc/rep:DisplayName/text() 

   let $impactedFlows:= for $flow in $database//rep:Item/rep:Entry[(*:avosScreenflow|*:process|*:taskflow)]
      let $documentUri := db:path($flow)
      let $flowDesign  := root($flow)/*/rep:Item
      let $itemName    := $flowDesign/rep:Name/text()
      let $itemGuid    := $flowDesign/rep:GUID/text()
      let $designType  := $flowDesign/rep:MimeType/text()
      let $itemDisplayName := $flowDesign/rep:DisplayName/text()
      
      let $distinctFields := distinct-values(
                           for $field in $flowDesign//(*:field|*:parameter)[@type="reference" or @type="objectList"]
                           let $referenceTo  := $field/*:options/*:option[@name="referenceTo"]/text()
                           return
                           $referenceTo)
      let $fieldDeps := for $field in $distinctFields
                           let $connectionName  := substring-before($field, ":")
                        where $name = $connectionName
                        return 
                        <usedBy 
                           displayName="{$itemDisplayName}" name="{$itemName}" guid="{$itemGuid}"
                           dependsOn="{$field}" dependsOndisplayName="{$displayName}" dependsOnGuid="{$guid}" 
                           referenceType="Process Object" designType="{$designType}"
                           docUri="{$documentUri}">
                           {
                              if ($traverseImpactTree ) then 
                                 imf:getSubflowImpact($database,imf:getDesignByGuid($database,$itemGuid), $traverseImpactTree )
                              else ()
                           }
                        </usedBy>
      let $serviceDeps := for $service in $flowDesign//*:service
                              let $operationName := $service/*:serviceName/text()
                              let $serviceName   := substring-before($operationName, ":")
                           where
                              $serviceName = $name
                           return 
                           <usedBy 
                              displayName="{$itemDisplayName}" name="{$itemName}" guid="{$itemGuid}"
                              dependsOn="{$operationName}" dependsOndisplayName="{$displayName}" dependsOnGuid="{$guid}" 
                              referenceType="Service" designType="{$designType}"
                              docUri="{$documentUri}">
                              {
                                 if ($traverseImpactTree ) then 
                                    imf:getSubflowImpact($database,imf:getDesignByGuid($database,$itemGuid), $traverseImpactTree )
                                 else ()
                              }
                           </usedBy>
      let $createDeps := for $object in $flowDesign//*:create/*:entityName/text()
                           let $conName := substring-before($object,":")
                           where
                              $conName = $name
                           return
                           <usedBy 
                              displayName="{$itemDisplayName}" name="{$itemName}" guid="{$itemGuid}"
                              dependsOn="{$object}" dependsOndisplayName="{$displayName}" dependsOnGuid="{$guid}" 
                              referenceType="Connection:Create" designType="{$designType}"
                              docUri="{$documentUri}">
                              {
                                 if ($traverseImpactTree ) then 
                                    imf:getSubflowImpact($database,imf:getDesignByGuid($database,$itemGuid), $traverseImpactTree )
                                 else ()
                              }
                           </usedBy>
      
      where not(empty($fieldDeps)) or not(empty($serviceDeps)) or not(empty($createDeps))
      return
            (
            $fieldDeps
            ,$serviceDeps
            ,$createDeps
            )
   return $impactedFlows
};

(:~
 : Function generates Impact for Connector, it finds related connections and finds all objects refering to services and process objects provided by the connection/connector
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $fdesignDoc as node()?  Design Object to check impact for
 : @param $traverseImpactTree as xs:boolean When  set to true() then the function will travverse the dependencies 
 :        all the way to top level process/ guide, otherwise it will only scan direct first level dependencies    
 : @return Connection UsedBy in the workspace
 :)
declare function imf:getConnectorImpact (
   $database as document-node()*, 
   $designDoc as node()?,
   $traverseImpactTree as xs:boolean
) as node()* {
    let $name   := $designDoc/rep:Name/text()
    let $guid   := $designDoc/rep:GUID/text()
    let $displayName := $designDoc/rep:DisplayName/text() 
    let $design := $designDoc[1]/rep:Entry/*
    let $uuid   := string($design/@uuid)
    let $impactedConnections := for $svc in $database//rep:Item/rep:Entry[*:connection/*:businessConnector/@uuid = $uuid]
         let $documentUri := db:path($svc)
         let $connection  := root($svc)/*/rep:Item
         let $flowDesign  := root($svc)/*/rep:Item
         let $itemName    := $flowDesign/rep:Name/text()
         let $itemGuid    := $flowDesign/rep:GUID/text()
         let $designType  := $flowDesign/rep:MimeType/text()
         let $itemDisplayName := $flowDesign/rep:DisplayName/text()
         return
         <usedBy 
               displayName="{$itemDisplayName}" name="{$itemName}" guid="{$itemGuid}" 
               dependsOn="{$name}" dependsOndisplayName="{$displayName}" dependsOnGuid="{$guid}" 
               referenceType="Connector" designType="{$designType}"
               docUri="{$documentUri}">
               {imf:getConnectionImpact($database,$connection,$traverseImpactTree )}
         </usedBy>
    return $impactedConnections
};


(:~
 : Function generates Impact (Used By) analysis data for IPD Process Object Designs
 :
 : @param $database as document-node()* PID Document Collection repository with file descriptors
 : @param $fdesignDoc as node()?  Design Object to check impact for
 : @param $traverseImpactTree as xs:boolean When  set to true() then the function will travverse the dependencies 
 :        all the way to top level process/guide, otherwise it will only scan direct first level dependencies     
 : @return Object impact report
 :)
declare function imf:getObjectImpact (
   $database as document-node()*, 
   $designDoc as node()?, 
   $traverseImpactTree as xs:boolean
) as node()* {
    let $name   := $designDoc/rep:Name/text()
    let $guid   := $designDoc/rep:GUID/text()
    let $design := $designDoc[1]/rep:Entry/*
    let $displayName := $designDoc/rep:DisplayName/text() 
    let $impactedDesigns := typeswitch ($design)
            case element(svc:businessConnector) return imf:getConnectorImpact($database,$designDoc,$traverseImpactTree)
            case element(con:connection)  return imf:getConnectionImpact($database,$designDoc,$traverseImpactTree)
            case element(hen:processObject) return imf:getPOImpact($database,$designDoc,$traverseImpactTree)
            case element(sfd:process)  return imf:getSubflowImpact($database,$designDoc,$traverseImpactTree)
            default return ()
    return 
    <impactReport name="{$name}" displayName="{$displayName}" guid="{$guid}">
        {
        $impactedDesigns
        }
    </impactReport>
};