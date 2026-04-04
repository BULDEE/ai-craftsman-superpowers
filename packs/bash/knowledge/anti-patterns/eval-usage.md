# Anti-Pattern: eval Usage

## The Problem

`eval` re-parses its arguments as a shell command.
User input or variable content can inject arbitrary commands.

## Bad

```bash
user_input="file.txt; rm -rf /"
eval "cat $user_input"    # Executes: cat file.txt; rm -rf /
```

## Good

```bash
# Use arrays for dynamic commands
declare -a command_parts=("cat" "$user_input")
"${command_parts[@]}"

# Use indirect variable references instead of eval
declare -n ref="$variable_name"
echo "$ref"
```

## Rule

**SH004** — `eval` found. Use arrays, indirect references, or `declare -n` instead.
