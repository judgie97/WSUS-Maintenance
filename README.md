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

## Initial configuration

* Only select products that actually appear in the environment. Windows 7 and 8 should no longer exist.
* Configure the recommended IIS settings from the best practices
* Install the custom indexes from the WSUS maintenance guide
* Reindex after initial synchronisation
* Sync daily at close of play