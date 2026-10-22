`authz.rego` and `data.json` here are a made-up example policy for the `{action, groups}`
input that `c3g_require_authz()` sends. `test-authz.R` runs `c3g_require_authz()` against a
real `opa run --server` loaded with it.

Group names and actions are deliberately generic: this repo is public, and real policies and
group names stay in the private `c3g-opa-policies` repo. Don't copy a real app's policy here.
