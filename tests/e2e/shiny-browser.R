# End-to-end check of c3g.shiny.authz inside a real Shiny app, driven by a real browser.
#
# Starts `opa run --server` with the example policy from tests/testthat/fixtures/example_app/,
# runs inst/examples/authz-demo/ against it behind groups_proxy.py (a stand-in for
# oauth2-proxy), and uses headless Chrome (chromote) to click its buttons as users in different
# groups.
#
# The proxy is needed because Shiny reads session$request from the WebSocket handshake, and a
# browser can't add its own headers to that. oauth2-proxy sets X-Forwarded-Groups on every
# request from its session cookie; groups_proxy.py does the same from an `e2e_groups` cookie.
#
# Needs: the `opa` CLI, Google Chrome, `uv` (runs the proxy with aiohttp), and the processx,
# callr and chromote packages. Run from the package root:  Rscript tests/e2e/shiny-browser.R

stopifnot(file.exists("DESCRIPTION"))
for (pkg in c("processx", "callr", "chromote")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("install the ", pkg, " package first")
}
for (cli in c("opa", "uv")) {
  if (!nzchar(Sys.which(cli))) stop("the ", cli, " CLI must be on PATH")
}

free_port <- function() {
  repeat {
    port <- sample(20000:60000, 1)
    con <- suppressWarnings(tryCatch(
      socketConnection("127.0.0.1", port, open = "r+", blocking = TRUE, timeout = 0.2),
      error = function(e) NULL
    ))
    if (is.null(con)) return(port)
    close(con)
  }
}

wait_for <- function(what, fn, timeout = 15) {
  deadline <- Sys.time() + timeout
  repeat {
    value <- tryCatch(fn(), error = function(e) FALSE)
    if (isTRUE(value)) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("timed out waiting for ", what)
    Sys.sleep(0.2)
  }
}

http_ok <- function(url) {
  con <- url(url)
  on.exit(close(con))
  length(suppressWarnings(readLines(con, warn = FALSE))) > 0
}

# Install this checkout into a temporary library, so the app's library() call loads it.
lib <- tempfile("lib")
dir.create(lib)
system2(file.path(R.home("bin"), "R"),
        c("CMD", "INSTALL", "--no-test-load", paste0("--library=", lib), "."),
        stdout = FALSE, stderr = FALSE)
stopifnot(dir.exists(file.path(lib, "c3g.shiny.authz")))

opa_port <- free_port()
opa_url <- paste0("http://127.0.0.1:", opa_port)
opa <- processx::process$new(
  "opa", c("run", "--server", "--addr", paste0("127.0.0.1:", opa_port),
           file.path("tests", "testthat", "fixtures", "example_app"))
)
wait_for("OPA", function() http_ok(paste0(opa_url, "/health")))

app_port <- free_port()
app_url <- paste0("http://127.0.0.1:", app_port)
app <- callr::r_bg(
  function(lib, port) {
    .libPaths(c(lib, .libPaths()))
    shiny::runApp(system.file("examples/authz-demo", package = "c3g.shiny.authz"),
                  port = port, launch.browser = FALSE)
  },
  args = list(lib = lib, port = app_port),
  env = c(callr::rcmd_safe_env(), C3G_OPA_URL = opa_url)
)
wait_for("the Shiny app", function() http_ok(app_url))

proxy_port <- free_port()
proxy_url <- paste0("http://127.0.0.1:", proxy_port)
proxy <- processx::process$new(
  "uv", c("run", "--quiet", "--no-project", "--with", "aiohttp", "python",
          file.path("tests", "e2e", "groups_proxy.py"), proxy_port, app_url)
)
wait_for("the proxy", function() http_ok(proxy_url), timeout = 60)
# processx and callr kill all three child processes when this script exits.

# --- Browser helpers ---------------------------------------------------------------------------

# Opens the app through the proxy as a user in `groups` (NULL: no groups at all).
open_as <- function(groups) {
  b <- chromote::ChromoteSession$new()
  b$Network$enable()
  b$Network$clearBrowserCookies()  # sessions share one browser: drop the previous user's cookie
  if (!is.null(groups)) {
    b$Network$setCookie(name = "e2e_groups", value = groups, url = proxy_url)
  }
  b$Page$navigate(proxy_url)
  wait_for("the app to connect", function() {
    js(b, "!!(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected()) &&
            document.getElementById('groups').textContent.length > 0")
  })
  b
}

js <- function(b, expr) b$Runtime$evaluate(expr, returnByValue = TRUE)$result$value
text_of <- function(b, id) js(b, sprintf("document.getElementById('%s').textContent", id))
error_notifications <- function(b) js(b, "document.querySelectorAll('.shiny-notification-error').length")

click <- function(b, id) {
  before <- error_notifications(b)
  js(b, sprintf("document.getElementById('%s').click()", id))
  Sys.sleep(1.5)  # long enough for the server round trip and the OPA call (timeout: 2 s)
  list(last_action = text_of(b, "last_action"), denied = error_notifications(b) > before)
}

failures <- 0
check <- function(label, ok) {
  cat(if (ok) "PASS" else "FAIL", " ", label, "\n", sep = "")
  if (!ok) failures <<- failures + 1
}

# --- Scenarios ---------------------------------------------------------------------------------

b <- open_as("example-editors")
check("editor: groups header reaches the app", text_of(b, "groups") == "example-editors")
check("editor: cosmetic Tier 2 note is shown", grepl("editor", text_of(b, "admin_note")))
r <- click(b, "export")
check("editor: export allowed, handler ran", r$last_action == "export_dataset" && !r$denied)
invisible(b$close())

b <- open_as("example-viewers")
check("viewer: cosmetic Tier 2 note is hidden", text_of(b, "admin_note") == "")
r <- click(b, "view")
check("viewer: view allowed, handler ran", r$last_action == "view_dataset" && !r$denied)
r <- click(b, "export")
check("viewer: export denied, notification shown, handler stopped",
      r$denied && r$last_action == "view_dataset")
invisible(b$close())

b <- open_as(NULL)
check("no header: no groups", text_of(b, "groups") == "(none)")
r <- click(b, "view")
check("no header: view denied, handler stopped", r$denied && r$last_action == "none")
invisible(b$close())

b <- open_as("example-editors")
invisible(opa$kill())
r <- click(b, "export")
check("OPA down: export denied (fails closed)", r$denied && r$last_action == "none")
check("OPA down: app still responds", text_of(b, "groups") == "example-editors")
invisible(b$close())

cat(if (failures == 0) "\nAll checks passed.\n" else sprintf("\n%d check(s) failed.\n", failures))
quit(status = if (failures == 0) 0 else 1)
