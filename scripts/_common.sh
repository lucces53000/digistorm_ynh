#!/bin/bash

# Shared helpers for DigiStorm lifecycle scripts.

source /usr/share/yunohost/helpers

install_node_dependencies() {
    pushd "$install_dir" >/dev/null
        ynh_hide_warnings ynh_exec_as_app npm ci --no-audit --no-fund
        ynh_hide_warnings ynh_exec_as_app env VITE_DEFAULT_LANGUAGE=fr VITE_UPLOAD_LIMIT=5 npm run build
    popd >/dev/null
}

configure_systemd_runtime() {
    ynh_config_add_systemd
    chown root:root "/etc/systemd/system/$app.service"
    chmod 640 "/etc/systemd/system/$app.service"
}

configure_runtime() {
    mkdir -p "$data_dir/fichiers" "$data_dir/temp" "$install_dir/static/temp"
    if [ -d "$install_dir/static/fichiers" ] && [ ! -L "$install_dir/static/fichiers" ]; then
        # Upstream ships an empty placeholder; preserve any files if it is not empty.
        cp -a "$install_dir/static/fichiers/." "$data_dir/fichiers/"
        rmdir "$install_dir/static/fichiers" 2>/dev/null || ynh_safe_rm "$install_dir/static/fichiers"
    elif [ -e "$install_dir/static/fichiers" ] && [ ! -L "$install_dir/static/fichiers" ]; then
        ynh_die "static/fichiers existe mais n'est pas un répertoire ou un lien symbolique valide."
    fi
    ln -sfn "$data_dir/fichiers" "$install_dir/static/fichiers"
    if [ -d "$install_dir/static/temp" ] && [ ! -L "$install_dir/static/temp" ]; then
        rmdir "$install_dir/static/temp" 2>/dev/null || ynh_safe_rm "$install_dir/static/temp"
    fi
    mkdir -p "$data_dir/temp"
    ln -sfn "$data_dir/temp" "$install_dir/static/temp"
    chown -R "$app:$app" "$data_dir"
    chown -R "$app:$app" "$install_dir"
    chmod 750 "$data_dir"
    chmod 750 "$data_dir/fichiers"
    chmod 750 "$data_dir/temp"

    cat > "$data_dir/redis.conf" <<EOF
bind 127.0.0.1
protected-mode yes
port $port_redis
tcp-backlog 128
timeout 0
logfile ""
dir $data_dir
dbfilename dump.rdb
appendonly yes
appendfilename appendonly.aof
appendfsync everysec
pidfile $data_dir/redis.pid
requirepass $db_pwd
EOF
    chown root:"$app" "$data_dir/redis.conf"
    chmod 640 "$data_dir/redis.conf"
}

configure_lti_origins() {
    authorized_domains="https://$domain"

    lti_platform_origins=$(ynh_app_setting_get --key=lti_platform_origins)
    if [ -n "$lti_platform_origins" ]; then
        authorized_domains="$authorized_domains,$lti_platform_origins"
    fi

    ynh_app_setting_set --key=authorized_domains --value="$authorized_domains"
}

patch_lti_tls() {
    local package_dir
    package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [ -f "$package_dir/conf/lti-tls.patch" ] && [ -f "$install_dir/server/lti.js" ]; then
        if ! grep -q "import tls from 'tls'" "$install_dir/server/lti.js"; then
            patch -d "$install_dir" -p1 -i "$package_dir/conf/lti-tls.patch"
        fi
    fi
}
