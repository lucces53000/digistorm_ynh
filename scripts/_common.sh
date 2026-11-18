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
        lti_platform_origins=$(python3 -c 'import sys, urllib.parse
origins = []
for value in sys.argv[1].split(","):
    value = value.strip()
    if not value:
        continue
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme in ("http", "https") and parsed.hostname:
        origins.append(parsed.scheme.lower() + "://" + parsed.netloc)
print(",".join(origins))' "$lti_platform_origins")
        if [ -n "$lti_platform_origins" ]; then
            authorized_domains="$authorized_domains,$lti_platform_origins"
        fi
    fi

    ynh_app_setting_set --key=authorized_domains --value="$authorized_domains"
}

patch_lti_tls() {
    python3 - "$install_dir/server/lti.js" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = text.replace("import net from 'net'\n", "import net from 'net'\nimport tls from 'tls'\n", 1)
text = text.replace(
    "import { Agent, buildConnector, fetch as fetchSecurise } from 'undici'",
    "import { Agent, fetch as fetchSecurise } from 'undici'",
    1,
)

start_marker = "const connecteurParDefaut = buildConnector({})"
end_marker = "class GestionnaireRequetesSecurise"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start >= 0 and end >= 0:
    block = """function construireConnecteurSecurise () {
\treturn (options, callback) => {
\t\tconst nomServeur = options.servername || options.hostname
\t\tdnsPromises.lookup(nomServeur).then((resultat) => {
\t\t\tif (verifierAdressePrivee(resultat.address)) {
\t\t\t\tcallback(new Error('Adresse non autorisée : ' + nomServeur + ' (' + resultat.address + ')'), null)
\t\t\t\treturn
\t\t\t}
\t\t\tconst port = options.port || (options.protocol === 'https:' ? 443 : 80)
\t\t\tconst socketOptions = { host: resultat.address, port, localAddress: options.localAddress }
\t\t\tconst socket = options.protocol === 'https:'
\t\t\t\t? tls.connect({ ...socketOptions, servername: nomServeur })
\t\t\t\t: net.connect(socketOptions)
\t\t\tsocket.once('error', (erreur) => callback(erreur, null))
\t\t\tsocket.once(options.protocol === 'https:' ? 'secureConnect' : 'connect', () => callback(null, socket))
\t\t}).catch((erreur) => callback(erreur, null))
\t}
}

"""
    text = text[:start] + block + text[end:]
elif "buildConnector" not in text:
    pass
else:
    raise SystemExit("Unexpected DigiStorm LTI source layout")

if "const connecteurParDefaut" in text or "buildConnector" in text:
    raise SystemExit("DigiStorm LTI TLS patch was not applied")

path.write_text(text, encoding="utf-8")
PY
