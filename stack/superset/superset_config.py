# Superset (EKOS fork) for the local demo: the gold marts in one DuckDB file, Ask (AI) grounded and
# checked by EKOS over MCP, the model a local Ollama (its Anthropic-compatible /v1/messages).
# Local only: bound to 127.0.0.1, weak secrets from the environment.
import os

SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]
SQLALCHEMY_DATABASE_URI = "sqlite:////app/superset_home/superset.db"
WTF_CSRF_ENABLED = True
FEATURE_FLAGS = {"DASHBOARD_NATIVE_FILTERS": True}

EKOS_AI_ENABLED = True
EKOS_MCP_URL = os.environ["EKOS_MCP_URL"]           # `ekos mcp serve --http` on the host
EKOS_MCP_TOKEN_ENV = "EKOS_MCP_TOKEN"
EKOS_MCP_DATABASE = "gold"                           # the project's [[databases]] entry for the marts file
EKOS_MCP_STATUS = "all"                              # show hypotheses too, labelled as such
EKOS_AI_DIALECT = "duckdb"
EKOS_AI_DATABASE = "marts"                           # the Superset connection, opened read-only
EKOS_AI_SCHEMA = "gold_idem"                         # the schema the generated marts are built in
EKOS_AI_REQUALIFY = True                             # DuckDB ignores a connection's schema: every table is put in gold_idem
EKOS_AI_TABLES = os.environ.get("EKOS_AI_TABLES", "")    # comma list; empty = every compiled mart
EKOS_AI_BASE_URL = os.environ.get("EKOS_AI_BASE_URL", "http://host.docker.internal:11434")
EKOS_AI_MODEL = os.environ.get("EKOS_AI_MODEL", "qwen2.5-coder:3b")
EKOS_AI_KEY_ENV = os.environ.get("EKOS_AI_KEY_ENV", "EKOS_AI_KEY")   # the variable holding the key (OpenCode Zen: OPENCODE_API_KEY; Ollama ignores it)
EKOS_AI_MODEL_TIMEOUT = int(os.environ.get("EKOS_AI_MODEL_TIMEOUT", "60"))   # a hosted model; 300 was for Ollama on a CPU
EKOS_AI_QUERY_TIMEOUT = 15
EKOS_AI_PER_USER_PER_DAY = 100
EKOS_AI_PER_DAY = 500
