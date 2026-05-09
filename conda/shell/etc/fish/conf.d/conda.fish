# Copyright (C) 2012 Anaconda, Inc
# SPDX-License-Identifier: BSD-3-Clause
#
# INSTALL
#
#     Run 'conda init fish' and restart your shell.
#

if not set -q CONDA_SHLVL
    set -gx CONDA_SHLVL 0
    set -g _CONDA_ROOT (dirname (dirname $CONDA_EXE))
    set -gx PATH $_CONDA_ROOT/condabin $PATH
end

if not set -q CONDA_DISABLE_FISH_PROMPT
    function __conda_add_prompt
        if set -q CONDA_PROMPT_MODIFIER
            set_color -o green
            echo -n $CONDA_PROMPT_MODIFIER
            set_color normal
        end
    end

    if functions -q fish_prompt
        if not functions -q __fish_prompt_orig
            functions -c fish_prompt __fish_prompt_orig
        end
        functions -e fish_prompt
    else
        function __fish_prompt_orig
        end
    end

    function return_last_status
        return $argv
    end

    function fish_prompt
        set -l last_status $status
        if set -q CONDA_LEFT_PROMPT
            __conda_add_prompt
        end
        return_last_status $last_status
        __fish_prompt_orig
    end

    if functions -q fish_right_prompt
        if not functions -q __fish_right_prompt_orig
            functions -c fish_right_prompt __fish_right_prompt_orig
        end
        functions -e fish_right_prompt
    else
        function __fish_right_prompt_orig
        end
    end

    function fish_right_prompt
        if not set -q CONDA_LEFT_PROMPT
            __conda_add_prompt
        end
        __fish_right_prompt_orig
    end
end

function conda --inherit-variable CONDA_EXE
    if [ (count $argv) -lt 1 ]
        $CONDA_EXE
    else
        set -l cmd $argv[1]
        set -e argv[1]
        switch $cmd
            case activate deactivate
                eval ($CONDA_EXE shell.fish $cmd $argv)
            case install update upgrade remove uninstall
                $CONDA_EXE $cmd $argv
                and eval ($CONDA_EXE shell.fish reactivate)
            case '*'
                $CONDA_EXE $cmd $argv
        end
    end
end




# Autocompletions below

function __fish_conda_subcommand
    # Scans the commandline for the conda subcommand chain.
    #
    # Called with no arguments:
    #   Prints the top-level subcommand and returns 0 if one exists, 1 if not.
    #   Used inside (…) to feed `contains`: contains -- (__fish_conda_subcommand) config
    #
    # Called with arguments (a subcommand chain, e.g. "self"):
    #   Verifies the commandline positionals match the chain.
    #   Prints the next positional (if any) and returns 1 (further subcommand present).
    #   Returns 0 when the chain matches and no further subcommand follows.
    #   Used both bare in -n conditions and inside (…) for deeper chains:
    #     -n "__fish_conda_subcommand self"
    #     contains -- (__fish_conda_subcommand self) install

    # Collect positional tokens: skip `conda` itself and any flag tokens (starting with -)
    set -l positionals
    for tok in (commandline -xpc)[2..-1]
        string match -qr '^-' -- $tok
        or set -a positionals $tok
    end

    set -l depth (count $argv)

    if test $depth -eq 0
        # No chain to match — just report the first subcommand
        set -q positionals[1]; or return 1
        echo $positionals[1]
        return 0
    end

    # Verify each level of the requested chain against commandline positionals
    set -l i 1
    while test $i -le $depth
        if not set -q positionals[$i]; or test "$positionals[$i]" != "$argv[$i]"
            return 1
        end
        set i (math $i + 1)
    end

    # Chain matched: emit the next positional (if present) for deeper contains checks
    set -l next (math $depth + 1)
    if set -q positionals[$next]
        echo $positionals[$next]
        return 1  # A further subcommand exists; suppress -n bare usage
    end
    return 0  # Chain fully matched with nothing beyond it
end

function __fish_conda -a cmd
    # Register a completion scoped to a specific conda subcommand
    complete -c conda -n "contains -- (__fish_conda_subcommand) $cmd" $argv[2..-1]
end

