# c3g.shiny.authz

Authentication/authorization helpers for C3G R Shiny apps sitting behind oauth2-proxy. See
[web-app-template](https://github.com/c3g/web-app-template)'s `for-app-developers.md`
(`#real-tier-3-for-shiny`) and `README.md` for where this fits among the authentication/
authorization tiers.

Two independent layers, so an app only takes on what it needs:

| Layer | Function | Does | Needs OPA |
|---|---|---|---|
| Tier 2, cosmetic | `c3g_groups()` | Reads and parses the forwarded-groups header from `session$request`, once, correctly. | No |
| Tier 3, real authz | `c3g_require_authz()` | Called at the top of a guarded `observeEvent()`/`downloadHandler()`. Builds an `{action, groups}` input, calls the app's local OPA sidecar, fails closed. | Yes |

**Status: working, and verified end to end.** `c3g_require_authz()` is tested against a real
OPA server in CI, and checked inside a running Shiny app driven by a real browser (allowed,
denied, no groups, OPA down). See [CLAUDE.md](CLAUDE.md) for how to run both.

**Pre-1.0:** the API may change between minor versions until a first app has adopted it.

No OIDC-client layer is planned for this package — oauth2-proxy stays in front regardless of
tier, since Shiny has no non-browser client the way `pt_cli` justifies one for
`project_tracking` (which is meant to use `c3g-oidc` instead). That keeps this package doing one thing.

## Install

```r
remotes::install_github("c3g/c3g.shiny.authz@v0.1.0")
```

## Usage

### Tier 2, cosmetic UI only

```r
server <- function(input, output, session) {
  groups <- c3g_groups(session)
  if ("admins" %in% groups) {
    # show an admin-only tab, button, etc. -- this is UI polish, not a security boundary;
    # oauth2-proxy already decided who gets this far before Shiny ever saw the request.
  }
}
```

### Tier 3, real per-action authorization

```r
server <- function(input, output, session) {
  observeEvent(input$export_btn, {
    # stops here, notifies the user, on deny
    c3g_require_authz("export_dataset", session, policy_path = "my_app/authz/allow")
    # ... proceed with the export
  })
}
```

`policy_path` names the app's rule in `c3g-opa-policies`: the Rego package and rule with dots
replaced by slashes (package `my_app.authz`, rule `allow` → `"my_app/authz/allow"`). It has no
default, since every app's policy lives under its own package.

By default, `c3g_require_authz()` calls the OPA sidecar at the `C3G_OPA_URL` environment
variable, falling back to `http://127.0.0.1:8181` -- OPA runs in the app's own podman pod, per
`web-app-template`'s deployment docs, so the app reaches it on the pod's loopback. It gives up
after 2 seconds (`timeout`) and denies: a Shiny process is single-threaded, so a hung OPA call
would otherwise freeze the app for every user.

A complete example app is in `inst/examples/authz-demo/`.
