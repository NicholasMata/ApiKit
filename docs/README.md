# Documentation

ApiKit follows CalendarKit's DocC setup: each library target has a documentation
catalog, and the three archives are merged into one site with unified navigation
and search. The package landing page links to `ApiKit`, `ApiKit_OAuth`, and
`ApiKit_Google`, matching their Swift import names.

## Build

Use Xcode 26 or later, with the iOS SDK and command-line tools selected:

```sh
zsh ./docs/build-docc-site.sh
```

The script runs `xcodebuild docbuild` for all three library schemes, treats DocC
warnings as errors, merges the archives, and prepares GitHub Pages output:

- Combined archive: `.build/docc/ApiKit.doccarchive`
- Static site: `.build/docc/site`

Build output and dependency caches stay under the ignored `.build` directory.
The script can be invoked from any working directory. Package dependencies may
need downloading on the first build. No documentation plugin is added to the
library's package dependencies.

## Preview

For a local preview, build without a hosting base path and serve the output over
HTTP. For example, with Node.js installed:

```sh
DOCC_HOSTING_BASE_PATH="" zsh ./docs/build-docc-site.sh
npx --yes serve .build/docc/site --listen 8080
```

Open <http://localhost:8080/documentation/>. Stop the server with Control-C.
The preview server is optional and is not a dependency of ApiKit. `docc preview`
expects a source catalog; it does not serve the merged compiled archive.

The default hosting path comes from `GITHUB_REPOSITORY`, or the repository's
directory name locally. Set `DOCC_HOSTING_BASE_PATH` explicitly to override it.

## Publish

In GitHub, set **Settings → Pages → Build and deployment → Source** to
**GitHub Actions**. The `Deploy DocC` workflow publishes changes on `main` or
when manually dispatched. Pull requests build the same site without deploying.
The expected project URL is:

<https://nicholasmata.github.io/ApiKit/documentation/>

Adding the workflow does not enable Pages or publish a site by itself.

## Edit

- Core: `ApiKit/Sources/ApiKit.docc`
- OAuth: `ApiKit-OAuth/Sources/ApiKit-OAuth.docc`
- Google: `ApiKit-Google/Sources/ApiKit-Google.docc`

Update guides alongside API changes, and use DocC symbol links for public types.
Build all modules before submitting a change so broken links and malformed
catalog content are caught. Keep OAuth examples aligned with the protocol-based
provider and the `beginSession(with:)` / `endSession()` lifecycle.
