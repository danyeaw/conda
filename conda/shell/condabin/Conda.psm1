param([parameter(Position=0,Mandatory=$false)] [Hashtable] $CondaModuleArgs=@{})

# Defaults from before we had arguments.
if (-not $CondaModuleArgs.ContainsKey('ChangePs1')) {
    $CondaModuleArgs.ChangePs1 = $True
}

## ENVIRONMENT MANAGEMENT ######################################################

<#
    .SYNOPSIS
        Obtains a list of valid conda environments.

    .EXAMPLE
        Get-CondaEnvironment

    .EXAMPLE
        genv
#>
function Get-CondaEnvironment {
    [CmdletBinding()]
    param();

    begin {}

    process {
        # NB: the JSON output of conda env list does not include the names
        #     of each env, so we need to parse the fragile output instead.
        & $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA env list | `
            Where-Object { -not $_.StartsWith("#") } | `
            Where-Object { -not $_.Trim().Length -eq 0 } | `
            ForEach-Object {
                $envLine = $_ -split "\s+";
                $Active = $envLine[1] -eq "*";
                [PSCustomObject] @{
                    Name = $envLine[0];
                    Active = $Active;
                    Path = if ($Active) {$envLine[2]} else {$envLine[1]};
                } | Write-Output;
            }
    }

    end {}
}

<#
    .SYNOPSIS
        Activates a conda environment, placing its commands and packages at
        the head of $Env:PATH.

    .EXAMPLE
        Enter-CondaEnvironment my-env

    .EXAMPLE
        etenv my-env

    .NOTES
        This command does not currently support activating environments stored
        in a non-standard location.
#>
function Enter-CondaEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][switch]$Stack,
        [Parameter(Position=0)][string]$Name
    );

    begin {
        If ($Stack) {
            $activateCommand = (& $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA shell.powershell activate --stack $Name | Out-String);
        } Else {
            $activateCommand = (& $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA shell.powershell activate $Name | Out-String);
        }

        Write-Verbose "[conda shell.powershell activate $Name]`n$activateCommand";
        Invoke-Expression -Command $activateCommand;
    }

    process {}

    end {}

}

<#
    .SYNOPSIS
        Deactivates the current conda environment, if any.

    .EXAMPLE
        Exit-CondaEnvironment

    .EXAMPLE
        exenv
#>
function Exit-CondaEnvironment {
    [CmdletBinding()]
    param();

    begin {
        $deactivateCommand = (& $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA shell.powershell deactivate | Out-String);

        # If deactivate returns an empty string, we have nothing more to do,
        # so return early.
        if ($deactivateCommand.Trim().Length -eq 0) {
            return;
        }
        Write-Verbose "[conda shell.powershell deactivate]`n$deactivateCommand";
        Invoke-Expression -Command $deactivateCommand;
    }
    process {}
    end {}
}

<#
    .SYNOPSIS
        Runs the conda reactivate command and invokes the resulting shell
        script, if any. Called after install/update/remove/etc. so that
        environment variables set by activate.ps1 are refreshed in the
        current session.
#>
function Invoke-CondaReactivate {
    $reactivateCommand = (& $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA shell.powershell reactivate | Out-String);
    if ($reactivateCommand.Trim().Length -gt 0) {
        Invoke-Expression -Command $reactivateCommand;
    }
}

## CONDA WRAPPER ###############################################################

<#
    .SYNOPSIS
        conda is a tool for managing and deploying applications, environments
        and packages.

    .PARAMETER Command
        Subcommand to invoke.

    .EXAMPLE
        conda install toolz
#>
function Invoke-Conda() {
    # Don't use any explicit args here, we'll use $args and tab completion
    # so that we can capture everything, INCLUDING short options (e.g. -n).
    if ($Args.Count -eq 0) {
        # No args, just call the underlying conda executable.
        & $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA;
    }
    else {
        $Command = $Args[0];
        if ($Args.Count -ge 2) {
            $OtherArgs = $Args[1..($Args.Count - 1)];
        } else {
            $OtherArgs = @();
        }
        switch -Regex ($Command) {
            "^activate$" {
                Enter-CondaEnvironment @OtherArgs;
            }
            "^deactivate$" {
                Exit-CondaEnvironment;
            }

            # Run the command, then reactivate so activate.ps1 runs and env vars
            # (e.g. from packages like proj, GDAL) are set in this session.
            # Matches behavior of conda.sh and conda.bat (see issue #15643).
            "^(install|update|upgrade|remove|uninstall)$" {
                & $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA $Command @OtherArgs;
                $succeeded = $?;
                $exitCode = if (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) { $LASTEXITCODE } else { if ($succeeded) { 0 } else { 1 } };
                if ($succeeded) { Invoke-CondaReactivate }
                if (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) { $global:LASTEXITCODE = $exitCode; }
            }

            default {
                # There may be a command we don't know want to handle
                # differently in the shell wrapper, pass it through
                # verbatim.
                & $Env:CONDA_EXE $Env:_CE_M $Env:_CE_CONDA $Command @OtherArgs;
            }
        }
    }
}

## TAB COMPLETION ##############################################################

