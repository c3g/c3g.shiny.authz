free_port <- function() {
  # Base R can't ask the OS for a free port, so pick a random high port and check nothing is
  # listening there.
  for (i in 1:50) {
    port <- sample(20000:60000, 1)
    con <- suppressWarnings(tryCatch(
      socketConnection("127.0.0.1", port, open = "r+", blocking = TRUE, timeout = 0.2),
      error = function(e) NULL
    ))
    if (is.null(con)) return(port)
    close(con)
  }
  stop("couldn't find a free port")
}

# Starts `opa run --server` loaded with tests/testthat/fixtures/example_app/ for the duration
# of the calling test, and returns its base URL. Skips when the `opa` CLI isn't on PATH --
# except in CI (the `CI` env var GitHub Actions sets), where a missing `opa` must fail the run
# instead of silently skipping the tests that use a real policy.
local_opa_server <- function(env = parent.frame()) {
  if (!nzchar(Sys.which("opa"))) {
    if (nzchar(Sys.getenv("CI"))) stop("opa CLI not found on PATH in CI")
    testthat::skip("opa CLI not found on PATH -- install it to run the real-policy tests")
  }

  port <- free_port()
  addr <- paste0("127.0.0.1:", port)
  proc <- processx::process$new(
    "opa", c("run", "--server", "--addr", addr, test_path("fixtures", "example_app")),
    stdout = NULL, stderr = NULL
  )
  withr::defer(proc$kill(), envir = env)

  url <- paste0("http://", addr)
  deadline <- Sys.time() + 10
  repeat {
    up <- tryCatch(
      httr2::request(url) |>
        httr2::req_url_path_append("health") |>
        httr2::req_timeout(0.5) |>
        httr2::req_perform() |>
        httr2::resp_status() == 200,
      error = function(e) FALSE
    )
    if (up) return(url)
    if (Sys.time() > deadline) stop("opa server never came up")
    Sys.sleep(0.1)
  }
}
