#' Parse the oauth2-proxy forwarded-groups header
#'
#' Reads and parses `X-Forwarded-Groups` from the current Shiny `session$request`. This is a
#' Tier 2, **cosmetic-only** helper -- the actual access decision already happened at
#' oauth2-proxy, before the request reached Shiny at all. Use this only to conditionally
#' show/hide UI (e.g. an admin tab); it is not a security boundary. See
#' [web-app-template](https://github.com/c3g/web-app-template)'s `for-app-developers.md` for
#' the tier this belongs to.
#'
#' @param session The current Shiny session, as passed into the server function.
#' @return A character vector of group names. Empty if the header is absent (e.g. the app
#'   isn't actually running behind oauth2-proxy, such as during local development).
#'
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   groups <- c3g_groups(session)
#'   if ("admins" %in% groups) {
#'     # show an admin-only tab, button, etc.
#'   }
#' }
#' }
#'
#' @export
c3g_groups <- function(session) {
  header <- session$request$HTTP_X_FORWARDED_GROUPS
  if (is.null(header) || !nzchar(header)) {
    return(character(0))
  }
  trimws(strsplit(header, ",", fixed = TRUE)[[1]])
}
