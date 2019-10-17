# IICS Design Reporting Tools

This project contains set of tools to provide reporting on exported assets packages from Informatica IICS
Tool  is Installed and deployed by Apache Ant Script and set of XQuery modules based web application deployed on BaseX Database HTTP Server

![Designs Report](doc/images/IICS_DesignsReport.png "Designs Report")

<!-- TOC -->

- [IICS Design Reporting Tools](#iics-design-reporting-tools)
    - [Features](#features)
    - [Installation of the Tool](#installation-of-the-tool)
        - [Pre-requisites](#pre-requisites)
    - [Install Steps](#install-steps)
    - [Create Exported Objects Database](#create-exported-objects-database)
    - [Ant Script main Properties File](#ant-script-main-properties-file)
    - [Target basex.create.db](#target-basexcreatedb)
    - [Parameters](#parameters)
    - [Example Use in Ant Script](#example-use-in-ant-script)
    - [Target basex.create.db](#target-basexcreatedb-1)
    - [Parameters](#parameters-1)
    - [Example Use in Ant Script](#example-use-in-ant-script-1)

<!-- /TOC -->

## Features

- Detailed IICS exported asset reports
- Basic designs statistics
- Dependency and Impact analysis
- Detailed Design report
- Supported IICS object types
    - Service Connectors
    - Connection
    - Process Objects
    - Processes
    - Guides
    - Task Flows
- Support for MacOS, Windows, Linux

This tool is developed as web application on top of BaseX XQuery Database and HTTP Server provided by BaseX
Tool provides set of scripts to download, install and deploy custom application to BaseX Server.

It can be plugged-in into the automated Build process to Publish And  make online reports available as shown in the
[Fault Alert Service Implementation](https://github.com/jbrazda/icai-fault-alert-service)

## Installation of the Tool

### Pre-requisites

- JAVA JRE 1.8 or newer
- Apache Ant 1.9 or newer

## Install Steps

Simplest method is to follow these steps

1. Clone this repository
2. Run ant target `ant install`

You can also follow  these steps

1. Clone this repository
2. Run ant target `ant configure`
3. Run ant target `ant basex.install`
4. Run ant target `ant basex.deploy.iics`
5. Run ant target `ant basex.run`
6. Create Database from IICS Exported Package Zip file
7. Go tp Go to [http://localhost:8984/iics](http://localhost:8984/iics)

## Create Exported Objects Database

You can import unmodified  Export package to BaseX Databases  several ways

Using a command line as shown below or using BaseX Gui Application.

```shell
basex -c "CREATE DATABASE [DB_NAME] [PATH TO EXPORTED zip]"
```

Example

```shell
basex -c "CREATE DATABASE IICS_ICLAB_SRC_2019_07_08 /Users/jbrazda/git/icrt_common/com.informatica.ipd/target/drop/IICS_ICLAB_SRC_2019_07_08.zip"
```

Ant Target Parameters and Examples

```text
Buildfile: /Users/jbrazda/git/iics-reporting-tools/build.xml

            IICS Reportinmg Tools Build Script

Main targets:

 basex.create.db           Create new BaseX Database from Source file, archive or directory
 basex.deploy.iics         Deploys IICS Reporting pages to BaseX Http Server to basex_home/webapp/iics
 basex.download            Download BaseX
 basex.drop.db             Drop Existing BaseX DB by name
 basex.install             Uninstalls BaseX DB and Tools
 basex.run                 Run BaseX HTTP Server
 basex.sample.db.create    Create Sample DEMO_DB
 basex.sample.db.drop      Drop Sample DEMO_DB
 basex.stop                Stop BaseX HTTP Server
 basex.uninstall           Stops and Uninstall BaseX Server and Tools
 configure                 Configure Reporting Tool
 help                      help - describes how to use this script
 install                   Installs BaseX Tools, Deploys IICS Reporting App and runs BaseX HTTP Server
 project.update.from.basex  Updates iics reporting modules and sources from basex http server webapp/iics dir
```

## Ant Script main Properties File

```properties
# Tool Defaults
default.iics.reporting.basex.home=/opt/java/library/basex
default.iics.reporting.downloads.dir=${user.home}/Downloads
iics.reporting.config=${user.home}/.iics.reporting.properties
iics.reporting.sample.file=FaultAlertService_InitialInstall_All_Designs.zip
iics.reporting.sample.url=https://raw.githubusercontent.com/jbrazda/icai-fault-alert-service/master/dist/FaultAlertService_InitialInstall_All_Designs.zip


# BaseX Distribution Properties
basex.download.file=BaseX924.zip
basex.download.url=http://files.basex.org/releases/9.2.4/${basex.download.file}
basex.http.base_url=http://localhost:8984

basex.java_home=/Library/Java/JavaVirtualMachines/jdk1.8.0_162.jdk/Contents/Home

## Configure your IICS org region. For example, us, eu, ap
iics.region=us
```

## Target basex.create.db

This target Will create New database Typically from zip archive as a part of the build process

## Parameters

| Property               | Description                                                                                                                         | Example Value                               |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| basex.create.db.name   | Database name                                                                                                                       | FaultAlertService_iclab-dev_all_designs     |
| basex.create.db.source | Database source Can be Directory containing XML files, single XML File or zip archive which is the most common scenario in our case | FaultAlertService_iclab-dev_all_designs.zip |
| env.info.displayed     | Suppress print of environment Info                                                                                                  | true                                        |

## Example Use in Ant Script

You can run the tools from a parent Ant script using an `ant` target Assuming that the `${tools.package.reporting}` is pointing to `build.xml` file of this project

```xml
<ant antfile="${tools.package.reporting}" target="basex.create.db" inheritall="false" inheritrefs="false">
    <property name="basex.create.db.name" value="${release.package.label}"/>
    <property name="basex.create.db.source" location="${iics.import.dir}/${release.package.label}.zip"/>
    <property name="env.info.displayed" value="true"/>
</ant>
```

## Target basex.create.db

This target Will create New database Typically from zip archive as a part of the build process

## Parameters

| Property           | Description                        | Example Value                           |
| ------------------ | ---------------------------------- | --------------------------------------- |
| basex.drop.db.name | Database name                      | FaultAlertService_iclab-dev_all_designs |
| env.info.displayed | Suppress print of environment Info | true                                    |

## Example Use in Ant Script

```xml
<ant antfile="${tools.package.reporting}" target="basex.drop.db" inheritall="false" inheritrefs="false">
    <property name="basex.drop.db.name" value="DB_NAME"/>
    <property name="env.info.displayed" value="true"/>
</ant>
```
