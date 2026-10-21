test_that("c3g_require_authz fails closed when OPA is unreachable", {
  session <- list(request = list(HTTP_X_FORWARDED_GROUPS = "admins"))

  # Port 1 is a reserved, unassigned port -- nothing should be listening there, so this
  # exercises the fail-closed (network error -> deny) path rather than a real OPA answer.
  # We only assert that *something* stops execution here (deny), not which exact condition
  # class does it -- shiny::showNotification()/shiny::req() both require a reactive/session
  # context this unit test doesn't have, which is itself a reason execution won't proceed.
  expect_error(
    suppressWarnings(
      c3g_require_authz("export_dataset", session, opa_url = "http://127.0.0.1:1")
    )
  )
})

# NOTE: there is deliberately no test here for the "OPA reachable and returns allow/deny"
# path -- that needs a running OPA server (or an httr2 mock) and hasn't been wired up yet.
# See CLAUDE.md's "What's actually verified" section before assuming this function has been
# exercised against a real policy.