function Get-CondaEnvironmentNames {
    [CmdletBinding()]
    param()

    if (-not $Env:CONDA_EXE) { return }
    $condaRoot = Split-Path (Split-Path $Env:CONDA_EXE -Parent) -Parent

    'base'

    $sep = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { ';' } else { ':' }
    $searchDirs = @(Join-Path $condaRoot 'envs')
    if ($Env:CONDA_ENVS_PATH) {
        $searchDirs += $Env:CONDA_ENVS_PATH -split [regex]::Escape($sep)
    }

    foreach ($dir in $searchDirs) {
        if (Test-Path $dir -PathType Container) {
            Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name }
        }
    }
}

function Get-CondaInstalledPackages {
    [CmdletBinding()]
    param(
        [string[]]$Tokens = @()
    )

    $envName = $null
    for ($i = 0; $i -lt ($Tokens.Count - 1); $i++) {
        if ($Tokens[$i] -in '-n', '--name') {
            $envName = $Tokens[$i + 1]
            break
        }
    }

    $metaDir = $null
    if ($envName) {
        if (-not $Env:CONDA_EXE) { return }
        $condaRoot = Split-Path (Split-Path $Env:CONDA_EXE -Parent) -Parent
        $metaDir = [System.IO.Path]::Combine($condaRoot, 'envs', $envName, 'conda-meta')
    } elseif ($Env:CONDA_PREFIX) {
        $metaDir = Join-Path $Env:CONDA_PREFIX 'conda-meta'
    }

    if ($metaDir -and (Test-Path $metaDir -PathType Container)) {
        Get-ChildItem $metaDir -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.BaseName -replace '-\d[^-]*-[^-]+$', '' }
    }
}

# Static subcommand list with descriptions, matching the Fish shell completions.
# A static list avoids spawning a Python subprocess on every Tab press.
$script:CondaSubcommands = [ordered]@{
    activate   = 'Activate a conda environment'
    clean      = 'Remove unused packages and caches'
    compare    = 'Compare packages between conda environments'
    config     = 'Modify configuration values in .condarc'
    create     = 'Create a new conda environment from a list of specified packages'
    deactivate = 'Deactivate the current conda environment'
    doctor     = 'Display a health report for your environment'
    env        = 'Conda options for environments'
    export     = 'Export a given environment'
    info       = 'Display information about current conda install'
    init       = 'Initialize conda for shell interaction'
    install    = 'Install a list of packages into a specified conda environment'
    list       = 'List installed packages in a conda environment'
    notices    = 'Retrieve latest channel notifications'
    package    = 'Low-level conda package utility (EXPERIMENTAL)'
    pypi       = 'Install PyPI packages as conda packages'
    remove     = 'Remove a list of packages from a specified conda environment'
    rename     = 'Rename an existing environment'
    repoquery  = 'Advanced search for repodata'
    run        = 'Run an executable in a conda environment'
    search     = 'Search for packages and display associated information'
    self       = 'Manage your conda base environment safely'
    update     = 'Update conda packages to the latest compatible version'
}

$script:CondaConfigKeys = @(
    'add_anaconda_token', 'add_pip_as_python_dependency', 'aggressive_update_packages',
    'allow_conda_downgrades', 'allow_cycles', 'allow_non_channel_urls', 'allow_softlinks',
    'allowlist_channels', 'always_copy', 'always_softlink', 'always_yes',
    'anaconda_anon_usage', 'anaconda_heartbeat', 'anaconda_upload', 'auto_activate',
    'auto_stack', 'auto_update_conda', 'bld_path', 'changeps1', 'channel_alias',
    'channel_priority', 'channel_settings', 'channels', 'client_ssl_cert',
    'client_ssl_cert_key', 'clobber', 'conda_build', 'console', 'create_default_packages',
    'croot', 'custom_channels', 'custom_multichannels', 'debug', 'default_activation_env',
    'default_channels', 'default_python', 'default_threads', 'denylist_channels',
    'deps_modifier', 'dev', 'disallowed_packages', 'download_only', 'dry_run',
    'enable_private_envs', 'env_prompt', 'environment_specifier', 'envs_dirs',
    'envvars_force_uppercase', 'error_upload_url', 'execute_threads', 'experimental',
    'export_platforms', 'extra_safety_checks', 'fetch_threads', 'force', 'force_32bit',
    'force_reinstall', 'force_remove', 'ignore_pinned', 'json', 'list_fields',
    'local_repodata_ttl', 'migrated_channel_aliases', 'migrated_custom_channels',
    'no_lock', 'no_plugins', 'non_admin_enabled', 'notify_outdated_conda',
    'number_channel_notices', 'offline', 'override_channels_enabled',
    'override_virtual_packages', 'path_conflict', 'pinned_packages', 'pkgs_dirs',
    'plugins', 'prefix_data_interoperability', 'protect_frozen_envs', 'proxy_servers',
    'quiet', 'register_envs', 'remote_backoff_factor', 'remote_connect_timeout_secs',
    'remote_max_retries', 'remote_read_timeout_secs', 'repodata_fns', 'repodata_threads',
    'repodata_use_zst', 'report_errors', 'rollback_enabled', 'root_prefix',
    'safety_checks', 'sat_solver', 'separate_format_cache', 'shortcuts',
    'shortcuts_only', 'show_channel_urls', 'signing_metadata_url_base', 'solver',
    'solver_ignore_timestamps', 'ssl_verify', 'subdir', 'subdirs',
    'target_prefix_override', 'trace', 'track_features', 'unsatisfiable_hints',
    'unsatisfiable_hints_check_depth', 'update_modifier', 'use_index_cache',
    'use_local', 'use_only_tar_bz2', 'verbosity', 'verify_threads'
)

