# WSUS Maintenance

This repo does not provide a software package that can be installed or run. It is a collection of ideas of how to improve WSUS. These ideas might be bad, don't run any of these scripts unless you are sure.

If you know more about WSUS or SQL than I do and know how to improve one of these scripts or have any other ideas please let me know.

## Microsoft documentation

* [Best Practices](https://docs.microsoft.com/en-US/troubleshoot/mem/configmgr/windows-server-update-services-best-practices)
* [WSUS Maintenance Guide](https://docs.microsoft.com/en-us/troubleshoot/mem/configmgr/wsus-maintenance-guide)
* [Reindex Database](https://docs.microsoft.com/en-us/troubleshoot/mem/configmgr/reindex-the-wsus-database)

## General Strategy

* Decline all driver updates older than 1 year as these should have been applied already
* Delete all driver updates older than 2 years
* Decline all non English updates as unused
* Decline ARM updates as unused
* Decline x86 updates as unused
* Decline all superseded updates as the new (probably cumulative) version can be installed
* Reindex the WSUS database
* Only approve updates that are actually required

## Initial configuration

* Only select products that actually appear in the environment. Windows 7 and 8 should no longer exist.
* Configure the recommended IIS settings from the best practices. Microsoft recommend unlimited Memory on the IIS pool. This seems like a bad idea if using SQL or WID on the same server as IIS.
* Install the custom indexes from the WSUS maintenance guide
* Reindex after initial synchronisation
* Sync daily at close of play

## WID connection
DO NOT ALTER THE SCHEMA IN ANY WAY WHEN USING WID. DO NOT CREATE DIAGRAMING OBJECTS OR ANY OTHER NEW OBJECTS

SSMS needs to be open as an Admin

Database Engine 
```
\\.\pipe\MICROSOFT##WID\tsql\query
```

## Links

* [CLR Types](http://go.microsoft.com/fwlink/?LinkID=239644&clcid=0x409)
* [Report Viewer](https://www.microsoft.com/en-us/download/details.aspx?id=35747)


## Observations

* SUSDB should be on solid state storage