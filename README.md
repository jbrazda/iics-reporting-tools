# IICS Design Reporting Tools

This project contains set of Tools to provide reporting on Exported asses packages from Informatica IICS

![Designs Report](doc/images/IICS_DesignsReport.png "Designs Report")

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

## Installation of the Tool

### Pre-requisites

- JAVA JRE 1.8 or newer
- Apache Ant 1.9 or newer

## Install Steps

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

# Planned improvements in upcoming releases

- improve documentation
- improve dependency tree rendering
- provide graphical view of dependency graph Design objects
- provide page to upload the exported package to create DB
- provide script targets to incorporate this tool during Designs Migration from different Stage Environments
