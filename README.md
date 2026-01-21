Simple preconfigured build system for [REDACTED] os apps.

1. Run `setup` (or manually export the path to this repo to `REDBUILD` and add the `utils` folder to `PATH`"
2. If starting a new project, initialize the project by running `redinit` in the new project's directory.
3. Create a `build.redb` `cred` file in your project to configure your build process \*, or the equivalent `build.c` file. 
4. Run `redc` (or `redc c` to skip the `.redb` compilation) to configure your build, which will generate a `build` file, which you can use to run builds of your project \*\*

\*  Due to the rapidly changing nature of the project, adding examples here is impractical. See usage in https://github.com/differrari/cred
\*\* redc requires use of the cred compiler. Which uses this same build system. The compiler includes a precompiled build.c to skip this process, so a first version of the cred compiler can be built. 

TODOs:
- Get rid of hardcoded .build once language is JIT or interpreted
- Bring back library support.
- Bear