$script:CondaCommonFlags = [ordered]@{
    '--json'    = 'Report all output as json'
    '--console' = 'Select the backend to use for normal output rendering'
    '-v'        = 'Use once for info, twice for debug, three times for trace'
    '--verbose' = 'Use once for info, twice for debug, three times for trace'
    '-q'        = 'Do not display progress bar'
    '--quiet'   = 'Do not display progress bar'
    '-h'        = 'Show help and exit'
    '--help'    = 'Show help and exit'
}

# Shared flag set for create / install / update (common subset).
$_cifBase = [ordered]@{
    '-n'                       = 'Name of environment'
    '--name'                   = 'Name of environment'
    '-p'                       = 'Full path to environment prefix'
    '--prefix'                 = 'Full path to environment prefix'
    '-c'                       = 'Additional channel to search for packages'
    '--channel'                = 'Additional channel to search for packages'
    '-O'                       = 'Do not search default or .condarc channels'
    '--override-channels'      = 'Do not search default or .condarc channels'
    '-d'                       = 'Only display what would have been done'
    '--dry-run'                = 'Only display what would have been done'
    '-y'                       = 'Do not ask for confirmation'
    '--yes'                    = 'Do not ask for confirmation'
    '-k'                       = 'Allow conda to perform insecure SSL connections and transfers'
    '--insecure'               = 'Allow conda to perform insecure SSL connections and transfers'
    '--file'                   = 'Read package versions from the given file'
    '--solver'                 = 'Choose solver backend'
    '--format'                 = 'Format for the environment file'
    '--env-spec'               = 'Format for the environment file'
    '--environment-specifier'  = 'Format for the environment file'
    '--force'                  = 'Force install (even when package already installed)'
    '--channel-priority'       = 'Channel priority takes precedence over package version'
    '--no-channel-priority'    = 'Package version takes precedence over channel priority'
    '--clobber'                = 'Allow clobbering of overlapping file paths'
    '--copy'                   = 'Install all packages using copies instead of hard- or soft-linking'
    '--download-only'          = 'Solve an environment but don''t link/unlink into prefix'
    '--offline'                = 'Offline mode, don''t connect to the Internet'
    '--only-deps'              = 'Only install dependencies'
    '--no-deps'                = 'Do not install, update, remove, or change dependencies'
    '--no-pin'                 = 'Ignore pinned file'
    '--mkdir'                  = 'Create the environment directory if necessary'
    '--show-channel-urls'      = 'Show channel urls'
    '--no-show-channel-urls'   = 'Don''t show channel urls'
    '--update-dependencies'    = 'Update dependencies'
    '--no-update-dependencies' = 'Don''t update dependencies'
    '--use-index-cache'        = 'Use cache of channel index files, even if it has expired'
    '--use-local'              = 'Use locally built packages'
    '--no-lock'                = 'Disable locking when reading/updating repodata cache'
    '--no-shortcuts'           = 'Don''t install start menu shortcuts'
    '--shortcuts-only'         = 'Install shortcuts only for this package name'
    '--strict-channel-priority' = 'Packages in lower priority channels are not considered if a higher priority channel has the same package'
    '--subdir'                 = 'Use packages built for this platform'
    '--platform'               = 'Use packages built for this platform'
}

$_installFlags = [ordered]@{}
$_cifBase.GetEnumerator() | ForEach-Object { $_installFlags[$_.Key] = $_.Value }
$_installFlags['--force-reinstall']      = 'Uninstall and reinstall even if already present'
$_installFlags['--freeze-installed']     = 'Do not update or change already-installed dependencies'
$_installFlags['-S']                     = 'Exit early if requested specs are already satisfied'
$_installFlags['--satisfied-skip-solve'] = 'Exit early if requested specs are already satisfied'
$_installFlags['--update-specs']         = 'Update based on provided specifications'
$_installFlags['--override-frozen']      = 'Ignore frozen environment protections'
$_installFlags['--revision']             = 'Revert to the specified REVISION'

$_createFlags = [ordered]@{}
$_cifBase.GetEnumerator() | ForEach-Object { $_createFlags[$_.Key] = $_.Value }
$_createFlags['--clone']               = 'Path to (or name of) existing local environment'
$_createFlags['--no-default-packages'] = 'Ignore create_default_packages in the .condarc file'

