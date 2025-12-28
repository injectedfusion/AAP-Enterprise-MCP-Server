#!/bin/bash
# Wrapper to run MCP server with 1Password secrets
cd /Users/gabriel/repos/awx-mcp-server

# Create temp env file
ENV_FILE=$(mktemp)
trap "rm -f $ENV_FILE" EXIT

cat > "$ENV_FILE" << 'EOF'
AAP_URL=http://localhost:8080/api/v2
AAP_TOKEN=op://development/AWX API Token MCP/credential
EOF

exec op run --env-file="$ENV_FILE" --account=KK2DNNXVWRGTTPU4E4KGHFZSRI -- uv run ansible.py