function __fish_conda_top
    # Register a completion that only applies before any subcommand has been entered
    complete -c conda -n 'not __fish_conda_subcommand' $argv
end

function __fish_conda_config_keys
    # Static list of all known config keys as of conda 26.3.2.
    # Update by running: conda config --show | string match -r '^\w+(?=:)'
    echo add_anaconda_token
    echo add_pip_as_python_dependency
    echo aggressive_update_packages
    echo allow_conda_downgrades
    echo allow_cycles
    echo allow_non_channel_urls
    echo allow_softlinks
    echo allowlist_channels
    echo always_copy
    echo always_softlink
    echo always_yes
    echo anaconda_anon_usage
    echo anaconda_heartbeat
    echo anaconda_upload
    echo auto_activate
    echo auto_stack
    echo auto_update_conda
    echo bld_path
    echo changeps1
    echo channel_alias
    echo channel_priority
    echo channel_settings
    echo channels
    echo client_ssl_cert
    echo client_ssl_cert_key
    echo clobber
    echo conda_build
    echo console
    echo create_default_packages
    echo croot
    echo custom_channels
    echo custom_multichannels
    echo debug
    echo default_activation_env
    echo default_channels
    echo default_python
    echo default_threads
    echo denylist_channels
    echo deps_modifier
    echo dev
    echo disallowed_packages
    echo download_only
    echo dry_run
    echo enable_private_envs
    echo env_prompt
    echo environment_specifier
    echo envs_dirs
    echo envvars_force_uppercase
    echo error_upload_url
    echo execute_threads
    echo experimental
    echo export_platforms
    echo extra_safety_checks
    echo fetch_threads
    echo force
    echo force_32bit
    echo force_reinstall
    echo force_remove
    echo ignore_pinned
    echo json
    echo list_fields
    echo local_repodata_ttl
    echo migrated_channel_aliases
    echo migrated_custom_channels
    echo no_lock
    echo no_plugins
    echo non_admin_enabled
    echo notify_outdated_conda
    echo number_channel_notices
    echo offline
    echo override_channels_enabled
    echo override_virtual_packages
    echo path_conflict
    echo pinned_packages
    echo pkgs_dirs
    echo plugins
    echo prefix_data_interoperability
    echo protect_frozen_envs
    echo proxy_servers
    echo quiet
    echo register_envs
    echo remote_backoff_factor
    echo remote_connect_timeout_secs
    echo remote_max_retries
    echo remote_read_timeout_secs
    echo repodata_fns
    echo repodata_threads
    echo repodata_use_zst
    echo report_errors
    echo rollback_enabled
    echo root_prefix
    echo safety_checks
    echo sat_solver
    echo separate_format_cache
    echo shortcuts
    echo shortcuts_only
    echo show_channel_urls
    echo signing_metadata_url_base
    echo solver
    echo solver_ignore_timestamps
    echo ssl_verify
    echo subdir
    echo subdirs
    echo target_prefix_override
    echo trace
    echo track_features
    echo unsatisfiable_hints
    echo unsatisfiable_hints_check_depth
    echo update_modifier
    echo use_index_cache
    echo use_local
    echo use_only_tar_bz2
    echo verbosity
    echo verify_threads
end

function __fish_conda_config_set_keys
    # Only keys explicitly set in config files (not defaults)
    conda config --show-sources 2>/dev/null | string match -rg '^(\w+):'
end

function __fish_conda_config_values
    # Values currently set for the key preceding --remove on the commandline
    set -l tokens (commandline -xpc)
    set -l idx (contains -i -- --remove $tokens)
    or return
    set -l key $tokens[(math $idx + 1)]
    test -n "$key"; or return
    conda config --get $key 2>/dev/null | string match -rg "^--?(?:add|set) $key '?([^'# ]+)"
end

function __fish_conda_environments
    # Read environment directories without spawning Python.
    # Covers base, the standard envs dir, and any paths in CONDA_ENVS_PATH.
    # Environments in condarc envs_dirs beyond the standard location are not listed.
    set -q CONDA_EXE; or return
    set -l conda_root (dirname (dirname $CONDA_EXE))
    set -l search_dirs $conda_root/envs
    set -q CONDA_ENVS_PATH; and set -a search_dirs (string split ':' $CONDA_ENVS_PATH)

    echo base
    for dir in $search_dirs
        test -d $dir; or continue
        # `ls -1` handles empty dirs cleanly; `test -d` filters out files
        for entry in (command ls -1 $dir 2>/dev/null)
            test -d $dir/$entry; and echo $entry
        end
    end