$_updateFlags = [ordered]@{}
$_cifBase.GetEnumerator() | ForEach-Object { $_updateFlags[$_.Key] = $_.Value }
$_updateFlags['--force-reinstall']      = 'Uninstall and reinstall even if already present'
$_updateFlags['--freeze-installed']     = 'Do not update or change already-installed dependencies'
$_updateFlags['-S']                     = 'Exit early if requested specs are already satisfied'
$_updateFlags['--satisfied-skip-solve'] = 'Exit early if requested specs are already satisfied'
$_updateFlags['--update-specs']         = 'Update based on provided specifications'
$_updateFlags['--override-frozen']      = 'Ignore frozen environment protections'
$_updateFlags['--all']                  = 'Update all installed packages in the environment'
$_updateFlags['--update-all']           = 'Update all installed packages in the environment'

$_removeFlags = [ordered]@{
    '-n'                  = 'Name of existing environment'
    '--name'              = 'Name of existing environment'
    '-p'                  = 'Full path to environment prefix'
    '--prefix'            = 'Full path to environment prefix'
    '-c'                  = 'Additional channel to search for packages'
    '--channel'           = 'Additional channel to search for packages'
    '-O'                  = 'Do not search default or .condarc channels'
    '--override-channels' = 'Do not search default or .condarc channels'
    '-y'                  = 'Do not ask for confirmation'
    '--yes'               = 'Do not ask for confirmation'
    '-d'                  = 'Only display what would have been done'
    '--dry-run'           = 'Only display what would have been done'
    '-k'                  = 'Allow conda to perform insecure SSL connections and transfers'
    '--insecure'          = 'Allow conda to perform insecure SSL connections and transfers'
    '--all'               = 'Remove all packages, i.e., the entire environment'
    '--keep-env'          = 'Delete all packages but keep the environment'
    '--features'          = 'Remove features (instead of packages)'
    '--force-remove'      = 'Force removal without checking dependents'
    '--force'             = 'Force removal without checking dependents'
    '--offline'           = 'Offline mode, don''t connect to the Internet'
    '--no-pin'            = 'Ignore pinned file'
    '--solver'            = 'Choose solver backend'
    '--no-lock'           = 'Disable locking when reading/updating repodata cache'
    '--override-frozen'   = 'Ignore frozen environment protections'
    '--use-index-cache'   = 'Use cache of channel index files, even if it has expired'
}

