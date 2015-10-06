# Introduction #

A FileNode represents its state as a file.  Its updater is an executable command, such as a shell script.

# Details #

A FileNode's updater is called in one of two ways, depending on whether the p:state was explicitly set in the pipeline definition.  If p:state **was** set, the updater is called as follows:
> _updaterCmd_ _stateFile_ _inputFiles..._
If p:state was **not** set, the updater is called as follows, writing its new state to stdout:
> _updaterCmd_ _inputFiles..._ > _stateFile_

In either case:
  * **_updaterCmd_** is the command specified by p:updater, defaulting to the name of the node, possibly with a recognized file extension added.
  * **_inputFiles..._** are files representing the states of the nodes inputs (if any).
  * **_stateFile_** is the file that represents this node's state.

The first form (used when p:state is explicitly specified) allows the _updaterCmd_ to dynamically decide whether to modify its _stateFile_.  The second form requires _updaterCmd_ to write a new state to stdout every time it is invoked.

# Environment Variables #

Before the _updaterCmd_ is invoked, the following environment variables are set:
  * **$THIS\_URI** is set to the current node's URI.
  * **$QUERY\_STRING** is set to the query string of this node's latest GET request, as received from one of the node's downstream output nodes or an anonymous requester.
  * **$QUERY\_STRINGS** is set to the space-separated list of $QUERY\_STRINGs received from all of the node's downstream nodes.  **TODO: Does it include the $QUERY\_STRING of an anonymous requester?**

In addition to the above, an environment variable is set for each URL **query parameter** that is passed to a FileNode when its output is requested, provided that the query parameter matches the following perl regular expression: `^[a-z][a-zA-Z0-9_]*$` .

Thus, if FileNode :foo is invoked as `http://localhost/node/foo?patient=43&domain=demographics&Doctor=Clark`, the following additional environment variables will be set prior to invoking the updater:
```
export patient=43
export domain=demographics
```
No environment variable will be set for the `Doctor` query parameter, because it starts with an upper case letter.