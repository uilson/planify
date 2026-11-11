#!/usr/bin/env bash
set -Eeuo pipefail

# Meson passes the declared custom-target output as the first argument.
stamp_file="${1:?usage: windows-build.sh <stamp-file>}"
dist_dir="${PWD}/dist"
prefix="${MSYSTEM_PREFIX:-/ucrt64}"

die() {
    printf 'windows-build: ERROR: %s\n' "$*" >&2
    exit 1
}

copy_runtime_dependencies() {
    local binary="$1"
    local ldd_output dependency

    [[ -f "$binary" ]] || die "required binary not found: $binary"
    ldd_output="$(ldd "$binary")" || die "ldd failed for $binary"

    if grep -q 'not found' <<<"$ldd_output"; then
        printf '%s\n' "$ldd_output" >&2
        die "unresolved DLL dependency for $binary"
    fi

    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        [[ -f "$dependency" ]] || die "dependency reported by ldd does not exist: $dependency"
        cp -vu "$dependency" "$dist_dir/bin/"
    done < <(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\/ucrt64\/.*\.dll$/) print $i }' <<<"$ldd_output" | sort -u)
}

copy_required() {
    local source="$1"
    local destination="$2"
    [[ -e "$source" ]] || die "required packaging input not found: $source"
    cp -v "$source" "$destination"
}

rm -rf "$dist_dir"
mkdir -p "$dist_dir/bin"

# Copy dependencies reported by the executable and Planify's shared library.
copy_runtime_dependencies src/io.github.alainm23.planify.exe
copy_runtime_dependencies core/libplanify-0.dll

copy_required "$prefix/bin/gdbus.exe" "$dist_dir/bin/"
cp -v "$prefix"/bin/libgnutls*.dll "$dist_dir/bin/"

# Copy the built Planify executable, shared library, and Chrono subproject.
copy_required src/io.github.alainm23.planify.exe "$dist_dir/bin/"
copy_required core/libplanify-0.dll "$dist_dir/bin/"
copy_required subprojects/chrono/lib/libchrono.dll "$dist_dir/bin/"

# Icon themes.
mkdir -p "$dist_dir/share/icons"
copy_required "$prefix/share/icons/Adwaita" "$dist_dir/share/icons/"
copy_required "$prefix/share/icons/hicolor" "$dist_dir/share/icons/"
copy_required ../data/icons/hicolor "$dist_dir/share/icons/"

# Translations.
mkdir -p "$dist_dir/share/locale"
cp -rv po/* "$dist_dir/share/locale/"

# GLib schemas.
mkdir -p "$dist_dir/share/glib-2.0/schemas"
copy_required ../data/io.github.alainm23.planify.gschema.xml "$dist_dir/share/glib-2.0/schemas/"
glib-compile-schemas "$dist_dir/share/glib-2.0/schemas/"

# Enchant and Hunspell dictionaries.
mkdir -p "$dist_dir/lib/enchant-2"
copy_required "$prefix/lib/enchant-2/enchant_hunspell.dll" "$dist_dir/lib/enchant-2/"
copy_required "$prefix/bin/libhunspell-1.7-0.dll" "$dist_dir/bin/"
copy_required "$prefix/share/hunspell" "$dist_dir/share/"

# GIO OpenSSL module.
mkdir -p "$dist_dir/lib/gio/modules"
copy_required "$prefix/lib/gio/modules/libgioopenssl.dll" "$dist_dir/lib/gio/modules/"

# GStreamer and plugin dependencies.
shopt -s nullglob
gst_dlls=("$prefix"/bin/libgst*.dll)
(("${#gst_dlls[@]}" > 0)) || die "no GStreamer DLLs found under $prefix/bin"
cp -v "${gst_dlls[@]}" "$dist_dir/bin/"
copy_required "$prefix/lib/gstreamer-1.0" "$dist_dir/lib/"
for plugin in "$dist_dir"/lib/gstreamer-1.0/*.dll; do
    copy_runtime_dependencies "$plugin"
done

# libical time-zone data.
copy_required "$prefix/share/libical" "$dist_dir/share/"

# Use a fixed, immutable CLDR release tag rather than the moving main branch.
mkdir -p "$dist_dir/share"
cldr_url="https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/supplemental/windowsZones.xml"
curl --fail --location --retry 3 --output "$dist_dir/share/windowsZones.xml" "$cldr_url"
[[ -s "$dist_dir/share/windowsZones.xml" ]] || die "CLDR windowsZones.xml download is empty"

# Only publish the Meson output marker after every packaging step succeeded.
mkdir -p "$(dirname "$stamp_file")"
touch "$stamp_file"
printf 'Portable distribution created at %s\n' "$dist_dir"
