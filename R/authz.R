#' Require OPA authorization for an action (Tier 3, real authorization)
#'
#' Call this at the top of a guarded `observeEvent()`/`downloadHandler()`. Builds an
#' `{action, groups}` payload -- Shiny apps are single-page, so there's no route to key a
#' decision off, just a named action -- and calls the app's local OPA sidecar. **Fails
#' closed**: any error reaching OPA (network failure, timeout, non-2xx response, malformed
#' body, undefined rule) is treated as a deny, never silently allowed. On deny, the user is
#' notified and execution stops (via `shiny::req`) -- the calling code never runs.
#'
#' @param action A short string naming the action being authorized (e.g. `"export_dataset"`).
#'   Must match whatever the app's Rego policy (in `c3g-opa-policies`) expects as
#'   `input.action`.
#' @param session The current Shiny session, as passed into the server function.
#' @param policy_path The rule to query, as a slash-separated path: the Rego package and rule
#'   name with dots replaced by slashes. E.g. package `my_app.authz`, rule `allow`, becomes
#'   `"my_app/authz/allow"`. Each app's policy lives under its own package in
#'   `c3g-opa-policies`, so there is no default.
#' @param opa_url Base URL of the app's local OPA sidecar. Defaults to the `C3G_OPA_URL`
#'   environment variable, falling back to `http://10.0.2.2:8181` -- the host-loopback address
#'   used throughout `web-app-template`'s deployment docs.
#' @param timeout Seconds to wait for OPA before treating the call as failed (and therefore
#'   denied). Keep it short: a Shiny process is single-threaded, so a hanging call freezes the
#'   app for every user, not just this one.
#'
#' @return Invisibly, `TRUE` if authorized. Does not return on deny -- stops execution instead
#'   (see Details).
#'
#' @examples
#' \dontrun{
#' observeEvent(input$export_btn, {
#'   c3g_require_authz("export_dataset", session, policy_path = "my_app/authz/allow")
#'   # ... proceed with the export; unreached if the call above denied
#' })
#' }
#'
#' @export
c3g_require_authz <- function(action,
                              session,
                              policy_path,
                              opa_url = Sys.getenv("C3G_OPA_URL", "http://10.0.2.2:8181"),
                              timeout = 2) {
  # A missing policy path is a programming error, not a deny: fail loudly so it's caught the
  # first time the app runs, rather than looking like every user lacks permission.
  if (missing(policy_path) || !is.character(policy_path) || length(policy_path) != 1 ||
      !nzchar(gsub("/", "", policy_path, fixed = TRUE))) {
    stop("`policy_path` must name the app's OPA rule, e.g. \"my_app/authz/allow\".",
         call. = FALSE)
  }

  groups <- c3g_groups(session)
  body <- list(input = list(action = action, groups = as.list(groups)))
  path <- strsplit(gsub("^/+|/+$", "", policy_path), "/", fixed = TRUE)[[1]]

  # Fail closed: any error reaching OPA (network failure, timeout, non-2xx, malformed body)
  # becomes NULL here, which `allowed` below treats as a deny -- never an allow. An undefined
  # rule comes back as `{}`, so `result$result` is NULL and also denies.
  result <- tryCatch(
    {
      httr2::request(opa_url) |>
        httr2::req_url_path_append("v1", "data", path) |>
        httr2::req_body_json(body) |>
        httr2::req_timeout(timeout) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
    },
    error = function(e) NULL
  )

  allowed <- isTRUE(result$result)

  if (!allowed) {
    shiny::showNotification("You are not authorized to perform this action.",
                            type = "error", session = session)
    shiny::req(FALSE)
  }

  invisible(allowed)
}
