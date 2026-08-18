# Ambxst customization reference

## Resolve the running copy

```bash
command -v ambxst
sed -n '1,80p' "$(command -v ambxst)"
readlink -f ~/.local/src/ambxst
```

The command wrapper and Hyprland autostart determine which checkout is live.
Do not infer that from the current working directory.

## User-owned state

- `~/.config/ambxst/config/*.json`: shell settings by domain.
- `~/.config/hypr/`: compositor configuration owned by the user.
- `~/.cache/ambxst/`: disposable caches and generated theme artifacts.
- `~/.local/state/ambxst/`: toggles and runtime state.

Files under `~/.local/share/ambxst/` are commonly generated from settings. Change
their source setting instead of editing generated output.

## Source work

When the user explicitly asks to develop Ambxst itself:

1. Work on a feature branch in the fork checkout.
2. Read repository and nearest-directory `AGENTS.md` files.
3. Update both `config/defaults/*.js` and `config/Config.qml` for new config keys.
4. Use `StyledRect` rather than raw `Rectangle` containers.
5. Run `./lab/check-qml-syntax.sh`, then `./lab/run-isolated.sh` for visual work.
6. Never run the upstream installer/update path from a dirty checkout.

This is source development, so follow repository instructions over the general
end-user workflow in the parent skill.
