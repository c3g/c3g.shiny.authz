#' Require OPA authorization for an action (Tier 3, real authorization)
#'
#' Call this at the top of a guarded `observeEvent()`/`downloadHandler()`. Builds an
#' `{action, groups}` payload -- Shiny apps are single-page, so there's no route to key a
#' decision off, just a named action -- and calls the app's local OPA sidecar. **Fails
#' closed**: any error reaching OPA (network failure, non-2xx response, malformed body) is
#' treated as a deny, never silently allowed. On deny, execution stops (via `shiny::req`) and
#' the user is notified -- the calling code never runs.
#'
#' @param action A short string naming the action being authorized (e.g. `"export_dataset"`).
#'   Must match whatever the app's Rego policy (in `c3g-opa-policies`) expects as
#'   `input.action`.
#' @param session The current Shiny session, as passed into the server function.
#' @param opa_url Base URL of the app's local OPA sidecar. Defaults to the `C3G_OPA_URL`
#'   environment variable, falling back to `http://10.0.2.2:8181` -- the host-loopback address
#'   used throughout `web-app-template`'s deployment docs.
#'
#' @return Invisibly, `TRUE` if authorized. Does not return on deny -- stops execution instead
#'   (see Details).
#'
#' @examples
#' \dontrun{
#' observeEvent(input$export_btn, {
#'   c3g_require_authz("export_dataset", session)
#'   # ... proceed with the export; unreached if the call above denied
#' })
#' }
#'
#' @export
c3g_require_authz <- function(action,
                               session,
                               opa_url = Sys.getenv("C3G_OPA_URL", "http://10.0.2.2:8181")) {
  groups <- c3g_groups(session)
  body <- list(input = list(action = action, groups = as.list(groups)))

  # Fail closed: any error reaching OPA (network failure, non-2xx, malformed body) becomes
  # NULL here, which `allowed` below treats as a deny -- never an allow.
  result <- tryCatch(
    {
      httr2::request(opa_url) |>
        httr2::req_url_path_append("v1", "data", "authz", "allow") |>
        httr2::req_body_json(body) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
    },
    error = function(e) NULL
  )

  allowed <- isTRUE(result$result)

  if (!allowed) {
    shiny::showNotification("You are not authorized to perform this action.", type = "error")
    shiny::req(FALSE)
  }

  invisible(allowed)
}
