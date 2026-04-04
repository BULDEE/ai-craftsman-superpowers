# Anti-Pattern: Unquoted Variables

## The Problem

Unquoted variables undergo word splitting and glob expansion.
A filename with spaces or special characters can break your entire script.

## Bad

```bash
file_path=$1
rm $file_path          # Word splitting: "my file.txt" becomes rm my file.txt
cat $file_path         # Same problem
cp $source $dest       # Both variables vulnerable
```

## Good

```bash
file_path="$1"
rm "$file_path"
cat "$file_path"
cp "$source" "$dest"
```

## Exception

Inside `[[ ]]` tests, quotes are optional (no word splitting occurs).
But quoting consistently is safer and more readable.

## Rule

**SH005** — Unquoted variable in file operation. Always quote `"$variable"`.
