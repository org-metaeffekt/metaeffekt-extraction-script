# metaeffekt-extraction-script

Scripts for extracting detailed information from a host.

The script should only be run in non-production environments, as it collects a
significant amount of data and is somewhat heavy computationally.

The script aggregates data in ``/var/opt/metaeffekt/extraction/analysis``.

For aggregating lower-profile inventory data, possibly from production environments,
look at the [{metæffekt} inventory script](https://github.com/org-metaeffekt/metaeffekt-inventory-script).

![An illustration of how the script may be integrated](doc/overview.png)

This figure illustrates how the script can be applied in a staged environment.

## Linux

### Running the script

#### Optional Arguments:

- `-t <machineTag>` : Adds a tag to be stored with the analysis.
  This exists so that a custom Identifier can be set.
  It should consist only of characters as allowed for base64 encoded strings
  (alphanumeric plus . and /).
- `-e <pattern>` : Exclude the path denoted by the pattern.
  The pattern follows the rules that the command `find` uses for its `-path` options (which aren't always intuitive).
  <br>
  For directories without overly odd characters, however, it works something like this:  
  `-e "/do/not/traverse/this/directory" -e "/other/patterns*/to/exclude"`  
  Take care to not include trailing slashes in your exclude paths, as `find` doesn't cope with it very well.

## Windows

The [scripts-windows](scripts-windows) folder contains multiple PowerShell scripts that are all required to run the
extraction script on Windows. Only the [windows-extractor.ps1](scripts-windows/windows-extractor.ps1) script needs to
be executed. The other scripts are called by the main script.

### Running the script

```powershell
.\windows-extractor.ps1 -OutDir result
```

#### Optional arguments:

- `-FsScanBaseDir` : The base directory for the filesystem scan. This is the directory that will be scanned for files
  and directories. The default value is `(Get-WmiObject Win32_OperatingSystem).SystemDrive` or if that fails,  `C:\`.
- `FsScanExcludeDirs` : A string consisting of directories split by `;;;` to exclude from scanning into during the
  file system scan: `"dir1;;;dir2;;;dir3"`

### Result processing

The results can be converted into an inventory of software components using the `extract-windows-inventory` goal of
the `org.metaeffekt.core` : `ae-inventory-maven-plugin` plugin.

## License

- The files in the [scripts-windows](scripts-windows) are licensed under the [MIT license](LICENSE.MIT).
