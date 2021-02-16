#!/bin/sh


#set -x

# All (good?) defaults
SHADOW_VERBOSE=${SHADOW_VERBOSE:-1}
SHADOW_USER=${SHADOW_USER:-}
MAINDIR=$(readlink -f "$(dirname "$(readlink -f "$0")")/..")
if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi
SHADOW_CONFIG=${SHADOW_CONFIG:-./shadow.cfg}
SHADOW_SRCDIR=${SHADOW_SRCDIR:-}
SHADOW_DSTDIR=${SHADOW_DSTDIR:-.}
SHADOW_DELETE=${SHADOW_DELETE:-0}
SHADOW_LINK=${SHADOW_LINK:-0}
SHADOW_DRYRUN=${SHADOW_DRYRUN:-0}

# Dynamic vars
cmdname=$(basename "$(readlink -f "$0")")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
  exitcode="$1"
  cat << USAGE >&2

Description:

  $cmdname copies files and directories from a source directory to a destination
  prior to running a command. Copy occurs with sudo to bypass restrictions.

Usage:
  $cmdname [-option arg --long-option(=)arg] [--] machine..

  where all dash-led options are as follows (long options can be followed by
  an equal sign):
    --silent            Be as silent as possible
    -c | --config       Configuration where to find copying/linking information
    -s | --source       Main directory at where to find sources
    -d | --dest         Main directory at where to place destinations
    -u | --user         Name of user to force ownership to, will trigger sudo
                        copies.
    -p | --path         Path to (relative) file to copy. Can appear several times.
    -n | --dryrun       Just show what would be done
    --delete            Delete files in destination instead, this is irreversible!
    --link              Create symbolic links to sources instead, will not
                        work if the source files have too restrictive perms.
    --copy              Performs copies (the *good* default)

Details:

  This uses sudo whenever relevant to be able to access the source files and
  directories when copying. This is to make sure the script can bypass
  restrictive permissions: secrets are usually only readable only by the user.

USAGE
  exit "$exitcode"
}


SHADOW_PATH=
# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -c | --config)
            SHADOW_CONFIG=$2; shift 2;;
        --config=*)
            SHADOW_CONFIG="${1#*=}"; shift 1;;

        -s | --source)
            SHADOW_SRCDIR=$2; shift 2;;
        --source=*)
            SHADOW_SRCDIR="${1#*=}"; shift 1;;

        -d | --dest | --destination)
            SHADOW_DSTDIR=$2; shift 2;;
        --dest=* | --destination=*)
            SHADOW_DSTDIR="${1#*=}"; shift 1;;

        -u | --user)
            SHADOW_USER=$2; shift 2;;
        --user=*)
            SHADOW_USER="${1#*=}"; shift 1;;

        -p | --path)
            [ -z "$SHADOW_PATH" ] && SHADOW_PATH=$(mktemp)
            printf %s\\n "$2" >> "$SHADOW_PATH"
            shift 2;;
        --path=*)
            [ -z "$SHADOW_PATH" ] && SHADOW_PATH=$(mktemp)
            printf %s\\n "${1#*=}" >> "$SHADOW_PATH"
            shift 1;;

        --silent)
            SHADOW_VERBOSE=0; shift;;

        --delete)
            SHADOW_DELETE=1; shift;;

        -l | --link)
            SHADOW_LINK=1; shift;;

        --copy)
            SHADOW_LINK=0; shift;;

        -n | --dry-run | --dryrun)
            SHADOW_DRYRUN=1; shift;;

        -h | --help)
            usage 0;;
        --)
            shift; break;;
        -*)
            echo "Unknown option: $1 !" >&2 ; usage 1;;
        *)
            break;;
    esac
done

# Colourisation support for logging and output.
_colour() {
  if [ "$INTERACTIVE" = "1" ]; then
    printf '\033[1;31;'${1}'m%b\033[0m' "$2"
  else
    printf -- "%b" "$2"
  fi
}
green() { _colour "32" "$1"; }
red() { _colour "40" "$1"; }
yellow() { _colour "33" "$1"; }
blue() { _colour "34" "$1"; }

# Conditional logging
log() {
  if [ "$SHADOW_VERBOSE" = "1" ]; then
    echo "[$(blue "$appname")] [$(yellow info)] [$(date +'%Y%m%d-%H%M%S')] $1"
  fi
}

warn() {
  echo "[$(blue "$appname")] [$(red WARN)] [$(date +'%Y%m%d-%H%M%S')] $1"
}

abort() {
  warn "$1"
  exit 1
}


# handle following scenarios:
#   * unprivileged user (i.e. not root, sudo not used)
#   * privileged user (i.e. not root, sudo used)
#   * root user (i.e. sudo not used)
SUDO=''
if [ -n "$SHADOW_USER" ]; then
  if [ "$(id -u)" -ne "0" ]; then
    # verify that 'sudo' is present before assuming we can use it
    if ! command -v sudo 2>&1 >/dev/null; then
      abort "Cannot find sudo"
    fi

    SUDO='sudo'
  fi
fi

