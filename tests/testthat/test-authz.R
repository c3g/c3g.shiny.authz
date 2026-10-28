# A stand-in for a Shiny session: carries the forwarded-groups header like oauth2-proxy would,
# and records notifications instead of sending them to a browser.
fake_session <- function(groups_header = NULL) {
  sent <- new.env()
  sent$notifications <- list()
  list(
    request = list(HTTP_X_FORWARDED_GROUPS = groups_header),
    sendNotification = function(type, message) {
      sent$notifications[[length(sent$notifications) + 1]] <- message
    },
    sent = sent
  )
}

expect_denied <- function(session, ...) {
  expect_error(c3g_require_authz(session = session, ...), class = "shiny.silent.error")
  expect_length(session$sent$notifications, 1)
  expect_equal(session$sent$notifications[[1]]$type, "error")
}

POLICY <- "example_app/authz/allow"

# --- Without OPA -------------------------------------------------------------------------------

test_that("a missing or empty policy_path is a loud error, not a silent deny", {
  session <- fake_session("example-editors")
  expect_error(c3g_require_authz("export_dataset", session), "policy_path")
  expect_error(c3g_require_authz("export_dataset", session, policy_path = ""), "policy_path")
  expect_error(c3g_require_authz("export_dataset", session, policy_path = "/"), "policy_path")
  expect_length(session$sent$notifications, 0)
})

test_that("c3g_require_authz fails closed when OPA is unreachable", {
  # Port 1 is reserved and unassigned -- nothing listens there, so the connection is refused.
  expect_denied(fake_session("example-editors"), action = "export_dataset",
                policy_path = POLICY, opa_url = "http://127.0.0.1:1")
})

test_that("c3g_require_authz fails closed, and quickly, when OPA never answers", {
  # A listening socket that never accepts: the TCP connection opens, the request goes out,
  # and no response ever comes back -- the same as a hung OPA.
  port <- free_port()
  listener <- serverSocket(port)
  on.exit(close(listener), add = TRUE)

  started <- Sys.time()
  expect_denied(fake_session("example-editors"), action = "export_dataset",
                policy_path = POLICY, opa_url = paste0("http://127.0.0.1:", port),
                timeout = 0.5)
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 5)
})

# --- Against a real OPA server -----------------------------------------------------------------

test_that("allows an action the user's group may perform", {
  opa <- local_opa_server()
  session <- fake_session("example-viewers, example-editors")
  expect_true(c3g_require_authz("export_dataset", session, POLICY, opa_url = opa))
  expect_length(session$sent$notifications, 0)
})

test_that("denies an action the user's groups may not perform", {
  opa <- local_opa_server()
  expect_denied(fake_session("example-viewers"), action = "export_dataset",
                policy_path = POLICY, opa_url = opa)
})

test_that("denies when the forwarded-groups header is absent", {
  opa <- local_opa_server()
  expect_denied(fake_session(NULL), action = "view_dataset", policy_path = POLICY,
                opa_url = opa)
})

test_that("denies an action the policy doesn't know", {
  opa <- local_opa_server()
  expect_denied(fake_session("example-editors"), action = "delete_everything",
                policy_path = POLICY, opa_url = opa)
})

test_that("denies when policy_path names a rule that doesn't exist", {
  opa <- local_opa_server()
  expect_denied(fake_session("example-editors"), action = "export_dataset",
                policy_path = "other_app/authz/allow", opa_url = opa)
})

test_that("tolerates leading and trailing slashes in policy_path", {
  opa <- local_opa_server()
  session <- fake_session("example-editors")
  expect_true(c3g_require_authz("export_dataset", session, "/example_app/authz/allow/",
                                opa_url = opa))
})

test_that("opa_url defaults to the OPA sidecar in the app's own pod", {
  withr::local_envvar(C3G_OPA_URL = NA)
  expect_equal(eval(formals(c3g_require_authz)$opa_url), "http://127.0.0.1:8181")
  withr::local_envvar(C3G_OPA_URL = "http://opa.example:9999")
  expect_equal(eval(formals(c3g_require_authz)$opa_url), "http://opa.example:9999")
})
