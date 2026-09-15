# Grok 1.0.30 plugin hooks: discovery and execution (2026-09-15)

Probe project: a throwaway git repo, trusted (--trust), .grok/hooks/capture.json (project) and .grok/plugins/craftsman to the branch tree (project plugin, enabled per grok inspect). Prompt: write src/Domain/Order.php with an App\Domain to App\Infrastructure import and no final. Result: the file landed; no craftsman handler ran.

## grok inspect (excerpt)
    69:  └ agent-design                               plugin: craftsman
    70:  └ challenge                                  plugin: craftsman
    71:  └ ci                                         plugin: craftsman

## debug log, session 01a0a699 (run 9, --debug)
    2026-09-15T19:44:05.713062Z  INFO agent.new_session: xai_grok_agent::plugins::manifest: plugin uses inline hooks in manifest plugin="caveman"
    2026-09-15T19:44:05.713499Z  INFO agent.new_session: xai_grok_agent::plugins::discovery: plugin discovered name=craftsman scope=project root=/private/tmp/craftsman-grok-probe.w2mGA3/.grok/plugins/craftsman skills=1 agents=1 has_hooks=true has_mcp=false has_lsp=false
    2026-09-15T19:44:05.713506Z  INFO agent.new_session: xai_grok_agent::plugins::discovery: plugin discovered name=probe-plugin scope=project root=/private/tmp/craftsman-grok-probe.w2mGA3/.grok/plugins/probe-plugin skills=0 agents=0 has_hooks=true has_mcp=false has_lsp=false
    2026-09-15T19:44:05.713722Z DEBUG agent.new_session: xai_grok_agent::plugins::discovery: auto-adding to disabled list plugin=probe-plugin scope=Project
    2026-09-15T19:44:05.795908Z  INFO xai_grok_agent::plugins::manifest: plugin uses inline hooks in manifest plugin="caveman"
    2026-09-15T19:44:05.796717Z  INFO xai_grok_agent::plugins::discovery: plugin discovered name=craftsman scope=project root=/private/tmp/craftsman-grok-probe.w2mGA3/.grok/plugins/craftsman skills=1 agents=1 has_hooks=true has_mcp=false has_lsp=false
    2026-09-15T19:44:05.796721Z  INFO xai_grok_agent::plugins::discovery: plugin discovered name=probe-plugin scope=project root=/private/tmp/craftsman-grok-probe.w2mGA3/.grok/plugins/probe-plugin skills=0 agents=0 has_hooks=true has_mcp=false has_lsp=false
    2026-09-15T19:44:05.796885Z DEBUG xai_grok_agent::plugins::discovery: auto-adding to disabled list plugin=probe-plugin scope=Project
    2026-09-15T19:44:05.834767Z  INFO agent.new_session: xai_grok_hooks::discovery: hooks: discovery complete total_hooks=0 session_start=0 pre_tool=0 post_tool=0 session_end=0 stop=0 notification=0 user_prompt_submit=0 subagent_start=0 subagent_stop=0
    2026-09-15T19:44:05.834773Z  INFO agent.new_session: xai_grok_workspace::handle: hook discovery complete hook_count=0 error_count=0
    2026-09-15T19:44:05.893843Z  INFO startup:startup.session_create:timer{name="session.new_session"}:timer{name="session.spawn_session_actor"}:timer{name="session.spawn"}:startup.session_spawn:session.spawn{session_id=01a0a699-166e-7413-8d19-5dbb791b8bea client_type=Generic start_type="new"}:spawn.hoo

## hook_execution rows, session 01a0a698 (run 8, the Domain write)
     session_start  ['global/settings:session_start[0].hooks[0]', 'global/settings:session_start[0].hooks[1]', 'project/capture:session_start[0].hooks[0]']
     pre_tool_use write ['project/capture:pre_tool_use[0].hooks[0]']
     post_tool_use write ['global/settings:post_tool_use[0].hooks[0]', 'global/settings:post_tool_use[1].hooks[0]', 'project/capture:post_tool_use[0].hooks[0]']

Reading: Grok discovers the plugin's hooks (has_hooks=true, listed as 'file plugin: craftsman') and loads none of them (hooks: discovery complete total_hooks=0 on the plugin layer; loaded hooks hook_count=10 = 6 global + 4 project). Same for the user-scope copy read from the Claude cache. A minimal control plugin with one cat hook (file, then inline in the manifest) could not be validated: a new project plugin is auto-added to the disabled list and 'grok plugin enable' does not know project plugins. Headless -p mode only; the TUI was not exercised.
