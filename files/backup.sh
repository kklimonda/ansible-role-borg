#!/bin/bash
source /etc/borg/borg.env

info() { printf "%s %s\n" "$( date )" "$*" >&2; }

trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

info "Running pre scripts"

for script in /etc/borg/pre.d/*; do
    $script
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        info "Script $script returned $exit_code. Aborting backup."
        exit $exit_code
    fi
done

info "Starting backup"

# Backup the most important directories into an archive named after
# the machine this script is currently running on:

/opt/borg/borg create                  \
    --verbose                          \
    --list                             \
    --stats                            \
    --show-rc                          \
    --compression lz4                  \
    --exclude-caches                   \
    --patterns-from /etc/borg/patterns \
                                       \
    ::'{now}'

backup_exit=$?

info "Running post scripts"

for script in /etc/borg/post.d/*; do
    $script
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        info "Script $script returned $exit_code. Aborting backup."
        exit $exit_code
    fi
done


info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

/opt/borg/borg prune                   \
    --list                             \
    --show-rc                          \
    --keep-hourly   $BORG_KEEP_HOURLY  \
    --keep-daily    $BORG_KEEP_DAILY   \
    --keep-weekly   $BORG_KEEP_WEEKLY  \
    --keep-monthly  $BORG_KEEP_MONTHLY

prune_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))

if [ ${global_exit} -eq 1 ];
then
    info "Backup and/or Prune finished with a warning"
fi

if [ ${global_exit} -gt 1 ];
then
    info "Backup and/or Prune finished with an error"
fi

exit ${global_exit}

