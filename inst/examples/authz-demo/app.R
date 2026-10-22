# Minimal app showing both layers of c3g.shiny.authz. Run it behind oauth2-proxy (or anything
# else that sets X-Forwarded-Groups) with the app's OPA sidecar reachable at C3G_OPA_URL.
#
#   C3G_OPA_URL=http://127.0.0.1:8181 Rscript -e 'shiny::runApp(system.file("examples/authz-demo", package = "c3g.shiny.authz"))'

library(shiny)
library(c3g.shiny.authz)

policy_path <- Sys.getenv("C3G_OPA_POLICY_PATH", "example_app/authz/allow")

ui <- fluidPage(
  titlePanel("c3g.shiny.authz demo"),
  p("Your groups: ", textOutput("groups", inline = TRUE)),
  actionButton("view", "View dataset"),
  actionButton("export", "Export dataset"),
  uiOutput("admin_note"),
  h4("Last action that ran"),
  textOutput("last_action")
)

server <- function(input, output, session) {
  groups <- c3g_groups(session)
  last_action <- reactiveVal("none")

  output$groups <- renderText(if (length(groups)) paste(groups, collapse = ", ") else "(none)")

  # Tier 2, cosmetic: only changes what's shown, decides nothing.
  output$admin_note <- renderUI({
    if ("example-editors" %in% groups) p(em("You're an editor: exports are available."))
  })

  # Tier 3, real authorization: on deny, the user sees a notification and the handler stops.
  observeEvent(input$view, {
    c3g_require_authz("view_dataset", session, policy_path)
    last_action("view_dataset")
  })
  observeEvent(input$export, {
    c3g_require_authz("export_dataset", session, policy_path)
    last_action("export_dataset")
  })

  output$last_action <- renderText(last_action())
}

shinyApp(ui, server)
