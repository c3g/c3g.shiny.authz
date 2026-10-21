test_that("c3g_groups parses a comma-separated header", {
  session <- list(request = list(HTTP_X_FORWARDED_GROUPS = "admins, users, ops"))
  expect_equal(c3g_groups(session), c("admins", "users", "ops"))
})

test_that("c3g_groups returns an empty vector when the header is absent", {
  session <- list(request = list(HTTP_X_FORWARDED_GROUPS = NULL))
  expect_equal(c3g_groups(session), character(0))
})

test_that("c3g_groups returns an empty vector when the header is empty", {
  session <- list(request = list(HTTP_X_FORWARDED_GROUPS = ""))
  expect_equal(c3g_groups(session), character(0))
})

test_that("c3g_groups handles a single group with no commas", {
  session <- list(request = list(HTTP_X_FORWARDED_GROUPS = "admins"))
  expect_equal(c3g_groups(session), "admins")
})