$script:CondaCommandFlags = @{
    'clean'    = [ordered]@{
        '-y'                = 'Do not ask for confirmation'
        '--yes'             = 'Do not ask for confirmation'
        '-d'                = 'Only display what would have been done'
        '--dry-run'         = 'Only display what would have been done'
        '-a'                = 'Remove index cache, unused cache packages, tarballs, and logfiles'
        '--all'             = 'Remove index cache, unused cache packages, tarballs, and logfiles'
        '-i'                = 'Remove index cache'
        '--index-cache'     = 'Remove index cache'
        '-p'                = 'Remove unused packages from writable package caches'
        '--packages'        = 'Remove unused packages from writable package caches'
        '-t'                = 'Remove cached package tarballs'
        '--tarballs'        = 'Remove cached package tarballs'
        '-f'                = 'Remove *all* writable package caches'
        '--force-pkgs-dirs' = 'Remove *all* writable package caches'
        '-c'                = 'Remove temporary files that could not be deleted earlier'
        '--tempfiles'       = 'Remove temporary files that could not be deleted earlier'
        '-l'                = 'Remove log files'
        '--logfiles'        = 'Remove log files'
    }
    'compare'  = [ordered]@{
        '-n'       = 'Name of existing environment'
        '--name'   = 'Name of existing environment'
        '-p'       = 'Full path to environment prefix'
        '--prefix' = 'Full path to environment prefix'
        '-f'       = 'Path to environment file to compare against'
        '--file'   = 'Path to environment file to compare against'
    }
    'config'   = [ordered]@{
        '-n'              = 'Name of existing environment'
        '--name'          = 'Name of existing environment'
        '-p'              = 'Full path to environment prefix'
        '--prefix'        = 'Full path to environment prefix'
        '--system'        = 'Write to the system .condarc file'
        '--env'           = 'Write to the active conda environment .condarc file'
        '--file'          = 'Write to the given file'
        '--show'          = 'Display configuration values'
        '--show-sources'  = 'Display all identified configuration sources'
        '--validate'      = 'Validate all configuration sources'
        '--describe'      = 'Describe configuration parameters'
        '--write-default' = 'Write the default configuration to a file'
        '--get'           = 'Get a configuration value'
        '--append'        = 'Add one configuration value to the end of a list key'
        '--prepend'       = 'Add one configuration value to the beginning of a list key'
        '--add'           = 'Alias for --prepend'
        '--set'           = 'Set a boolean or string key'
        '--remove'        = 'Remove a configuration value from a list key'
        '--remove-key'    = 'Remove a configuration key (and all its values)'
        '--stdin'         = 'Apply configuration given in yaml format from stdin'
    }
    'create'   = $_createFlags
    'doctor'   = [ordered]@{
        '-n'        = 'Name of existing environment'
        '--name'    = 'Name of existing environment'
        '-p'        = 'Full path to environment prefix'
        '--prefix'  = 'Full path to environment prefix'
        '-d'        = 'Only display what would have been done'
        '--dry-run' = 'Only display what would have been done'
        '-y'        = 'Do not ask for confirmation'
        '--yes'     = 'Do not ask for confirmation'
        '--list'    = 'List all available health checks and their fix capabilities'
        '--fix'     = 'Fix issues found by health checks'
        '--heal'    = 'Fix issues found by health checks'
    }
    'export'   = [ordered]@{
        '-n'                   = 'Name of existing environment'
        '--name'               = 'Name of existing environment'
        '-p'                   = 'Full path to environment prefix'
        '--prefix'             = 'Full path to environment prefix'
        '-c'                   = 'Additional channel to search for packages'
        '--channel'            = 'Additional channel to search for packages'
        '-O'                   = 'Do not search default or .condarc channels'
        '--override-channels'  = 'Do not search default or .condarc channels'
        '-f'                   = 'File name or path for the exported environment'
        '--file'               = 'File name or path for the exported environment'
        '--platform'           = 'Target platform/subdir for export'
        '--subdir'             = 'Target platform/subdir for export'
        '--override-platforms' = 'Override platforms specified in condarc'
        '--format'             = 'Format for the exported environment'
        '--no-builds'          = 'Remove build specification from dependencies'
        '--ignore-channels'    = 'Do not include channel names with package names'
        '--from-history'       = 'Build environment spec from explicit specs in history'
    }
    'info'     = [ordered]@{
        '--offline'         = 'Offline mode, don''t connect to the Internet'
        '-a'                = 'Show all information, (environments, license, and system information)'
        '--all'             = 'Show all information, (environments, license, and system information)'
        '-e'                = 'List all known conda environments'
        '--envs'            = 'List all known conda environments'
        '-s'                = 'List environment variables'
        '--system'          = 'List environment variables'
        '--base'            = 'Display base environment path'
        '--size'            = 'Show conda-managed disk usage for each environment'
        '--unsafe-channels' = 'Display list of channels with tokens exposed'
    }
    'init'     = [ordered]@{
        '--all'      = 'Initialize all currently available shells'
        '--condabin' = 'Add condabin/ to PATH only, do not install shell function'
        '--user'     = 'Initialize conda for the current user (default)'
        '--no-user'  = 'Do not initialize conda for the current user'
        '--system'   = 'Initialize conda for all users on the system'
        '--reverse'  = 'Undo effects of last conda init'
        '-d'         = 'Only display what would have been done'
        '--dry-run'  = 'Only display what would have been done'
    }
    'install'  = $_installFlags
    'list'     = [ordered]@{
        '-n'                     = 'Name of existing environment'
        '--name'                 = 'Name of existing environment'
        '-p'                     = 'Full path to environment prefix'
        '--prefix'               = 'Full path to environment prefix'
        '-c'                     = 'Output canonical names of packages only'
        '--canonical'            = 'Output canonical names of packages only'
        '--explicit'             = 'List explicitly all installed conda packages with URL'
        '-e'                     = 'Output machine-readable requirement strings'
        '--export'               = 'Output machine-readable requirement strings'
        '-f'                     = 'Only search for full names'
        '--full-name'            = 'Only search for full names'
        '--md5'                  = 'Add MD5 hashsum when using --explicit'
        '--sha256'               = 'Add SHA256 hashsum when using --explicit'
        '--no-pip'               = 'Do not include pip-only installed packages'
        '--auth'                 = 'Leave authentication details in package URLs'
        '--reverse'              = 'List installed packages in reverse order'
        '-r'                     = 'List the revision history'
        '--revisions'            = 'List the revision history'
        '--size'                 = 'Show package and environment sizes'
        '--fields'               = 'Comma-separated list of fields to print'
        '--show-channel-urls'    = 'Show channel urls'
        '--no-show-channel-urls' = 'Don''t show channel urls'
    }
    'notices'  = [ordered]@{
        '-c'                  = 'Additional channel to search for packages'
        '--channel'           = 'Additional channel to search for packages'
        '-O'                  = 'Do not search default or .condarc channels'
        '--override-channels' = 'Do not search default or .condarc channels'
        '--no-lock'           = 'Disable locking when reading/updating repodata cache'
    }
    'package'  = [ordered]@{
        '-n'            = 'Name of existing environment'
        '--name'        = 'Name of existing environment'
        '-p'            = 'Full path to environment prefix'
        '--prefix'      = 'Full path to environment prefix'
        '-w'            = 'Print which conda package the file came from'
        '--which'       = 'Print which conda package the file came from'
        '-r'            = 'Remove all untracked files and exit'
        '--reset'       = 'Remove all untracked files and exit'
        '-u'            = 'Display all untracked files and exit'
        '--untracked'   = 'Display all untracked files and exit'
        '--pkg-name'    = 'Package name of the package being created'
        '--pkg-version' = 'Package version of the package being created'
        '--pkg-build'   = 'Package build number of the package being created'
    }
    'remove'    = $_removeFlags
    'uninstall' = $_removeFlags
    'rename'   = [ordered]@{
        '-n'        = 'Name of existing environment'
        '--name'    = 'Name of existing environment'
        '-p'        = 'Full path to environment prefix'
        '--prefix'  = 'Full path to environment prefix'
        '-d'        = 'Only display what would have been done'
        '--dry-run' = 'Only display what would have been done'
        '-y'        = 'Do not ask for confirmation'
        '--yes'     = 'Do not ask for confirmation'
    }
    'repoquery' = [ordered]@{
        '-n'                  = 'Name of existing environment'
        '--name'              = 'Name of existing environment'
        '-p'                  = 'Full path to environment prefix'
        '--prefix'            = 'Full path to environment prefix'
        '-c'                  = 'Additional channel to search for packages'
        '--channel'           = 'Additional channel to search for packages'
        '-O'                  = 'Do not search default or .condarc channels'
        '--override-channels' = 'Do not search default or .condarc channels'
    }
    'run'      = [ordered]@{
        '-n'                      = 'Name of existing environment'
        '--name'                  = 'Name of existing environment'
        '-p'                      = 'Full path to environment prefix'
        '--prefix'                = 'Full path to environment prefix'
        '--cwd'                   = 'Working directory for the command'
        '-s'                      = 'Don''t capture stdout/stderr'
        '--no-capture-output'     = 'Don''t capture stdout/stderr'
        '--live-stream'           = 'Don''t capture stdout/stderr'
        '--debug-wrapper-scripts' = 'Print debugging information from shell wrapper scripts'
    }
    'search'   = [ordered]@{
        '-n'                     = 'Name of existing environment'
        '--name'                 = 'Name of existing environment'
        '-p'                     = 'Full path to environment prefix'
        '--prefix'               = 'Full path to environment prefix'
        '-c'                     = 'Additional channel to search for packages'
        '--channel'              = 'Additional channel to search for packages'
        '-O'                     = 'Do not search default or .condarc channels'
        '--override-channels'    = 'Do not search default or .condarc channels'
        '-i'                     = 'Provide detailed information about each package'
        '--info'                 = 'Provide detailed information about each package'
        '--envs'                 = 'Search all of the current user''s environments'
        '--skip-flexible-search' = 'Do not perform flexible search if initial search fails'
        '-k'                     = 'Allow conda to perform insecure SSL connections and transfers'
        '--insecure'             = 'Allow conda to perform insecure SSL connections and transfers'
        '--offline'              = 'Offline mode, don''t connect to the Internet'
        '--subdir'               = 'Use packages built for this platform'
        '--platform'             = 'Use packages built for this platform'
        '--use-index-cache'      = 'Use cache of channel index files, even if it has expired'
    }
    'update'   = $_updateFlags
    'upgrade'  = $_updateFlags
    'self/install' = [ordered]@{
        '--force-reinstall' = 'Reinstall plugin even if already installed'
        '-d'                = 'Only display what would have been done'
        '--dry-run'         = 'Only display what would have been done'
        '-y'                = 'Do not ask for confirmation'
        '--yes'             = 'Do not ask for confirmation'
    }
    'self/remove' = [ordered]@{
        '--force'   = 'Remove even permanent packages'
        '-d'        = 'Only display what would have been done'
        '--dry-run' = 'Only display what would have been done'
        '-y'        = 'Do not ask for confirmation'
        '--yes'     = 'Do not ask for confirmation'
    }
    'self/reset' = [ordered]@{
        '--snapshot' = 'Snapshot to reset base environment to'
        '-d'         = 'Only display what would have been done'
        '--dry-run'  = 'Only display what would have been done'
        '-y'         = 'Do not ask for confirmation'
        '--yes'      = 'Do not ask for confirmation'
    }
    'self/update' = [ordered]@{
        '--force-reinstall' = 'Install latest conda even if current is more recent'
        '--plugin'          = 'Name of a conda plugin to update'
        '--all'             = 'Update conda, all plugins, and dependencies'
        '-d'                = 'Only display what would have been done'
        '--dry-run'         = 'Only display what would have been done'
        '-y'                = 'Do not ask for confirmation'
        '--yes'             = 'Do not ask for confirmation'
    }
    'pypi/install' = [ordered]@{
        '--ignore-channels' = 'Skip conda channels, search PyPI only'
        '-i'                = 'Add a PyPI index URL'
        '--index-url'       = 'Add a PyPI index URL'
        '-p'                = 'Full path to environment location'
        '--prefix'          = 'Full path to environment location'
        '-e'                = 'Build and install path as an editable package'
        '--editable'        = 'Build and install path as an editable package'
    }
    'pypi/convert' = [ordered]@{
        '--output-folder' = 'Folder to write output package(s)'
        '-e'              = 'Build as an editable package'
        '--editable'      = 'Build as an editable package'
        '-t'              = 'Directory containing test files to inject'
        '--test-dir'      = 'Directory containing test files to inject'
        '--name-mapping'  = 'Path to JSON file with PyPI-to-conda name mapping'
    }
    'repoquery/whoneeds' = [ordered]@{ '--info' = 'Show detailed package info' }
    'repoquery/depends'  = [ordered]@{ '--info' = 'Show detailed package info' }
    'repoquery/search'   = [ordered]@{ '--info' = 'Show detailed package info' }
    'env/create'         = [ordered]@{
        '-f'     = 'Create environment from yaml file'
        '--file' = 'Create environment from yaml file'
    }
}