end

function __fish_conda_installed_packages
    # Resolve the conda-meta directory without spawning Python where possible.
    # conda-meta filenames are: {name}-{version}-{build}.json
    # Package names can contain dashes; versions always start with a digit,
    # so (.+?)-\d[^-]*-[^-]+\.json cleanly separates name from version+build.

    # Scan for -n/--name on the commandline (built-ins only)
    set -l tokens (commandline -xpc)
    set -l env_name ""
    for flag in -n --name
        set -l idx (contains -i -- $flag $tokens)
        or continue
        set -q tokens[(math $idx + 1)]; and set env_name $tokens[(math $idx + 1)]
        break
    end

    set -l meta_dir
    if test -n "$env_name"
        # Derive the standard envs root from CONDA_EXE (set by conda's shell init)
        set -q CONDA_EXE; and set meta_dir (dirname (dirname $CONDA_EXE))/envs/$env_name/conda-meta
    else if set -q CONDA_PREFIX
        set meta_dir $CONDA_PREFIX/conda-meta
    end

    if test -d "$meta_dir"
        # Read filenames directly — no Python process, ~10ms vs ~1-2s for `conda list`
        string match -rg '^.*/(.+?)-\d[^-]*-[^-]+\.json$' $meta_dir/*.json 2>/dev/null
    else if test -n "$env_name"
        # Fallback for envs in non-standard locations
        conda list -n $env_name --no-pip -q 2>/dev/null | string match -rv '^#' | string match -rg '^(\S+)'
    end
end

function __fish_conda_config_set_value
    # Suggest valid values for the key following --set on the commandline
    set -l tokens (commandline -xpc)
    set -l idx (contains -i -- --set $tokens)
    or return
    set -l key $tokens[(math $idx + 1)]
    test -n "$key"; or return
    switch $key
        case solver
            printf "%s\n" classic libmamba rattler
        case channel_priority
            printf "%s\n" strict flexible disabled
        case verbosity
            printf "%s\n" 0 1 2 3
        case '*'
            # Detect boolean keys dynamically from conda config --show output
            set -l val (conda config --show 2>/dev/null | string match -rg "^$key: (True|False)")
            if test -n "$val"
                printf "%s\n" True False
            end
    end
end

# common options
complete -c conda -f
complete -c conda -s h -l help -d "Show help and exit"

# top-level options
__fish_conda_top -s V -l version -d "Show the conda version number and exit"

# top-level commands
__fish_conda_top -a clean -d "Remove unused packages and caches"
__fish_conda_top -a compare -d "Compare packages between conda environments"
__fish_conda_top -a config -d "Modify configuration values in .condarc"
__fish_conda_top -a create -d "Create a new conda environment from a list of specified packages"
__fish_conda_top -a doctor -d "Display a health report for your environment"
__fish_conda_top -a export -d "Export a given environment"
__fish_conda_top -a info -d "Display information about current conda install"
__fish_conda_top -a install -d "Install a list of packages into a specified conda environment"
__fish_conda_top -a init -d "Initialize conda for shell interaction"
__fish_conda_top -a list -d "List installed packages in a conda environment"
__fish_conda_top -a notices -d "Retreive latest channel notifications"
__fish_conda_top -a package -d "Low-level conda package utility (EXPERIMENTAL)"
__fish_conda_top -a remove -d "Remove a list of packages from a specified conda environment"
__fish_conda_top -a rename -d "Rename an existing environment"
__fish_conda_top -a repoquery -d "Advanced search for repodata"
__fish_conda_top -a run -d "Run an executable in a conda environment"
__fish_conda_top -a search -d "Search for packages and display associated information"
__fish_conda_top -a update -d "Updates conda packages to the latest compatible version"

# command added by sourcing ~/miniconda3/etc/fish/conf.d/conda.fish,
# which is the recommended way to use conda with fish
__fish_conda_top -a pypi -d "Install PyPI packages as conda packages"
__fish_conda_top -a self -d "Manage your conda base environment safely"
__fish_conda_top -a spawn -d "Activate conda environments in new shell processes"

# command added by sourcing ~/miniconda3/etc/fish/conf.d/conda.fish,
# which is the recommended way to use conda with fish
__fish_conda_top -a activate -d "Activate a conda environment"
__fish_conda activate -x -a "(__fish_conda_environments)"
__fish_conda_top -a deactivate -d "Deactivate the current conda environment"

# common to all top-level commands

set -l __fish_conda_commands clean compare config create doctor export info install init list notices package pypi remove rename repoquery run search update
for cmd in $__fish_conda_commands
    __fish_conda $cmd -l json -d "Report all output as json"
    __fish_conda $cmd -l console -r -d "Select the backend to use for normal output rendering"
    __fish_conda $cmd -l verbose -s v -d "Use once for info, twice for debug, three times for trace"
    __fish_conda $cmd -l quiet -s q -d "Do not display progress bar"
end

# 'compare' command
__fish_conda compare -F -d "Path to environment file to compare against"

# 'clean' command
__fish_conda clean -s y -l yes -d "Do not ask for confirmation"
__fish_conda clean -s d -l dry-run -d "Only display what would have been done"
__fish_conda clean -s a -l all -d "Remove index cache, unused cache packages, tarballs, and logfiles"
__fish_conda clean -s i -l index-cache -d "Remove index cache"
__fish_conda clean -s p -l packages -d "Remove unused packages from writable package caches"
__fish_conda clean -s t -l tarballs -d "Remove cached package tarballs"
__fish_conda clean -s f -l force-pkgs-dirs -d "Remove *all* writable package caches (breaks environments with symlinks)"
__fish_conda clean -s c -l tempfiles -r -F -d "Remove temporary files that could not be deleted earlier due to being in-use"
__fish_conda clean -s l -l logfiles -d "Remove log files"

# 'config' command

__fish_conda config -l system -d "Write to the system .condarc file"
__fish_conda config -l env -d "Write to the active conda environment .condarc file"
__fish_conda config -l file -d "Write to the given file" -F
__fish_conda config -l show -x -a "(__fish_conda_config_keys)" -d "Display configuration values"
__fish_conda config -l show-sources -d "Display all identified configuration sources"
__fish_conda config -l validate -d "Validate all configuration sources"
__fish_conda config -l describe -x -a "(__fish_conda_config_keys)" -d "Describe configuration parameters"
__fish_conda config -l write-default -d "Write the default configuration to a file"
__fish_conda config -l get -x -a "(__fish_conda_config_keys)" -d "Get a configuration value"
__fish_conda config -l append -r -a "(__fish_conda_config_keys)" -d "Add one configuration value to the end of a list key"
__fish_conda config -l prepend -r -a "(__fish_conda_config_keys)" -d "Add one configuration value to the beginning of a list key"
__fish_conda config -l add -r -a "(__fish_conda_config_keys)" -d "Alias for --prepend"
__fish_conda config -l set -r -a "(__fish_conda_config_keys)" -d "Set a boolean or string key"
__fish_conda config -l remove -x -a "(__fish_conda_config_set_keys)" -d "Remove a configuration value from a list key"
__fish_conda config -f -a "(__fish_conda_config_values) (__fish_conda_config_set_value)"
__fish_conda config -l remove-key -x -a "(__fish_conda_config_set_keys)" -d "Remove a configuration key (and all its values)"
__fish_conda config -l stdin -d "Apply configuration given in yaml format from stdin"

# 'doctor' command
__fish_conda doctor -x -a "altered-files consistency environment-txt file-locking missing-files pinned requests-ca-bundle" -d "Health check name"
__fish_conda doctor -l list -d "List all available health checks and their fix capabilities"
__fish_conda doctor -l fix -l heal -d "Fix issues found by health checks"

# 'export' command
__fish_conda export -l platform -l subdir -r -a "linux-32 linux-64 linux-aarch64 linux-armv7l linux-ppc64 linux-ppc64le linux-riscv64 linux-s390x osx-64 osx-arm64 win-32 win-64 win-arm64 zos-z" -d "Target platform/subdir for export"
__fish_conda export -l override-platforms -d "Override platforms specified in condarc"
__fish_conda export -s f -l file -r -F -d "File name or path for the exported environment"
__fish_conda export -l format -r -x -a "env.yml environment-json environment-yaml explicit json reqs requirements txt yaml yml conda-lock conda-lock-v1 pixi pixi-lock-v6 rattler-lock-v6" -d "Format for the exported environment"
__fish_conda export -l no-builds -d "Remove build specification from dependencies"
__fish_conda export -l ignore-channels -d "Do not include channel names with package names"
__fish_conda export -l from-history -d "Build environment spec from explicit specs in history"

# 'help' command
__fish_conda help -d "Displays a list of available conda commands and their help strings"
__fish_conda help -x -a "$__fish_conda_commands"

# 'init' command
__fish_conda init -x -a "bash fish powershell tcsh xonsh zsh" -d "Shell to initialize"
__fish_conda init -l all -d "Initialize all currently available shells"
__fish_conda init -l condabin -d "Add condabin/ to PATH only, do not install shell function"
__fish_conda init -l user -d "Initialize conda for the current user (default)"
__fish_conda init -l no-user -d "Do not initialize conda for the current user"
__fish_conda init -l system -d "Initialize conda for all users on the system"
__fish_conda init -l reverse -d "Undo effects of last conda init"

# 'info' command
__fish_conda info -l offline -d "Offline mode, don't connect to the Internet."
__fish_conda info -s a -l all -d "Show all information, (environments, license, and system information)"
__fish_conda info -s e -l envs -d "List all known conda environments"
__fish_conda info -s s -l system -d "List environment variables"
__fish_conda info -l base -d "Display base environment path"
__fish_conda info -l size -d "Show conda-managed disk usage for each environment"
__fish_conda info -l unsafe-channels -d "Display list of channels with tokens exposed"

# The remaining commands share many options, so the definitions are written the other way around:
# the outer loop is on the options

# Option channel
for cmd in create export install notices remove search update
    __fish_conda $cmd -s c -l channel -r -d 'Additional channel to search for packages'
end

# Option channel-priority
for cmd in create install update
    __fish_conda $cmd -l channel-priority -d 'Channel priority takes precedence over package version'
end

# Option clobber
for cmd in create install update
    __fish_conda $cmd -l clobber -d 'Allow clobbering of overlapping file paths (no warnings)'
end

# Option clone
__fish_conda create -l clone -x -a "(__fish_conda_environments)" -d "Path to (or name of) existing local environment"

# Option copy
for cmd in create install update
    __fish_conda $cmd -l copy -d 'Install all packages using copies instead of hard- or soft-linking'
end

# Option download-only
for cmd in create install update
    __fish_conda $cmd -l download-only -d 'Solve an environment: populate caches but no linking/unlinking into prefix'
end

# Option dry-run
for cmd in create doctor init install remove rename update
    __fish_conda $cmd -s d -l dry-run -d 'Only display what would have been done'
end

# Option file
for cmd in create install update
    __fish_conda $cmd -l file -d 'Read package versions from the given file' -F
end

# Option force
for cmd in create install remove update
    __fish_conda $cmd -l force -d 'Force install (even when package already installed)'
end

# Option insecure
for cmd in create install remove search update
    __fish_conda $cmd -s k -l insecure -d 'Allow conda to perform "insecure" SSL connections and transfers'
end

# Option mkdir
for cmd in create install update
    __fish_conda $cmd -l mkdir -d 'Create the environment directory if necessary'
end

# Option name
__fish_conda create -s n -l name -d "Name of new environment"
for cmd in compare config doctor export install list package remove rename repoquery run search update
    __fish_conda $cmd -s n -l name -x -a "(__fish_conda_environments)" -d "Name of existing environment"
end

# Option no-channel-priority
for cmd in create install update
    __fish_conda $cmd -l no-channel-priority -l no-channel-pri -l no-chan-pri -d 'Package version takes precedence over channel priority'
end

# Option no-default-packages
__fish_conda create -l no-default-packages -d 'Ignore create_default_packages in the .condarc file'

# Option no-deps
for cmd in create install update
    __fish_conda $cmd -l no-deps -d 'Do not install, update, remove, or change dependencies'
end

# Option no-pin
for cmd in create install remove update
    __fish_conda $cmd -l no-pin -d 'Ignore pinned file'
end

# Option no-show-channel-urls
for cmd in create install list update
    __fish_conda $cmd -l no-show-channel-urls -d "Don't show channel urls"
end

# Option no-update-dependencies
for cmd in create install update
    __fish_conda $cmd -l no-update-dependencies -l no-update-deps -d "Don't update dependencies"
end

# Option offline
for cmd in create install remove search update
    __fish_conda $cmd -l offline -d "Offline mode, don't connect to the Internet"
end

# Option only-deps
for cmd in create install update
    __fish_conda $cmd -l only-deps -d "Only install dependencies"
end

# Option override-channels
for cmd in create export install notices remove search update
    __fish_conda $cmd -s O -l override-channels -d "Do not search default or .condarc channels"
end

# Option prefix
for cmd in compare config create doctor export install list package remove rename repoquery run search update
    __fish_conda $cmd -s p -l prefix -r -F -d "Full path to environment prefix"
end

# Option quiet
for cmd in create install remove update
    __fish_conda $cmd -s q -l quiet -d "Do not display progress bar"
end

# Option show-channel-urls
for cmd in create install list update
    __fish_conda $cmd -l show-channel-urls -d "Show channel urls"
end

# Option update-dependencies
for cmd in create install update
    __fish_conda $cmd -l update-dependencies -l update-deps -d "Update dependencies"
end

# Option use-index-cache
for cmd in create install remove search update
    __fish_conda $cmd -s C -l use-index-cache -d "Use cache of channel index files, even if it has expired"
end

# Option use-local
for cmd in create install notices remove search update
    __fish_conda $cmd -l use-local -d "Use locally built packages"
end

# Option yes
for cmd in create doctor install remove rename update
    __fish_conda $cmd -s y -l yes -d "Do not ask for confirmation"
end

# Option format (create/install/update)
set -l __fish_conda_env_formats "cep-24 environment-yaml env.yml environment.yml explicit requirements.txt requirements reqs"
for cmd in create install update
    __fish_conda $cmd -l format -l env-spec -l environment-specifier -r -x -a "$__fish_conda_env_formats" -d "Format for the environment file"
end

# Option freeze-installed / update-deps / satisfied-skip-solve / update-specs / force-reinstall
for cmd in install update
    __fish_conda $cmd -l freeze-installed -l no-update-deps -d "Do not update or change already-installed dependencies"
    __fish_conda $cmd -l update-deps -d "Update dependencies that have available updates"
    __fish_conda $cmd -s S -l satisfied-skip-solve -d "Exit early if requested specs are already satisfied"
    __fish_conda $cmd -l update-specs -d "Update based on provided specifications"
    __fish_conda $cmd -l force-reinstall -d "Uninstall and reinstall even if already present"
end

# Option no-lock
for cmd in create install notices remove search update
    __fish_conda $cmd -l no-lock -d "Disable locking when reading/updating repodata cache"
end

# Option no-shortcuts / shortcuts-only
for cmd in create install update
    __fish_conda $cmd -l no-shortcuts -d "Don't install start menu shortcuts"
    __fish_conda $cmd -l shortcuts-only -r -d "Install shortcuts only for this package name"
end

# Option override-frozen
for cmd in install remove update
    __fish_conda $cmd -l override-frozen -d "Ignore frozen environment protections"
end

# Option solver
for cmd in create install remove update
    __fish_conda $cmd -l solver -r -x -a "classic libmamba rattler" -d "Choose solver backend"
end

# Option strict-channel-priority
for cmd in create install update
    __fish_conda $cmd -l strict-channel-priority -d "Packages in lower priority channels are not considered if a higher priority channel has the same package"
end

# Option subdir/platform
set -l __fish_conda_subdirs "linux-32 linux-64 linux-aarch64 linux-armv7l linux-ppc64 linux-ppc64le linux-riscv64 linux-s390x osx-64 osx-arm64 win-32 win-64 win-arm64 zos-z"
for cmd in create install search update
    __fish_conda $cmd -l subdir -l platform -r -x -a "$__fish_conda_subdirs" -d "Use packages built for this platform"
end

# Option revision
__fish_conda install -l revision -r -d "Revert to the specified REVISION"

# 'list' options
__fish_conda list -f -a "(__fish_conda_installed_packages)"
__fish_conda list -s c -l canonical -d "Output canonical names of packages only"
__fish_conda list -l explicit -d "List explicitly all installed conda packages with URL"
__fish_conda list -s e -l export -d "Output machine-readable requirement strings"
__fish_conda list -s f -l full-name -d "Only search for full names, i.e., ^<regex>\$"
__fish_conda list -l md5 -d "Add MD5 hashsum when using --explicit"
__fish_conda list -l sha256 -d "Add SHA256 hashsum when using --explicit"
__fish_conda list -l no-pip -d "Do not include pip-only installed packages"
__fish_conda list -l auth -d "Leave authentication details in package URLs"
__fish_conda list -l reverse -d "List installed packages in reverse order"
__fish_conda list -s r -l revisions -d "List the revision history"
__fish_conda list -l size -d "Show package and environment sizes"
__fish_conda list -l fields -r -d "Comma-separated list of fields to print"

# 'remove' options
__fish_conda remove -f -a "(__fish_conda_installed_packages)"
__fish_conda remove -l all -d "Remove all packages, i.e., the entire environment"
__fish_conda remove -l keep-env -d "Delete all packages but keep the environment"
__fish_conda remove -l features -d "Remove features (instead of packages)"
__fish_conda remove -l force-remove -l force -d "Force removal without checking dependents"

# 'search' options
__fish_conda search -s i -l info -d "Provide detailed information about each package"
__fish_conda search -l envs -d "Search all of the current user's environments"

# Option skip-flexible-search
__fish_conda search -l skip-flexible-search -d "Do not perform flexible search if initial search fails"

# 'update' options
__fish_conda update -f -a "(__fish_conda_installed_packages)"
__fish_conda update -l all -d "Update all installed packages in the environment"
__fish_conda update -l update-all -d "Update all installed packages in the environment"
__fish_conda update -l update-specs -d "Update based on provided specifications"

# 'package' command
__fish_conda package -s w -l which -r -F -d "Print which conda package the file came from"
__fish_conda package -s r -l reset -d "Remove all untracked files and exit"
__fish_conda package -s u -l untracked -d "Display all untracked files and exit"
__fish_conda package -l pkg-name -r -d "Package name of the package being created"
__fish_conda package -l pkg-version -r -d "Package version of the package being created"
__fish_conda package -l pkg-build -r -d "Package build number of the package being created"

# 'pypi' command
complete -c conda -n "__fish_conda_subcommand pypi" -x -a "install convert"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi install) install" -a install -d "Install PyPI packages as conda packages"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi convert) convert" -a convert -d "Build and convert sdists/wheels/projects to conda packages"
# pypi install options
complete -c conda -n "contains -- (__fish_conda_subcommand pypi install) install" -l ignore-channels -d "Skip conda channels, search PyPI only"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi install) install" -s i -l index-url -r -d "Add a PyPI index URL"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi install) install" -s p -l prefix -r -F -d "Full path to environment location"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi install) install" -s e -l editable -r -F -d "Build and install path as an editable package"
# pypi convert options
complete -c conda -n "contains -- (__fish_conda_subcommand pypi convert) convert" -F -d "Path to sdist, wheel, or project"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi convert) convert" -l output-folder -r -F -d "Folder to write output package(s)"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi convert) convert" -s e -l editable -d "Build as an editable package"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi convert) convert" -s t -l test-dir -r -F -d "Directory containing test files to inject"
complete -c conda -n "contains -- (__fish_conda_subcommand pypi convert) convert" -l name-mapping -r -F -d "Path to JSON file with PyPI-to-conda name mapping"

# 'rename' command
__fish_conda rename -F -d "New name for the conda environment"

# 'self' command
complete -c conda -n "__fish_conda_subcommand self" -x -a "install remove reset update"
complete -c conda -n "contains -- (__fish_conda_subcommand self) self" -s V -l version -d "Show conda-self version"
# self install
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -l force-reinstall -d "Reinstall plugin even if already installed"
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -l json -d "Report output as json"
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -l console -r -d "Select output rendering backend"
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -s v -l verbose -d "Increase verbosity"
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -s q -l quiet -d "Do not display progress bar"
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -s d -l dry-run -d "Only display what would have been done"
complete -c conda -n "contains -- (__fish_conda_subcommand self install) install" -s y -l yes -d "Do not ask for confirmation"
# self remove
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -l force -d "Remove even permanent packages"
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -l json -d "Report output as json"
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -l console -r -d "Select output rendering backend"
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -s v -l verbose -d "Increase verbosity"
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -s q -l quiet -d "Do not display progress bar"
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -s d -l dry-run -d "Only display what would have been done"
complete -c conda -n "contains -- (__fish_conda_subcommand self remove) remove" -s y -l yes -d "Do not ask for confirmation"
# self reset
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -l snapshot -r -x -a "current installer-exact installer-updated base-protection" -d "Snapshot to reset base environment to"
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -l json -d "Report output as json"
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -l console -r -d "Select output rendering backend"
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -s v -l verbose -d "Increase verbosity"
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -s q -l quiet -d "Do not display progress bar"
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -s d -l dry-run -d "Only display what would have been done"
complete -c conda -n "contains -- (__fish_conda_subcommand self reset) reset" -s y -l yes -d "Do not ask for confirmation"
# self update
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -l force-reinstall -d "Install latest conda even if current is more recent"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -l plugin -r -d "Name of a conda plugin to update"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -l all -d "Update conda, all plugins, and dependencies"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -l json -d "Report output as json"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -l console -r -d "Select output rendering backend"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -s v -l verbose -d "Increase verbosity"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -s q -l quiet -d "Do not display progress bar"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -s d -l dry-run -d "Only display what would have been done"
complete -c conda -n "contains -- (__fish_conda_subcommand self update) update" -s y -l yes -d "Do not ask for confirmation"

# 'spawn' command
set -l __fish_conda_spawn_shells "ash bash cmd.exe cmd csh dash fish posix powershell pwsh tcsh xonsh zsh"
complete -c conda -n "contains -- (__fish_conda_subcommand) spawn" -x -a "(__fish_conda_environments)" -d "Environment to activate"
complete -c conda -n "contains -- (__fish_conda_subcommand) spawn" -l hook -d "Print shell activation logic for in-process sourcing"
complete -c conda -n "contains -- (__fish_conda_subcommand) spawn" -l shell -r -x -a "$__fish_conda_spawn_shells" -d "Shell to use for the new session"
complete -c conda -n "contains -- (__fish_conda_subcommand) spawn" -l replace -d "Allow nested spawn by replacing current environment"
complete -c conda -n "contains -- (__fish_conda_subcommand) spawn" -l stack -d "Allow nested spawn by stacking on current environment"

# 'repoquery' command
complete -c conda -n "__fish_conda_subcommand repoquery" -x -a "whoneeds depends search"
complete -c conda -n "contains -- (__fish_conda_subcommand repoquery whoneeds) whoneeds" -l info -d "Show detailed package info"
complete -c conda -n "contains -- (__fish_conda_subcommand repoquery depends) depends" -l info -d "Show detailed package info"
complete -c conda -n "contains -- (__fish_conda_subcommand repoquery search) search" -l info -d "Show detailed package info"

# 'run' command
__fish_conda run -l cwd -r -F -d "Working directory for the command"
__fish_conda run -s s -l no-capture-output -l live-stream -d "Don't capture stdout/stderr"
__fish_conda run -l debug-wrapper-scripts -d "Print debugging information from shell wrapper scripts"

__fish_conda_top -a env -d "Conda options for environments"
complete -c conda -n "__fish_conda_subcommand env" -a create -d "Create a new environment"
complete -c conda -n "__fish_conda_subcommand env" -a list -d "List all conda environments"
complete -c conda -n "__fish_conda_subcommand env create" -s f -l file -rF -d "Create environment from yaml file"
