const std = @import("std");
const args = @import("args.zig");

pub fn writeCompletions(writer: *std.Io.Writer, shell: args.Shell) !void {
    switch (shell) {
        .bash => try writer.writeAll(bash_completions),
        .zsh => try writer.writeAll(zsh_completions),
        .fish => try writer.writeAll(fish_completions),
    }
}

pub fn writeMan(writer: *std.Io.Writer) !void {
    try writer.writeAll(man_page);
}

const bash_completions =
    \\_git_stage_lines() {
    \\  local cur prev
    \\  COMPREPLY=()
    \\  cur="${COMP_WORDS[COMP_CWORD]}"
    \\  prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\
    \\  case "$prev" in
    \\    --mode)
    \\      COMPREPLY=( $(compgen -W "new old both" -- "$cur") )
    \\      return 0
    \\      ;;
    \\    --context)
    \\      return 0
    \\      ;;
    \\    completions)
    \\      COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
    \\      return 0
    \\      ;;
    \\  esac
    \\
    \\  if [[ "$cur" == -* ]]; then
    \\    COMPREPLY=( $(compgen -W "--mode --dry-run --check --json --context --allow-empty --verbose --version --help" -- "$cur") )
    \\    return 0
    \\  fi
    \\
    \\  if [[ $COMP_CWORD -eq 1 ]]; then
    \\    COMPREPLY=( $(compgen -W "diff completions man" -- "$cur") )
    \\    return 0
    \\  fi
    \\}
    \\complete -F _git_stage_lines git-stage-lines
    \\
;

const zsh_completions =
    \\#compdef git-stage-lines
    \\
    \\_git_stage_lines() {
    \\  local -a commands modes shells options
    \\  commands=(diff completions man)
    \\  modes=(new old both)
    \\  shells=(bash zsh fish)
    \\  options=(
    \\    '--mode[Select by working-tree, index, or either line numbers]:mode:(new old both)'
    \\    '--dry-run[Print the patch that would be staged]'
    \\    '--check[Validate the selected patch without staging]'
    \\    '--json[Emit machine-readable JSON]'
    \\    '--context[Accepted for compatibility]:context'
    \\    '--allow-empty[Treat no matching changes as a successful noop]'
    \\    '--verbose[Include extra diagnostics]'
    \\    '--version[Show version]'
    \\    '(-h --help)'{-h,--help}'[Show help]'
    \\  )
    \\
    \\  _arguments \
    \\    '1:command or file:_alternative "commands:commands:($commands)" "files:files:_files"' \
    \\    '2:range, refs, file, or shell:_alternative "modes:modes:($modes)" "shells:shells:($shells)" "files:files:_files"' \
    \\    '*::args:_files' \
    \\    $options
    \\}
    \\
    \\_git_stage_lines "$@"
    \\
;

const fish_completions =
    \\complete -c git-stage-lines -f
    \\complete -c git-stage-lines -n '__fish_use_subcommand' -a 'diff' -d 'Show unstaged changes with line numbers'
    \\complete -c git-stage-lines -n '__fish_use_subcommand' -a 'completions' -d 'Print shell completions'
    \\complete -c git-stage-lines -n '__fish_use_subcommand' -a 'man' -d 'Print a manual page'
    \\complete -c git-stage-lines -n '__fish_seen_subcommand_from completions' -a 'bash zsh fish'
    \\complete -c git-stage-lines -l mode -x -a 'new old both' -d 'Select line-number side'
    \\complete -c git-stage-lines -l dry-run -d 'Print the patch that would be staged'
    \\complete -c git-stage-lines -l check -d 'Validate without staging'
    \\complete -c git-stage-lines -l json -d 'Emit machine-readable JSON'
    \\complete -c git-stage-lines -l context -x -d 'Accepted for compatibility'
    \\complete -c git-stage-lines -l allow-empty -d 'Treat no matching changes as success'
    \\complete -c git-stage-lines -l verbose -d 'Include extra diagnostics'
    \\complete -c git-stage-lines -l version -d 'Show version'
    \\complete -c git-stage-lines -s h -l help -d 'Show help'
    \\
;

const man_page =
    \\.TH GIT-STAGE-LINES 1
    \\.SH NAME
    \\git-stage-lines \- stage selected changed lines from a Git worktree
    \\.SH SYNOPSIS
    \\.B git-stage-lines
    \\FILE RANGES [options]
    \\
    \\.B git-stage-lines
    \\FILE:REFS [options]
    \\
    \\.B git-stage-lines
    \\diff [FILE...]
    \\
    \\.B git-stage-lines
    \\completions bash|zsh|fish
    \\
    \\.B git-stage-lines
    \\man
    \\.SH DESCRIPTION
    \\git-stage-lines builds a zero-context patch for selected changed lines and applies it to the Git index. The working tree is not modified.
    \\.SH LINE REFERENCES
    \\RANGES is a comma-separated list such as 10, 10-15, or 10,20-25. By default, ranges refer to new working-tree line numbers.
    \\
    \\FILE:REFS is exact. Positive refs select new-side lines. Negative refs select old-side deletion lines. Examples: src/app.ts:10, src/app.ts:-20, src/app.ts:-20..-25.
    \\.SH OPTIONS
    \\.TP
    \\.B --mode new|old|both
    \\Select by working-tree, index, or either line numbers.
    \\.TP
    \\.B --dry-run
    \\Print the patch that would be staged.
    \\.TP
    \\.B --check
    \\Validate the selected patch without staging.
    \\.TP
    \\.B --json
    \\Emit machine-readable JSON.
    \\.TP
    \\.B --allow-empty
    \\Treat no matching changes as a successful noop.
    \\.TP
    \\.B --version
    \\Print the version.
    \\.SH EXIT STATUS
    \\0 on success, 1 for input errors, 2 for no matching changes, 3 for patch validation failures, 4 for Git command failures, and 5 for unsupported diffs.
    \\.SH SEE ALSO
    \\git-diff(1), git-apply(1), git-add(1)
    \\
;
