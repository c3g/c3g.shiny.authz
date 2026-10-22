package example_app.authz

# Input shape sent by c3g_require_authz():
# {
#   "action": "export_dataset",
#   "groups": ["example-editors"]
# }
#
# Which groups may perform which action lives in data.actions (see data.json).

default allow := false

allow if {
	some group in data.actions[input.action]
	group in input.groups
}
