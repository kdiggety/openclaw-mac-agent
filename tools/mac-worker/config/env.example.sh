# Copy to env.sh and customize for the local Mac worker account.
export MAC_WORKER_HOME="$HOME/mac-worker"

# Optional local-dev default when you are not using --project-profile.
# In hardened remote mode, --project-profile is required and this value is ignored.
export MAC_WORKER_DEFAULT_PROJECT_ROOT="$HOME/src/apple-apps/sample-project"

# Optional default mode for local runs. Keep this at dev unless you have a reason
# to default local invocations to hardened behavior.
export MAC_WORKER_DEFAULT_MODE="dev"