shadow() {
  if [ "$SHADOW_LINK" = "1" ]; then
    log "Soft-linking $1 to $2"
    ln -sf "$1" "$2"
  else
    if $SUDO test -d "$1"; then
      log "Recursively copying $1 to $2"
      if [ "$SHADOW_DRYRUN" = "0" ]; then
        if ! [ -d "$2" ]; then
          mkdir "$2"
        fi
        _perms=$($SUDO stat -c "%a" "$1")
        chmod "0$_perms" "$2";      # Change the permissions as the source
      fi
      # Recursively shadow the content of $1
      $SUDO find "$1" -maxdepth 1 -mindepth 1| while IFS= read -r fpath; do
        shadow "$fpath" "${2%%/}/$(basename "$fpath")"
      done
    else
      if [ "$SHADOW_DRYRUN" = "0" ]; then
        _perms=$($SUDO stat -c "%a" "$1")
        _user=$(id -un)
        log "Copying $1 to $2, ownership: $_user, perms: $_perms"
        mkdir -p "$(dirname "$2")"
        $SUDO cp -f "$1" "$2";     # Copy as root to bypass perms
        $SUDO chown "$_user" "$2"; # Give away the copy to us (as root!)
        chmod "0$_perms" "$2";      # Change the permissions as the source
      else
        log "Copying $1 to $2"
      fi
    fi
  fi
}

# If we specified paths in addition to the configuration file, then arrange to
# work with a temporary file that contains the combination of both options.
if [ -n "$SHADOW_PATH" ]; then
  # We specified one or more paths at the command-line (they are in SHADOW_PATH)
  # and also have a config file. Create a new temporary file that contains both
  # the configuration and the paths from the command-line (paths are at the
  # end).
  if [ -n "$SHADOW_CONFIG" ] && [ -f "$SHADOW_CONFIG" ]; then
    _tmp=$(mktemp)
    cat "$SHADOW_CONFIG" > "$_tmp"
    cat "$SHADOW_PATH" >> "$_tmp"
    rm "$SHADOW_PATH";   # Get rid of the temporary file at once.
    SHADOW_PATH=$_tmp
  fi
  # Arrange for the following logic to take its information from the temporary
  # file instead.
  SHADOW_CONFIG=$SHADOW_PATH
fi

# Once here:
# $SHADOW_CONFIG contains the path to a file with all copying directives, wether
# they come from the configuration file from the command-line options, or from
# (repetitive) command-line options (--path).
# $SHADOW_PATH if non-empty, contains the path to a temporary file with cupying
# directives. It might be the same as $SHADOW_CONFIG.

if [ -f "$SHADOW_CONFIG" ]; then
  # Warnings on empty source and/or destination directories...
  [ -z "$SHADOW_DSTDIR" ] && warn "No destination directory, are you sure?!"
  [ -z "$SHADOW_SRCDIR" ] && warn "No source directory, are you sure?!"

  # Create destination, if necessary
  if [ -n "$SHADOW_DSTDIR" ] && ! [ -d "$SHADOW_DSTDIR" ]; then
    log "Creating destination directory at $SHADOW_DSTDIR"
    mkdir -p "$SHADOW_DSTDIR"
  fi

  # Check destination and source are directories, when specified.
  if [ -n "$SHADOW_DSTDIR" ] && ! [ -d "$SHADOW_DSTDIR" ]; then
    abort "Destination directory $SHADOW_DSTDIR is not a directory"
  fi
  if [ -n "$SHADOW_SRCDIR" ] && ! $SUDO test -d "$SHADOW_SRCDIR"; then
    abort "Source directory $SHADOW_SRCDIR is not a directory"
  fi

  # Force a trailing slash to the source and desination directories to
  # facilitate shadowing operations later on.
  if [ -n "$SHADOW_DSTDIR" ]; then
    SHADOW_DSTDIR=${SHADOW_DSTDIR%%/}/
  fi
  if [ -n "$SHADOW_SRCDIR" ]; then
    SHADOW_SRCDIR=${SHADOW_SRCDIR%%/}/
  fi

  while IFS= read -r path; do
    if [ "$SHADOW_DELETE" = "1" ]; then
      if [ -e "${SHADOW_DSTDIR}${path}" ]; then
        log "Removing ${SHADOW_DSTDIR}${path}"
        if [ "$SHADOW_DRYRUN" = "0" ]; then
          rm -f "${SHADOW_DSTDIR}${path}"
        fi
      else
        log "${SHADOW_DSTDIR}${path} does not exist (yet?)! Nothing to remove"
      fi
    else
      if [ -e "${SHADOW_SRCDIR}${path}" ]; then
        shadow "${SHADOW_SRCDIR}${path}" "${SHADOW_DSTDIR}${path}"
      else
        warn "${SHADOW_SRCDIR}${path} does not exist!"
      fi
    fi
  done <<EOF
$(sed -E '/^[[:space:]]*$/d' "${SHADOW_CONFIG}" | sed -E '/^[[:space:]]*#/d')
EOF
fi

# If we had to work with a temporary file, remove it. We are done now.
if [ -n "$SHADOW_PATH" ]; then
  rm "$SHADOW_PATH"
fi

# Execute further the rest of the command-line arguments, with files properly
# copied
[ "$#" -gt "0" ] && exec "$@"
