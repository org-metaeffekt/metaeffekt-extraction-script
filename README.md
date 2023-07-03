# metaeffekt-extraction-script
Scripts for extracting detailed information from a host.

The script should only be run in non-production environments, as it collects a
significant amount of data and is somewhat heavy computationally.

The script aggregates data in ``/var/opt/metaeffekt/extraction/analysis``.

For aggregating lower-profile inventory data, possibly from production environments,
look at the [{metæffekt} inventory script](https://github.com/org-metaeffekt/metaeffekt-inventory-script).

![An illustration of how the script may be integrated](doc/overview.png)

This figure illustrates how the script can be applied in a staged environment.

## Running the script
### Optional Arguments:
- \-t \<machineTag\> : Adds a tag to be stored with the analysis.
  This exists so that a custom Identifier can be set.
  It should consist only of characters as allowed for base64 encoded strings
  (alphanumeric plus . and /).
- \-e \<pattern\> : Exclude the path denoted by the pattern.
  The pattern follows the rules that the command `find` uses for its `-path` options (which aren't always intuitive).
  <br>
  For directories without overly odd characters, however, it works something like this: <br>
  `-e "/do/not/traverse/this/directory" -e "/other/patterns*/to/exclude"` <br>
  Take care to not include trailing slashes in your exclude paths, as `find` doesn't cope with it very well.
