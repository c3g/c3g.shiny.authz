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

**Status: early scaffold.** `c3g_groups()` is a real, working, tested implementation.
`c3g_require_authz()` is also implemented (it's a small HTTP call to a per-app OPA sidecar),
but hasn't been exercised end-to-end against a real OPA policy or inside a running Shiny app
yet — see [CLAUDE.md](CLAUDE.md).

No OIDC-client layer is planned for this package — oauth2-proxy stays in front regardless of
tier, since Shiny has no non-browser client the way `pt_cli` justifies one for
`project_tracking` (which is meant to use `c3g-oidc` instead). That keeps this package doing one thing.

## Install

```r
# once published:
remotes::install_github("c3g/c3g.shiny.authz")
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
    c3g_require_authz("export_dataset", session)  # stops here, notifies the user, on deny
    # ... proceed with the export
  })
}
```

By default, `c3g_require_authz()` calls the OPA sidecar at the `C3G_OPA_URL` environment
variable, falling back to `http://10.0.2.2:8181` -- the host-loopback address used throughout
`web-app-template`'s deployment docs for reaching a container's local sidecar.
