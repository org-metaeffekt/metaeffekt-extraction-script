# metaeffekt-extraction-script
Scripts for extracting detailed information from a host.

The script should only be utilized in non-production environment as it collects 
significant amount of data and imposes load on the CPU.

The script aggregates data in ``/var/opt/metaeffekt/extraction/analysis``.

For aggregating inventory data use the {metæffekt} inventory script.

![Alt](doc/overview.png)

The figure illustrates how the script can be applied in a staged environment.

For aggregating low-profile inventory data in a production environment use the 
{metæffekt} inventory script.

## Running the script
### Optional Arguments:
- \-t \<machineTag\> : Adds a tag to be stored with the analysis.
  This exists so that a custom Identifier can be set.
  It should consist only of characters as allowed for base64 encoded strings
  (alphanumeric plus . and /).
- \-e \<pattern\> : Exclude the path denoted by the pattern.
  The pattern follows the rules `find` uses for -path options (which isn't always intuitive). <br>
  For directories without overly odd characters however it works something like this: <br>
  `-e "/do/not/traverse/this/directory" -e "/other/patterns*/to/exclude"` <br>
  Take care to not include trailing slashes as `find` doesn't like that.
