Simple preconfigured build system for [REDACTED] os apps.

1. Run `setup` (or manually export the path to this repo's `Makefile` to `REDMAKE` and add the folder to `PATH`"
2. If starting a new project, initialize the project by running `redinit` in the new project's directory.
3. Ensure the dependencies in the project's config.mk are correct
4. To run a project, call `redc` from the project's directory.

TODOs:
- Adding support for more project types, like binaries and terminal apps
- Add script to copy the makefile into the project, to make it standalone or allow further customization
- More programming languages(?)
