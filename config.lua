local config = require("lapis.config")

-- Global config variables.
BCRYPT_NUM_CYCLES = 8

-- Server configuration.
config("development", {
  port = 9009,
  session_name = "svd_viz_session",
  secret = "test_secret_change_me",
  postgres = {
    host = "127.0.0.1",
    user = "postgres",
    password = "postgres_password",
    database = "svd_viz_test"
  }
})