Remove-Variable _cifBase, _installFlags, _createFlags, _updateFlags, _removeFlags

Register-ArgumentCompleter -Native -CommandName conda -ScriptBlock {
    param([string]$wordToComplete, $commandAst, [int]$cursorPosition)

    $allTokens = @($commandAst.CommandElements | Select-Object -Skip 1 |
        ForEach-Object { $_.Extent.Text })

    # Split into "already complete" tokens vs the word currently being typed.
    $tokens = if ($allTokens.Count -gt 0 -and $allTokens[-1] -eq $wordToComplete) {
        if ($allTokens.Count -gt 1) { $allTokens[0..($allTokens.Count - 2)] } else { @() }
    } else {
        $allTokens
    }

    $prevToken   = if ($tokens.Count -gt 0) { $tokens[-1] } else { $null }
    $positionals = @($tokens | Where-Object { $_ -notmatch '^-' })
    $topCmd      = if ($positionals.Count -ge 1) { $positionals[0] } else { $null }
    $subCmd      = if ($positionals.Count -ge 2) { $positionals[1] } else { $null }

    function New-Completion {
        param([string]$Text, [string]$ToolTip = '')
        $tip = if ($ToolTip) { $ToolTip } else { $Text }
        [System.Management.Automation.CompletionResult]::new(
            $Text, $Text,
            [System.Management.Automation.CompletionResultType]::ParameterValue,
            $tip
        )
    }

    # No subcommand yet: complete top-level subcommand names.
    if (-not $topCmd) {
        $script:CondaSubcommands.GetEnumerator() |
            Where-Object { $_.Key -like "$wordToComplete*" } |
            ForEach-Object { New-Completion $_.Key $_.Value }
        return
    }

    # Preceding flag takes a value: complete that value.
    switch -Regex ($prevToken) {
        '^(-n|--name|--clone)$' {
            Get-CondaEnvironmentNames |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^--solver$' {
            'classic', 'libmamba', 'rattler' |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^--channel-priority$' {
            'strict', 'flexible', 'disabled' |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^(--subdir|--platform)$' {
            'linux-32', 'linux-64', 'linux-aarch64', 'linux-armv7l', 'linux-ppc64',
            'linux-ppc64le', 'linux-riscv64', 'linux-s390x', 'osx-64', 'osx-arm64',
            'win-32', 'win-64', 'win-arm64', 'zos-z' |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^(--format|--env-spec|--environment-specifier)$' {
            $exportFormats = @(
                'env.yml', 'environment-json', 'environment-yaml', 'explicit', 'json',
                'reqs', 'requirements', 'txt', 'yaml', 'yml', 'conda-lock',
                'conda-lock-v1', 'pixi', 'pixi-lock-v6', 'rattler-lock-v6'
            )
            $envFormats = @(
                'cep-24', 'environment-yaml', 'env.yml', 'environment.yml', 'explicit',
                'requirements.txt', 'requirements', 'reqs'
            )
            $formats = if ($topCmd -eq 'export') { $exportFormats } else { $envFormats }
            $formats |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^--snapshot$' {
            'current', 'installer-exact', 'installer-updated', 'base-protection' |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^--shell$' {
            'ash', 'bash', 'cmd.exe', 'csh', 'dash', 'fish', 'posix',
            'powershell', 'pwsh', 'tcsh', 'xonsh', 'zsh' |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
            return
        }
        '^(--show|--get|--describe|--append|--prepend|--add|--set)$' {
            if ($topCmd -eq 'config') {
                $script:CondaConfigKeys |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
                return
            }
        }
        '^(--remove|--remove-key)$' {
            if ($topCmd -eq 'config') {
                if ($null -eq $script:CondaSetConfigKeys) {
                    $script:CondaSetConfigKeys = @()
                    if (-not $script:CondaExeResolved) {
                        $script:CondaExeResolved = $true
                        $script:CondaExe = if ($Env:CONDA_EXE) { $Env:CONDA_EXE } else {
                            (Get-Command conda -CommandType Application -ErrorAction SilentlyContinue |
                                Select-Object -First 1).Source
                        }
                    }
                    if ($script:CondaExe) {
                        $ceArgs = @()
                        if ($Env:_CE_M)     { $ceArgs += $Env:_CE_M }
                        if ($Env:_CE_CONDA) { $ceArgs += $Env:_CE_CONDA }
                        $script:CondaSetConfigKeys = & $script:CondaExe @ceArgs config --show-sources 2>$null |
                            Where-Object { $_ -match '^\w+:' } |
                            ForEach-Object { [regex]::Match($_, '^(\w+):').Groups[1].Value }
                    }
                }
                $script:CondaSetConfigKeys |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
                return
            }
        }
    }

    # config --set <key> <TAB>: complete the value for that config key.
    if ($topCmd -eq 'config' -and $tokens.Count -ge 2 -and $tokens[-2] -eq '--set') {
        $cfgKey = $tokens[-1]
        $cfgValues = switch ($cfgKey) {
            'solver'           { @('classic', 'libmamba', 'rattler') }
            'channel_priority' { @('strict', 'flexible', 'disabled') }
            'verbosity'        { @('0', '1', '2', '3') }
            default            { @() }
        }
        if ($cfgValues.Count -eq 0) {
            if (-not $script:CondaBoolConfigKeys) {
                $script:CondaBoolConfigKeys = [System.Collections.Generic.HashSet[string]]::new()
                # Lazy exe resolution, cached with a sentinel to avoid repeated Get-Command calls.
                if (-not $script:CondaExeResolved) {
                    $script:CondaExeResolved = $true
                    $script:CondaExe = if ($Env:CONDA_EXE) { $Env:CONDA_EXE } else {
                        (Get-Command conda -CommandType Application -ErrorAction SilentlyContinue |
                            Select-Object -First 1).Source
                    }
                }
                if ($script:CondaExe) {
                    $ceArgs = @()
                    if ($Env:_CE_M)     { $ceArgs += $Env:_CE_M }
                    if ($Env:_CE_CONDA) { $ceArgs += $Env:_CE_CONDA }
                    & $script:CondaExe @ceArgs config --show 2>$null |
                        Where-Object { $_ -match ': (True|False)$' } |
                        ForEach-Object {
                            [void]$script:CondaBoolConfigKeys.Add(($_ -split ':')[0].Trim())
                        }
                }
            }
            if ($script:CondaBoolConfigKeys.Contains($cfgKey)) {
                $cfgValues = @('True', 'False')
            }
        }
        $cfgValues |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { New-Completion $_ }
        return
    }

    # Flag completion: when word starts with -, return command-specific flags with descriptions.
    if ($wordToComplete -like '-*') {
        $flagKey = if ($subCmd) { "$topCmd/$subCmd" } else { $topCmd }
        $flagSet = [System.Collections.Generic.Dictionary[string,string]]::new()
        foreach ($p in $script:CondaCommonFlags.GetEnumerator()) { $flagSet[$p.Key] = $p.Value }
        if ($script:CondaCommandFlags.ContainsKey($flagKey)) {
            foreach ($p in $script:CondaCommandFlags[$flagKey].GetEnumerator()) { $flagSet[$p.Key] = $p.Value }
        }
        $flagSet.GetEnumerator() |
            Where-Object { $_.Key -like "$wordToComplete*" } |
            Sort-Object Key |
            ForEach-Object { New-Completion $_.Key $_.Value }
        return
    }

    # Subcommand-specific positional completions.
    switch ($topCmd) {
        'activate' {
            Get-CondaEnvironmentNames |
                Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { New-Completion $_ }
        }
        { $_ -in 'remove', 'uninstall', 'update', 'upgrade', 'list' } {
            if ($wordToComplete -notlike '-*') {
                Get-CondaInstalledPackages -Tokens $tokens |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
        'init' {
            if (-not $subCmd) {
                'bash', 'fish', 'powershell', 'tcsh', 'xonsh', 'zsh' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
        'repoquery' {
            if (-not $subCmd) {
                'whoneeds', 'depends', 'search' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
        'self' {
            if (-not $subCmd) {
                'install', 'remove', 'reset', 'update' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
        'env' {
            if (-not $subCmd) {
                'create', 'list' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
        'pypi' {
            if (-not $subCmd) {
                'install', 'convert' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
        'doctor' {
            if (-not $subCmd) {
                'altered-files', 'consistency', 'environment-txt', 'file-locking',
                'missing-files', 'pinned', 'requests-ca-bundle' |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { New-Completion $_ }
            }
        }
    }
}

## PROMPT MANAGEMENT ###########################################################

<#
    .SYNOPSIS
        Modifies the current prompt to show the currently activated conda
        environment, if any.
    .EXAMPLE
        Add-CondaEnvironmentToPrompt

        Causes the current session's prompt to display the currently activated
        conda environment.
#>
if ($CondaModuleArgs.ChangePs1) {
    if (Test-Path Function:\prompt) {
        Rename-Item Function:\prompt CondaPromptBackup
    } else {
        function CondaPromptBackup() {
            # Restore a basic prompt if the definition is missing.
            "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) ";
        }
    }

    function global:prompt() {
        if ($Env:CONDA_PROMPT_MODIFIER) {
            $Env:CONDA_PROMPT_MODIFIER | Write-Host -NoNewline
        }
        CondaPromptBackup;
    }
}

## ALIASES #####################################################################

New-Alias conda Invoke-Conda -Force
New-Alias genv Get-CondaEnvironment -Force
New-Alias etenv Enter-CondaEnvironment -Force
New-Alias exenv Exit-CondaEnvironment -Force

## EXPORTS ###################################################################

Export-ModuleMember `
    -Alias * `
    -Function `
        Invoke-Conda, `
        Get-CondaEnvironment, `
        Enter-CondaEnvironment, Exit-CondaEnvironment, `
        prompt
