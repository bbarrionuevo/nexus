module.exports = { apps: [{
  name: "nexus", script: "python3", args: "-m nexus.main", cwd: __dirname,
  autorestart: true, restart_delay: 5000, env: { NEXUS_PAPER_TRADING: "true" }
}]};
