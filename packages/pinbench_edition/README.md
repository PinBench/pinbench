# pinbench_edition

The edition a PinBench build runs as — here, none.

`createEdition()` returns null, so a build from this repository is the full
local app: canvas, simulator, code editor and every part, working on local
workspaces with no account.

Accounts, cloud projects and the other hosted features belong to PinBench's
hosted builds, which replace this package with their own implementation of
`Edition` (see `package:pinbench_edition_api`). Nothing else in the app changes
between the two.
